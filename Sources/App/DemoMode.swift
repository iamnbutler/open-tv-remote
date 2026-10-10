#if DEBUG
import Foundation

/// Debug-only fake TV for App Store screenshots and UI work without touching a real TV.
/// Launch with `-demo` (optionally `-padMode touchpad|keypad`, `-demoSheet apps|devices|keyboard`).
@MainActor
final class DemoDriver: TVDriver {
    let device: TVDevice
    weak var delegate: TVDriverDelegate?
    private(set) var state: ConnectionState = .connected

    init(device: TVDevice) { self.device = device }

    func connect() {
        state = .connected
        delegate?.driver(self, didChangeState: state)
    }

    func pair() {}
    func submitPairingCode(_ code: String) {}
    func disconnect() {}
    func supports(_ key: RemoteKey) -> Bool { true }
    func send(_ key: RemoteKey) {}
    func sendText(_ text: String) {}
    func launch(_ app: TVApp) {}
    func installedApps() async -> [TVApp]? { nil }
}

enum DemoMode {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    static let devices = [
        TVDevice(name: "Living Room TV", brand: .androidTV, host: "192.168.1.20", isPaired: true),
        TVDevice(name: "Bedroom Roku", brand: .roku, host: "192.168.1.31"),
    ]

    static var sheet: String? { UserDefaults.standard.string(forKey: "demoSheet") }
}
#endif
