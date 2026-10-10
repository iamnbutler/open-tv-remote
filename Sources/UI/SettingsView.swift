import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showingDevices = false

    var body: some View {
        NavigationStack {
            Form {
                Section("TV") {
                    Button {
                        showingDevices = true
                    } label: {
                        LabeledContent(model.current?.name ?? "No TV chosen", value: model.current.map { $0.brand.shortName } ?? "Choose…")
                    }
                    .buttonStyle(.plain)
                }

                JellyfinSettingsSection()

                if model.jellyfin.isReady && !model.jellyfin.pins.isEmpty {
                    Section {
                        ForEach(model.jellyfin.pins) { pin in
                            Label(pin.name, systemImage: pin.type == "Series" ? "tv" : pin.type == "Movie" ? "film" : "folder")
                        }
                        .onMove { model.jellyfin.movePins(from: $0, to: $1) }
                        .onDelete { model.jellyfin.removePins(at: $0) }
                    } header: {
                        Text("Pinned")
                    } footer: {
                        Text("Pin shows, movies and libraries from the Watch page: long-press one and choose Pin.")
                    }
                }

                if model.current != nil {
                    Section {
                        ForEach(model.allApps, id: \.app.id) { entry in
                            Toggle(entry.app.name, isOn: Binding {
                                model.isShown(entry.app)
                            } set: {
                                model.setShown(entry.app, $0)
                            })
                        }
                    } header: {
                        Text("Apps on the Watch page")
                    } footer: {
                        Text(model.installedApps == nil
                             ? "Your TV doesn't share its app list, so these are popular apps."
                             : "These are the apps installed on your TV.")
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Free and open source", systemImage: "heart.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                        Text("No subscriptions, no trials, no ads, no tracking, no account. Open Remote talks directly to your TV over your Wi-Fi and nothing leaves your home network.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Link("View the source on GitHub", destination: URL(string: "https://github.com/iamnbutler/open-tv-remote")!)
                            .font(.footnote.weight(.semibold))
                        Link("App icons adapted from selfh.st", destination: URL(string: "https://selfh.st/icons/")!)
                            .font(.footnote)
                        Link("CC BY 4.0 license", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                            .font(.footnote)
                    }
                    .padding(.vertical, 4)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                if model.jellyfin.isReady && !model.jellyfin.pins.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                }
            }
            #endif
            .sheet(isPresented: $showingDevices) { DevicesSheet() }
        }
        #if os(macOS)
        .frame(width: 460, height: 620)
        #endif
    }
}

/// Opens settings: the Settings window on the Mac, a sheet elsewhere.
struct SettingsButton: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        #if os(macOS)
        SettingsLink { icon }
            .buttonStyle(.plain)
        #else
        Button { model.showingSettings = true } label: { icon }
            .buttonStyle(.plain)
        #endif
    }

    private var icon: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.label)
            .frame(width: 44, height: 44)
            .background(KeySurface(shape: Circle()))
            .accessibilityLabel("Settings")
    }
}
