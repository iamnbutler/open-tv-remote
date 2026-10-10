import Foundation

// Dev harness: drives the real AndroidTVDriver from the command line.
//   harness <host> pair            → starts pairing; write the TV's code to /tmp/atv-code
//   harness <host> keys k1,k2,...  → connects with stored pairing and presses keys
@MainActor
final class Harness: TVDriverDelegate {
    let driver: AndroidTVDriver
    let keys: [RemoteKey]
    let pairing: Bool
    static let deviceFile = URL(fileURLWithPath: "/tmp/atv-device.json")

    init(host: String, pairing: Bool, keys: [RemoteKey]) {
        var device = TVDevice(name: "TV", brand: .androidTV, host: host)
        if let data = try? Data(contentsOf: Self.deviceFile), let saved = try? JSONDecoder().decode(TVDevice.self, from: data) {
            device = saved
        }
        driver = AndroidTVDriver(device: device)
        self.pairing = pairing
        self.keys = keys
        driver.delegate = self
    }

    func start() {
        pairing ? driver.pair() : driver.connect()
    }

    func driver(_ driver: TVDriver, didChangeState state: ConnectionState) {
        print("state:", state)
        switch state {
        case .pairing(.enterCode):
            try? FileManager.default.removeItem(atPath: "/tmp/atv-code")
            print("waiting for code in /tmp/atv-code …")
            pollForCode()
        case .connected:
            Task {
                try? await Task.sleep(for: .milliseconds(800))
                print("  foreground app:", self.driver.currentApp ?? "unknown")
                if let link = ProcessInfo.processInfo.environment["LAUNCH"] {
                    print("launch", link)
                    driver.launch(TVApp(name: "app", launchID: link))
                    try? await Task.sleep(for: .milliseconds(3000))
                    print("  foreground app:", self.driver.currentApp ?? "unknown")
                }
                for key in keys {
                    print("press", key)
                    driver.send(key)
                    try? await Task.sleep(for: .milliseconds(1500))
                    print("  foreground app:", self.driver.currentApp ?? "unknown")
                }
                try? await Task.sleep(for: .seconds(1))
                exit(0)
            }
        case .failed, .unpaired:
            exit(1)
        default: break
        }
    }

    func driver(_ driver: TVDriver, didUpdateDevice device: TVDevice) {
        print("device updated: paired=\(device.isPaired) model=\(device.model ?? "-")")
        try? JSONEncoder().encode(device).write(to: Self.deviceFile)
    }

    private func pollForCode() {
        Task {
            while true {
                if let code = try? String(contentsOfFile: "/tmp/atv-code", encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !code.isEmpty {
                    try? FileManager.default.removeItem(atPath: "/tmp/atv-code")
                    print("submitting code", code)
                    driver.submitPairingCode(code)
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}

setvbuf(stdout, nil, _IONBF, 0)
let args = CommandLine.arguments
let keyMap: [String: RemoteKey] = ["up": .up, "down": .down, "left": .left, "right": .right, "select": .select,
                                   "home": .home, "back": .back, "volup": .volumeUp, "voldown": .volumeDown, "mute": .mute]
let keys = args.count > 3 ? args[3].split(separator: ",").compactMap { keyMap[String($0)] } : []
ClientIdentity.commonName = "FreeRemoteHarness"
MainActor.assumeIsolated {
    let harness = Harness(host: args[1], pairing: args[2] == "pair", keys: keys)
    harness.start()
    Holder.harness = harness
}
RunLoop.main.run()

@MainActor enum Holder { static var harness: Harness? }
