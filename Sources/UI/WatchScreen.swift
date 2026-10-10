import SwiftUI

/// The second page: things to watch. Pinned Jellyfin items, app shortcuts, and Jellyfin rows.
struct WatchScreen: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jellyfin = model.jellyfin
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                if jellyfin.isReady {
                    JellyfinNowPlayingCard()
                    if !jellyfin.pins.isEmpty {
                        JellyfinPinnedGrid()
                    }
                }
                apps
                if jellyfin.isReady {
                    JellyfinRows()
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 20)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
    }

    private var header: some View {
        HStack {
            Text("Watch").font(.system(size: 28, weight: .bold, design: .rounded))
            Spacer()
            #if os(macOS)
            SettingsLink { settingsIcon }
                .buttonStyle(.plain)
            #else
            Button { model.showingSettings = true } label: { settingsIcon }
                .buttonStyle(.plain)
            #endif
        }
        .frame(height: 48)
    }

    private var settingsIcon: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(Theme.label)
            .frame(width: 44, height: 44)
            .background(KeySurface(shape: Circle()))
            .accessibilityLabel("Settings")
    }

    @ViewBuilder private var apps: some View {
        if model.current != nil {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Apps")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
                    ForEach(model.watchApps, id: \.app.id) { entry in
                        AppTile(app: entry.app, style: entry.style) { model.launch(entry.app) }
                            .frame(height: 56)
                    }
                    Button { model.showingApps = true } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "square.grid.2x2.fill").font(.system(size: 16, weight: .semibold))
                            Text("All apps").font(.system(size: 11, weight: .semibold, design: .rounded))
                        }
                        .foregroundStyle(Theme.label)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(KeySurface(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SectionTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.8)
            .foregroundStyle(Theme.secondary)
    }
}
