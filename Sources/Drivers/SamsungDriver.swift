import Foundation

/// Samsung Tizen TVs (2016+): WebSocket remote channel on port 8002.
/// The first connection shows an Allow/Deny prompt on the TV, after which it issues a token.
@MainActor
final class SamsungDriver: TVDriver {
    private(set) var device: TVDevice
    weak var delegate: TVDriverDelegate?
    private(set) var state: ConnectionState = .idle {
        didSet { if state != oldValue { delegate?.driver(self, didChangeState: state) } }
    }

    private var socket: LocalWebSocket?
    private var playing = true
    /// Keys pressed while (re)connecting, sent once the TV lets us in.
    private var pendingKeys: [String] = []
    private var appsContinuation: CheckedContinuation<[TVApp]?, Never>?

    init(device: TVDevice) {
        self.device = device
    }

    func connect() {
        guard device.token != nil else {
            state = .unpaired
            return
        }
        open(prompting: false)
    }

    func pair() { open(prompting: true) }
    func submitPairingCode(_ code: String) {}

    func disconnect() {
        socket?.close()
        socket = nil
        pendingKeys = []
        state = .idle
    }

    private func open(prompting: Bool) {
        socket?.close()
        let name = Data("Open Remote".utf8).base64EncodedString()
        var components = URLComponents(string: "wss://\(device.host):8002/api/v2/channels/samsung.remote.control")!
        components.queryItems = [URLQueryItem(name: "name", value: name)]
        if let token = device.token, !token.isEmpty {
            components.queryItems?.append(URLQueryItem(name: "token", value: token))
        }
        let ws = LocalWebSocket(url: components.url!)
        state = prompting ? .pairing(.acceptOnTV) : .connecting
        ws.onText = { [weak self] in self?.handle($0) }
        ws.onClose = { [weak self] _ in
            guard let self else { return }
            self.socket = nil
            switch self.state {
            case .connected: self.state = .idle
            case .pairing: self.state = .failed("The TV didn't allow the connection.")
            default: self.state = .failed("Couldn't reach the TV. Is it on and on the same Wi-Fi?")
            }
        }
        socket = ws
        ws.start()
    }

    private func handle(_ text: String) {
        guard let json = JSON.parse(text), let event = json["event"] as? String else { return }
        let data = json["data"] as? [String: Any]
        switch event {
        case "ms.channel.connect":
            // Older models never issue tokens; remember that we've been allowed anyway.
            let token = data?["token"] as? String ?? device.token ?? ""
            if token != device.token {
                device.token = token
                delegate?.driver(self, didUpdateDevice: device)
            }
            state = .connected
            let queued = pendingKeys
            pendingKeys = []
            queued.forEach(sendKey)
        case "ms.channel.unauthorized":
            device.token = nil
            delegate?.driver(self, didUpdateDevice: device)
            socket?.close()
            socket = nil
            state = .failed("The TV denied access. You can allow it under Settings → General → External Device Manager → Device Connection Manager.")
        case "ms.channel.timeOut":
            socket?.close()
            socket = nil
            state = .failed("Timed out waiting for you to allow access on the TV.")
        case "ed.installedApp.get":
            let list = (data?["data"] as? [[String: Any]]) ?? []
            let apps = list.compactMap { entry -> TVApp? in
                guard let id = entry["appId"] as? String, let name = entry["name"] as? String else { return nil }
                let type = entry["app_type"] as? Int
                return TVApp(name: name, launchID: id, extra: type == 4 ? "NATIVE_LAUNCH" : "DEEP_LINK")
            }
            appsContinuation?.resume(returning: apps)
            appsContinuation = nil
        default:
            break
        }
    }

    func supports(_ key: RemoteKey) -> Bool { Self.keyName(key) != nil }

    func send(_ key: RemoteKey) {
        guard var name = Self.keyName(key) else { return }
        if key == .playPause {
            name = playing ? "KEY_PAUSE" : "KEY_PLAY"
            playing.toggle()
        }
        guard state == .connected else {
            guard device.token != nil else { return }
            if pendingKeys.count < 10 { pendingKeys.append(name) }
            if socket == nil { open(prompting: false) }
            return
        }
        sendKey(name)
    }

    private func sendKey(_ name: String) {
        socket?.send(json: [
            "method": "ms.remote.control",
            "params": ["Cmd": "Click", "DataOfCmd": name, "Option": "false", "TypeOfRemote": "SendRemoteKey"],
        ])
    }

    func sendText(_ text: String) {
        guard state == .connected else { return }
        socket?.send(json: [
            "method": "ms.remote.control",
            "params": ["Cmd": Data(text.utf8).base64EncodedString(), "DataOfCmd": "base64", "TypeOfRemote": "SendInputString"],
        ])
    }

    func launch(_ app: TVApp) {
        guard state == .connected else { return }
        socket?.send(json: [
            "method": "ms.channel.emit",
            "params": [
                "event": "ed.apps.launch",
                "to": "host",
                "data": ["appId": app.launchID, "action_type": app.extra ?? "DEEP_LINK"],
            ],
        ])
    }

    func installedApps() async -> [TVApp]? {
        guard state == .connected, let socket else { return nil }
        appsContinuation?.resume(returning: nil)
        return await withCheckedContinuation { continuation in
            appsContinuation = continuation
            socket.send(json: ["method": "ms.channel.emit", "params": ["event": "ed.installedApp.get", "to": "host"]])
            Task {
                try? await Task.sleep(for: .seconds(4))
                appsContinuation?.resume(returning: nil)
                appsContinuation = nil
            }
        }
    }

    private static func keyName(_ key: RemoteKey) -> String? {
        switch key {
        case .power: "KEY_POWER"
        case .up: "KEY_UP"
        case .down: "KEY_DOWN"
        case .left: "KEY_LEFT"
        case .right: "KEY_RIGHT"
        case .select, .enter: "KEY_ENTER"
        case .back, .backspace: "KEY_RETURN"
        case .home: "KEY_HOME"
        case .menu: "KEY_MENU"
        case .info: "KEY_INFO"
        case .input: "KEY_SOURCE"
        case .search: nil
        case .volumeUp: "KEY_VOLUP"
        case .volumeDown: "KEY_VOLDOWN"
        case .mute: "KEY_MUTE"
        case .channelUp: "KEY_CHUP"
        case .channelDown: "KEY_CHDOWN"
        case .playPause: "KEY_PLAY"
        case .rewind: "KEY_REWIND"
        case .fastForward: "KEY_FF"
        case .exit: "KEY_EXIT"
        case .digit(let n): "KEY_\(n)"
        }
    }
}
