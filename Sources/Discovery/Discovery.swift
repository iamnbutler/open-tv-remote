import Foundation
import Network
import Observation

struct DiscoveredTV: Identifiable, Hashable {
    var id: String { "\(brand.rawValue)@\(host)" }
    var name: String
    let brand: TVBrand
    let host: String
    var model: String?

    var device: TVDevice { TVDevice(name: name, brand: brand, host: host, model: model) }
}

/// Finds TVs three ways, all of them passive — nothing here shows up on a TV screen:
///  1. Bonjour (`_androidtvremote2._tcp`) for Google TV / Android TV.
///  2. SSDP for Roku, Samsung and LG. (iOS only allows this with Apple's multicast
///     entitlement; on macOS and in the simulator it always works.)
///  3. A quick TCP port sweep of the local subnet, which needs no special entitlement.
@MainActor
@Observable
final class Discovery {
    private(set) var found: [DiscoveredTV] = []
    private(set) var isScanning = false
    /// iOS local network permission was declined (or hasn't been answered yet).
    private(set) var localNetworkDenied = false

    @ObservationIgnored private var browser: NWBrowser?
    @ObservationIgnored private var fallbackTask: Task<Void, Never>?
    @ObservationIgnored private var probeTask: Task<Void, Never>?
    @ObservationIgnored private var probesStarted = false
    @ObservationIgnored private var resolving: Set<String> = []

    /// Bonjour starts first because it's what surfaces the local network permission prompt.
    /// The SSDP/port probes wait until the browser is ready — probing while the prompt is
    /// still up would just fail and miss every TV.
    func start() {
        stop()
        isScanning = true
        probesStarted = false
        startBonjour()
        fallbackTask = Task {
            // If the browser never reports ready (no Wi-Fi, Bonjour hiccup), probe anyway.
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            startProbes()
        }
    }

    func stop() {
        browser?.cancel()
        browser = nil
        fallbackTask?.cancel()
        fallbackTask = nil
        probeTask?.cancel()
        probeTask = nil
        isScanning = false
    }

    private func startProbes() {
        guard !probesStarted, browser != nil else { return }
        if localNetworkDenied {
            isScanning = false
            return
        }
        probesStarted = true
        isScanning = true
        fallbackTask?.cancel()
        probeTask = Task {
            async let ssdp: Void = runSSDP()
            async let sweep: Void = runSweep()
            _ = await (ssdp, sweep)
            if !Task.isCancelled { isScanning = false }
        }
    }

    private func add(_ tv: DiscoveredTV) {
        if let i = found.firstIndex(where: { $0.id == tv.id }) {
            // Prefer a real name over a placeholder.
            if found[i].name.hasPrefix(found[i].brand.shortName) && !tv.name.hasPrefix(tv.brand.shortName) {
                found[i].name = tv.name
            }
            if found[i].model == nil { found[i].model = tv.model }
        } else {
            found.append(tv)
            found.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
    }

    // MARK: Bonjour

    private func startBonjour() {
        let browser = NWBrowser(for: .bonjour(type: "_androidtvremote2._tcp", domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            MainActor.assumeIsolated {
                for result in results {
                    if case .service(let name, _, _, _) = result.endpoint {
                        self?.resolve(result.endpoint, name: name)
                    }
                }
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                guard let self else { return }
                switch state {
                case .ready:
                    self.localNetworkDenied = false
                    self.startProbes()
                case .waiting(let error):
                    // kDNSServiceErr_PolicyDenied: local network access is off for this app.
                    if case .dns(let code) = error, code == -65570 {
                        self.localNetworkDenied = true
                        if !self.probesStarted { self.isScanning = false }
                    }
                case .failed:
                    self.startProbes()
                default:
                    break
                }
            }
        }
        self.browser = browser
        browser.start(queue: .main)
    }

    /// Bonjour gives us a service name; open (and immediately drop) a plain TCP socket to learn its IP.
    private func resolve(_ endpoint: NWEndpoint, name: String) {
        guard !resolving.contains(name) else { return }
        resolving.insert(name)
        let params = NWParameters.tcp
        (params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: params)
        connection.stateUpdateHandler = { [weak self] state in
            MainActor.assumeIsolated {
                switch state {
                case .ready:
                    if case .hostPort(let host, _)? = connection.currentPath?.remoteEndpoint {
                        let ip = Self.string(host)
                        self?.add(DiscoveredTV(name: name, brand: .androidTV, host: ip))
                    }
                    connection.cancel()
                case .failed, .cancelled:
                    self?.resolving.remove(name)
                default:
                    break
                }
            }
        }
        connection.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { connection.cancel() }
    }

    nonisolated static func string(_ host: NWEndpoint.Host) -> String {
        let raw: String
        switch host {
        case .ipv4(let a): raw = "\(a)"
        case .ipv6(let a): raw = "\(a)"
        case .name(let n, _): raw = n
        @unknown default: raw = "\(host)"
        }
        return String(raw.split(separator: "%").first ?? Substring(raw))
    }

    // MARK: SSDP

    private func runSSDP() async {
        let responses = await Task.detached { SSDP.search(timeout: 3) }.value
        await withTaskGroup(of: DiscoveredTV?.self) { group in
            for r in responses {
                group.addTask { await Self.identify(ssdp: r) }
            }
            for await tv in group {
                if let tv { add(tv) }
            }
        }
    }

    nonisolated private static func identify(ssdp r: SSDP.Response) async -> DiscoveredTV? {
        let st = (r.headers["ST"] ?? r.headers["NT"] ?? "") + " " + (r.headers["USN"] ?? "")
        let server = r.headers["SERVER"] ?? ""
        if st.contains("roku:ecp") || server.contains("Roku") {
            return await rokuInfo(r.ip)
        }
        if st.contains("samsung.com:device:RemoteControlReceiver") {
            return await samsungInfo(r.ip)
        }
        if st.contains("lge-com:service:webos-second-screen") {
            var name = "LG TV"
            if let loc = r.headers["LOCATION"].flatMap(URL.init(string:)), let xml = await LocalHTTP.get(loc) {
                name = XMLText.first("friendlyName", in: xml) ?? name
            }
            return DiscoveredTV(name: name, brand: .lg, host: r.ip)
        }
        return nil
    }

    // MARK: Subnet sweep

    private func runSweep() async {
        let hosts = LocalNetwork.subnetHosts()
        guard !hosts.isEmpty else { return }
        for batch in stride(from: 0, to: hosts.count, by: 48).map({ Array(hosts[$0..<min($0 + 48, hosts.count)]) }) {
            if Task.isCancelled { return }
            await withTaskGroup(of: DiscoveredTV?.self) { group in
                for host in batch {
                    group.addTask { await Self.probe(host) }
                }
                for await tv in group {
                    if let tv { add(tv) }
                }
            }
        }
    }

    nonisolated private static func probe(_ host: String) async -> DiscoveredTV? {
        async let roku = PortProbe.isOpen(host, 8060)
        async let atvRemote = PortProbe.isOpen(host, 6466)
        async let atvPair = PortProbe.isOpen(host, 6467)
        async let samsung = PortProbe.isOpen(host, 8001)
        async let lgPlain = PortProbe.isOpen(host, 3000)
        async let lgSecure = PortProbe.isOpen(host, 3001)
        let (r, a1, a2, s, l1, l2) = await (roku, atvRemote, atvPair, samsung, lgPlain, lgSecure)

        if r, let tv = await rokuInfo(host) { return tv }
        if a1 && a2 {
            var name = "Google TV"
            if let xml = await LocalHTTP.get(URL(string: "http://\(host):8008/ssdp/device-desc.xml")!) {
                name = XMLText.first("friendlyName", in: xml) ?? name
            }
            return DiscoveredTV(name: name, brand: .androidTV, host: host)
        }
        if s, let tv = await samsungInfo(host) { return tv }
        // Both webOS ports open is a strong enough signal (a lone :3000 is often a dev server).
        if l1 && l2 { return DiscoveredTV(name: "LG TV", brand: .lg, host: host) }
        return nil
    }

    nonisolated private static func rokuInfo(_ host: String) async -> DiscoveredTV? {
        guard let data = await LocalHTTP.get(URL(string: "http://\(host):8060/query/device-info")!) else { return nil }
        let name = XMLText.first("user-device-name", in: data)
            ?? XMLText.first("friendly-device-name", in: data)
            ?? "Roku"
        return DiscoveredTV(name: name, brand: .roku, host: host, model: XMLText.first("model-name", in: data))
    }

    nonisolated private static func samsungInfo(_ host: String) async -> DiscoveredTV? {
        guard let data = await LocalHTTP.get(URL(string: "http://\(host):8001/api/v2/")!),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let info = json["device"] as? [String: Any]
        let name = (info?["name"] as? String) ?? (json["name"] as? String) ?? "Samsung TV"
        return DiscoveredTV(name: XMLText.unescape(name), brand: .samsung, host: host, model: info?["modelName"] as? String)
    }
}

enum PortProbe {
    private static let queue = DispatchQueue(label: "freeremote.probe")

    /// TCP connect-and-drop. Nothing is sent, so the TV never notices.
    static func isOpen(_ host: String, _ port: UInt16, timeout: TimeInterval = 0.9) async -> Bool {
        await withCheckedContinuation { continuation in
            let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
            var done = false
            let finish: (Bool) -> Void = { open in
                guard !done else { return }
                done = true
                connection.cancel()
                continuation.resume(returning: open)
            }
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready: finish(true)
                case .failed, .waiting: finish(false)
                default: break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(false) }
        }
    }
}
