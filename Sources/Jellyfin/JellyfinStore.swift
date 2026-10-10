import Foundation
import Observation
import Security

/// Optional Jellyfin integration: off until the user turns it on, then signs in to one server
/// and plays things on the Jellyfin app running on the TV.
@MainActor
@Observable
final class JellyfinStore {
    struct Server: Codable, Hashable {
        var url: URL
        var name: String
        var id: String
        var userID: String
        var userName: String
    }

    struct Found: Identifiable, Hashable {
        var id: String { info.id }
        let url: URL
        let info: JellyfinServerInfo
    }

    enum PlayStatus: Equatable {
        case idle
        case openingApp
        case sent(String)
        case failed(String)
    }

    var isEnabled = UserDefaults.standard.bool(forKey: Keys.enabled) {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Keys.enabled)
            if !isEnabled { cancelSignIn() }
        }
    }

    private(set) var server: Server? = Keys.loadServer()
    private(set) var found: [Found] = []
    private(set) var isScanning = false
    private(set) var quickConnectCode: String?
    private(set) var passwordOnly = false
    private(set) var signInError: String?
    private(set) var sessions: [JellyfinSession] = []
    private(set) var playStatus: PlayStatus = .idle

    @ObservationIgnored private var signInTask: Task<Void, Never>?
    @ObservationIgnored private var pending: URL?

    var isReady: Bool { isEnabled && api?.token != nil }

    var api: JellyfinAPI? {
        guard let server else { return nil }
        return JellyfinAPI(baseURL: server.url, deviceID: Keys.deviceID, token: Keychain.token(for: server.id))
    }

    // MARK: Finding a server

    /// Jellyfin answers its public info endpoint without signing in, so a quick sweep of the
    /// subnet finds servers. (Its UDP broadcast discovery needs an entitlement on iOS.)
    func scan() {
        guard !isScanning else { return }
        isScanning = true
        found = []
        Task {
            let hosts = LocalNetwork.subnetHosts()
            for chunk in stride(from: 0, to: hosts.count, by: 64).map({ Array(hosts[$0..<min($0 + 64, hosts.count)]) }) {
                let results = await withTaskGroup(of: Found?.self) { group in
                    for host in chunk {
                        group.addTask {
                            guard await PortProbe.isOpen(host, 8096, timeout: 0.6),
                                  let url = URL(string: "http://\(host):8096"),
                                  let info = await JellyfinAPI.publicInfo(url) else { return nil }
                            return Found(url: url, info: info)
                        }
                    }
                    var out: [Found] = []
                    for await result in group { if let result { out.append(result) } }
                    return out
                }
                // A server with both Wi-Fi and Ethernet answers twice; keep one.
                for result in results where !found.contains(where: { $0.id == result.id }) {
                    found.append(result)
                }
            }
            isScanning = false
        }
    }

    // MARK: Signing in

    /// Starts Quick Connect: the user approves our code from a Jellyfin app they're already signed in to.
    func signIn(to url: URL) {
        cancelSignIn()
        pending = url
        signInError = nil
        signInTask = Task {
            let api = JellyfinAPI(baseURL: url, deviceID: Keys.deviceID)
            guard await api.quickConnectEnabled() else {
                passwordOnly = true
                return
            }
            do {
                var state = try await api.initiateQuickConnect()
                quickConnectCode = state.code
                for _ in 0..<150 where !Task.isCancelled && !state.authenticated {
                    try await Task.sleep(for: .seconds(2))
                    state = try await api.quickConnectState(secret: state.secret)
                }
                guard state.authenticated else {
                    if !Task.isCancelled { signInError = "The code expired. Try again." }
                    quickConnectCode = nil
                    return
                }
                finish(try await api.authenticate(quickConnectSecret: state.secret), url: url)
            } catch is CancellationError {
            } catch {
                signInError = error.localizedDescription
                quickConnectCode = nil
            }
        }
    }

    func signIn(to url: URL, username: String, password: String) {
        signInError = nil
        signInTask?.cancel()
        signInTask = Task {
            do {
                let api = JellyfinAPI(baseURL: url, deviceID: Keys.deviceID)
                finish(try await api.authenticate(username: username, password: password), url: url)
            } catch {
                signInError = error.localizedDescription
            }
        }
    }

    func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        quickConnectCode = nil
        passwordOnly = false
        pending = nil
    }

    var signingInTo: URL? { pending }

    private func finish(_ auth: JellyfinAuth, url: URL) {
        Task {
            let info = await JellyfinAPI.publicInfo(url)
            let id = info?.id ?? url.absoluteString
            Keychain.setToken(auth.accessToken, for: id)
            server = Server(url: url, name: info?.serverName ?? url.host() ?? "Jellyfin", id: id,
                            userID: auth.user.id, userName: auth.user.name)
            Keys.saveServer(server)
            cancelSignIn()
        }
    }

    func signOut() {
        if let server { Keychain.setToken(nil, for: server.id) }
        server = nil
        Keys.saveServer(nil)
        sessions = []
    }

    // MARK: Playing on the TV

    func refreshSessions() async {
        guard let api, let server else { return }
        sessions = (try? await api.sessions(user: server.userID)) ?? sessions
    }

    /// The Jellyfin session that belongs to this TV: the one the user picked before, or the only one.
    func target(for tv: TVDevice?) -> JellyfinSession? {
        if let tv, let device = Keys.targets[tv.id], let match = sessions.first(where: { $0.deviceID == device }) {
            return match
        }
        return sessions.count == 1 ? sessions[0] : nil
    }

    func choose(_ session: JellyfinSession, for tv: TVDevice?) {
        guard let tv, let device = session.deviceID else { return }
        Keys.targets[tv.id] = device
    }

    /// Plays an item on the TV's Jellyfin app, opening the app first if it isn't running.
    func play(_ item: JellyfinItem, resume: Bool, on tv: TVDevice?, session chosen: JellyfinSession? = nil,
              launch: @escaping (TVApp) -> Void) {
        guard let api else { return }
        Task {
            await refreshSessions()
            var session = chosen ?? target(for: tv)
            if session == nil {
                guard let tv, let app = Self.launchApp(for: tv.brand) else {
                    playStatus = .failed("Open Jellyfin on your TV, then try again.")
                    return
                }
                let before = Set(sessions.compactMap(\.deviceID))
                playStatus = .openingApp
                launch(app)
                for _ in 0..<20 where session == nil {
                    try? await Task.sleep(for: .seconds(1.5))
                    await refreshSessions()
                    session = sessions.first { !before.contains($0.deviceID ?? "") } ?? target(for: tv)
                }
                guard let session else {
                    playStatus = .failed("Jellyfin didn't show up on the TV. Make sure it's installed and signed in.")
                    return
                }
                choose(session, for: tv)
                // Give the app a moment to finish starting before asking it to play.
                try? await Task.sleep(for: .seconds(2))
            }
            guard let session else { return }
            do {
                try await api.play([item.id], on: session.id, startTicks: resume ? item.resumeTicks : nil)
                playStatus = .sent(item.name)
            } catch {
                playStatus = .failed(error.localizedDescription)
            }
        }
    }

    func send(_ command: JellyfinAPI.PlayState, to session: JellyfinSession, seekBy seconds: Int64? = nil) {
        guard let api else { return }
        Task {
            var ticks: Int64?
            if let seconds {
                let position = session.playState?.positionTicks ?? 0
                ticks = max(0, position + seconds * .ticksPerSecond)
            }
            try? await api.send(command, to: session.id, seekTicks: ticks)
            try? await Task.sleep(for: .milliseconds(600))
            await refreshSessions()
        }
    }

    func clearStatus() { playStatus = .idle }

    /// How to open the Jellyfin app on each kind of TV, where it has one.
    static func launchApp(for brand: TVBrand) -> TVApp? {
        switch brand {
        case .androidTV: TVApp(name: "Jellyfin", launchID: "market://launch?id=org.jellyfin.androidtv")
        case .roku: TVApp(name: "Jellyfin", launchID: "592369")
        case .lg: TVApp(name: "Jellyfin", launchID: "org.jellyfin.webos")
        case .samsung: nil
        }
    }
}

// MARK: - Storage

private enum Keys {
    static let enabled = "jellyfin.enabled"
    static let server = "jellyfin.server.v1"
    static let targetsKey = "jellyfin.targets.v1"
    static let deviceKey = "jellyfin.deviceID"

    static var deviceID: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    static func loadServer() -> JellyfinStore.Server? {
        UserDefaults.standard.data(forKey: server).flatMap { try? JSONDecoder().decode(JellyfinStore.Server.self, from: $0) }
    }

    static func saveServer(_ value: JellyfinStore.Server?) {
        UserDefaults.standard.set(value.flatMap { try? JSONEncoder().encode($0) }, forKey: server)
    }

    /// TV id → Jellyfin device id of the app running on that TV.
    static var targets: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: targetsKey) as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: targetsKey) }
    }
}

private enum Keychain {
    private static func query(_ server: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.natebutler.freeremote.jellyfin",
         kSecAttrAccount as String: server]
    }

    static func token(for server: String) -> String? {
        var q = query(server)
        q[kSecReturnData as String] = true
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func setToken(_ token: String?, for server: String) {
        SecItemDelete(query(server) as CFDictionary)
        guard let token else { return }
        var q = query(server)
        q[kSecValueData as String] = Data(token.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}
