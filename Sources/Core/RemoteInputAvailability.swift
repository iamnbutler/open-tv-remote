/// Deliberate keyboard commands may use the driver's reconnect path. Continuous
/// gestures require a live connection so stale movement cannot initiate recovery.
struct RemoteInputAvailability {
    var state: ConnectionState
    var showingDevices = false
    var showingKeyboard = false
    var showingApps = false
    var showingSettings = false

    var allowsKeyboardShortcuts: Bool {
        !showingDevices && !showingKeyboard && !showingApps && !showingSettings
    }

    var allowsGestures: Bool {
        state == .connected && allowsKeyboardShortcuts
    }
}
