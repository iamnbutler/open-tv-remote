import Foundation

enum PairingPrompt: Equatable, Sendable {
    /// The TV is showing a code the user must type in.
    case enterCode(length: Int, error: String?)
    /// The TV is showing an Allow / Deny dialog.
    case acceptOnTV
    /// We've sent the code and are waiting for the TV to confirm it.
    case verifying
}

enum ConnectionState: Equatable, Sendable {
    case idle
    case connecting
    /// We have no credentials yet. Pairing only starts when the user asks,
    /// so nothing pops up on a TV someone else is watching.
    case unpaired
    case pairing(PairingPrompt)
    case connected
    case failed(String)

    var isConnected: Bool { self == .connected }
}

/// Something the TV can open: either an installed app reported by the TV, or a catalog entry.
struct TVApp: Identifiable, Hashable, Sendable {
    var id: String { launchID }
    let name: String
    /// Driver-specific: Roku channel ID, Samsung/LG app ID, or Android TV app link.
    let launchID: String
    var iconURL: URL?
    /// Samsung needs to know whether an app launches as a deep link or native app.
    var extra: String?
}

@MainActor
protocol TVDriverDelegate: AnyObject {
    func driver(_ driver: TVDriver, didChangeState state: ConnectionState)
    /// Called when the driver learns something worth persisting (tokens, names, pairing).
    func driver(_ driver: TVDriver, didUpdateDevice device: TVDevice)
}

@MainActor
protocol TVDriver: AnyObject {
    var device: TVDevice { get }
    var delegate: TVDriverDelegate? { get set }
    var state: ConnectionState { get }

    /// Connect with stored credentials. Must never cause anything to appear on the TV.
    func connect()
    /// Start pairing. This *will* show a code or prompt on the TV.
    func pair()
    func submitPairingCode(_ code: String)
    func disconnect()

    func supports(_ key: RemoteKey) -> Bool
    func send(_ key: RemoteKey)
    func sendText(_ text: String)
    /// Whether `editText` reaches the TV as the user types. Otherwise text goes over with `sendText` on submit.
    var typesLive: Bool { get }
    /// Brings the TV's focused text field from `old` to `new`.
    func editText(from old: String, to new: String)
    func launch(_ app: TVApp)
    /// Apps installed on the TV, or nil if the protocol can't list them.
    func installedApps() async -> [TVApp]?
}

extension TVDriver {
    var typesLive: Bool { false }
    func editText(from old: String, to new: String) {}
}

extension String {
    /// How many characters `self` and `other` share at the start.
    func commonPrefixCount(with other: String) -> Int {
        zip(self, other).prefix { $0 == $1 }.count
    }
}
