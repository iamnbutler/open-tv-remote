import SwiftUI

@main
struct OpenRemoteApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 900)
        .windowResizability(.contentMinSize)
        #endif
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            RemoteScreen()
                .toolbar(.hidden)
                .jellyfinDestinations()
        }
            .safeAreaInset(edge: .bottom) { JellyfinStatusBar() }
            #if os(macOS)
            .frame(minWidth: 380, minHeight: 760)
            #endif
            .sheet(isPresented: $model.showingDevices) { DevicesSheet() }
            .sheet(isPresented: $model.showingKeyboard) { KeyboardSheet() }
            .sheet(isPresented: $model.showingApps) { AppsSheet() }
            .sheet(isPresented: pairingPresented) { PairingSheet() }
            .animation(.snappy, value: model.state)
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active: model.sceneDidBecomeActive()
                case .background: model.sceneDidEnterBackground()
                default: break
                }
            }
            .task {
                if model.devices.isEmpty { model.showingDevices = true }
            }
    }

    private var pairingPresented: Binding<Bool> {
        Binding {
            if case .pairing = model.state { return true }
            return false
        } set: { presented in
            if !presented, case .pairing = model.state { model.cancelPairing() }
        }
    }
}
