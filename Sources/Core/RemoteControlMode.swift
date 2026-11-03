import Foundation

enum RemoteControlMode: String, CaseIterable, Identifiable {
    case standard, eyesFree
    var id: String { rawValue }
    var title: String {
        switch self {
        case .standard: "Standard"
        case .eyesFree: "Eyes-free"
        }
    }
}

/// Only a view preference is saved. Touches, held directions and pending commands are never restored.
@MainActor
struct RemoteModePreferences {
    private let defaults: UserDefaults
    private static let key = "remoteView.modes.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func mode(for deviceID: String?, available: [RemoteControlMode] = RemoteControlMode.allCases) -> RemoteControlMode {
        guard let deviceID,
              let raw = defaults.dictionary(forKey: Self.key)?[deviceID] as? String,
              let mode = RemoteControlMode(rawValue: raw), available.contains(mode) else { return .standard }
        return mode
    }

    func save(_ mode: RemoteControlMode, for deviceID: String?) {
        guard let deviceID else { return }
        var modes = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        modes[deviceID] = mode.rawValue
        defaults.set(modes, forKey: Self.key)
    }

    func move(from oldID: String, to newID: String) {
        guard oldID != newID else { return }
        var modes = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        guard let mode = modes.removeValue(forKey: oldID) else { return }
        modes[newID] = mode
        defaults.set(modes, forKey: Self.key)
    }

    func forget(_ deviceID: String) {
        var modes = defaults.dictionary(forKey: Self.key) as? [String: String] ?? [:]
        modes.removeValue(forKey: deviceID)
        defaults.set(modes, forKey: Self.key)
    }

    /// The old beta preference applied to its selected TV, not every subsequently selected TV.
    func migrateLegacy(for deviceID: String?) {
        guard let deviceID, let old = defaults.object(forKey: "remoteView.eyesFree.v1") as? Bool else { return }
        if defaults.dictionary(forKey: Self.key)?[deviceID] == nil {
            save(old ? .eyesFree : .standard, for: deviceID)
        }
        defaults.removeObject(forKey: "remoteView.eyesFree.v1")
    }
}
