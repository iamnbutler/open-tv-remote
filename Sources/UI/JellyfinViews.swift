import SwiftUI

private let jellyfinPurple = Color(red: 0.42, green: 0.27, blue: 0.82)

// MARK: - Settings (in the TV list)

struct JellyfinSettingsSection: View {
    @Environment(AppModel.self) private var model
    @State private var manualURL = ""
    @State private var username = ""
    @State private var password = ""

    var body: some View {
        @Bindable var jellyfin = model.jellyfin
        Section {
            Toggle("Jellyfin", isOn: $jellyfin.isEnabled)
            if jellyfin.isEnabled { content(jellyfin) }
        } header: {
            Text("Media servers")
        } footer: {
            if !jellyfin.isEnabled {
                Text("Browse your Jellyfin library and play shows and movies on your TV's Jellyfin app.")
            }
        }
    }

    @ViewBuilder
    private func content(_ jellyfin: JellyfinStore) -> some View {
        if let server = jellyfin.server, jellyfin.isReady {
            LabeledContent(server.name, value: server.userName)
            Button("Sign out", role: .destructive) { jellyfin.signOut() }
        } else if let url = jellyfin.signingInTo {
            signIn(jellyfin, url: url)
        } else {
            ForEach(jellyfin.found) { found in
                Button {
                    jellyfin.signIn(to: found.url)
                } label: {
                    LabeledContent(found.info.serverName, value: found.url.host() ?? "")
                }
            }
            if jellyfin.isScanning {
                HStack { ProgressView().controlSize(.small); Text("Looking for servers…").foregroundStyle(.secondary) }
            } else if jellyfin.found.isEmpty {
                Text("No Jellyfin servers found on this network.").font(.footnote).foregroundStyle(.secondary)
            }
            HStack {
                TextField("Server address (e.g. 192.168.1.10:8096)", text: $manualURL)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    #endif
                Button("Connect") {
                    if let url = Self.url(from: manualURL) { jellyfin.signIn(to: url) }
                }
                .disabled(Self.url(from: manualURL) == nil)
            }
            .onAppear { if jellyfin.found.isEmpty { jellyfin.scan() } }
        }
        if let error = jellyfin.signInError {
            Text(error).font(.footnote).foregroundStyle(Theme.power)
        }
    }

    @ViewBuilder
    private func signIn(_ jellyfin: JellyfinStore, url: URL) -> some View {
        if let code = jellyfin.quickConnectCode {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick Connect code").font(.footnote).foregroundStyle(.secondary)
                Text(code).font(.system(size: 34, weight: .bold, design: .monospaced)).textSelection(.enabled)
                Text("In a Jellyfin app you're already signed in to, open your profile → Quick Connect and enter this code.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            Button("Cancel") { jellyfin.cancelSignIn() }
        } else if jellyfin.passwordOnly {
            TextField("Username", text: $username)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
            SecureField("Password", text: $password)
            Button("Sign in") { jellyfin.signIn(to: url, username: username, password: password) }
                .disabled(username.isEmpty)
            Button("Cancel") { jellyfin.cancelSignIn() }
        } else {
            HStack { ProgressView().controlSize(.small); Text("Connecting…").foregroundStyle(.secondary) }
        }
    }

    static func url(from text: String) -> URL? {
        var s = text.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        if !s.contains("://") { s = "http://" + s }
        guard let url = URL(string: s), url.host() != nil else { return nil }
        if url.port == nil, url.scheme == "http", url.path().isEmpty || url.path() == "/" {
            return URL(string: "http://\(url.host()!):8096")
        }
        return url
    }
}

// MARK: - Remote shortcut

struct JellyfinTile: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Button {
            Haptics.tap()
            model.showingJellyfin = true
        } label: {
            Text("Jellyfin")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [jellyfinPurple, Color(red: 0.0, green: 0.64, blue: 0.86)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)))
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel("Jellyfin library")
    }
}

// MARK: - Library browser

struct JellyfinSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var resume: [JellyfinItem] = []
    @State private var nextUp: [JellyfinItem] = []
    @State private var views: [JellyfinItem] = []
    @State private var query = ""
    @State private var results: [JellyfinItem] = []
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                TargetSection()
                if !query.isEmpty {
                    Section("Results") {
                        ForEach(results) { ItemRow(item: $0) }
                    }
                } else {
                    if !resume.isEmpty {
                        Section("Continue watching") { ForEach(resume) { ItemRow(item: $0) } }
                    }
                    if !nextUp.isEmpty {
                        Section("Next up") { ForEach(nextUp) { ItemRow(item: $0) } }
                    }
                    Section("Libraries") {
                        ForEach(views) { view in
                            NavigationLink(value: view) { Label(view.name, systemImage: Self.icon(for: view)) }
                        }
                    }
                }
                if let error {
                    Text(error).foregroundStyle(Theme.power)
                }
            }
            .navigationTitle(model.jellyfin.server?.name ?? "Jellyfin")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: JellyfinItem.self) { item in
                if item.type == "Series" { SeriesView(series: item) } else { FolderView(folder: item) }
            }
            .searchable(text: $query, prompt: "Shows, movies, episodes")
            .task(id: query) { await search() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await load() }
            .safeAreaInset(edge: .bottom) { StatusBar() }
        }
        #if os(macOS)
        .frame(minWidth: 360, idealWidth: 400, maxWidth: 480, minHeight: 560)
        #endif
    }

    private func load() async {
        guard let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else { return }
        do {
            async let r = api.resume(user: user)
            async let n = api.nextUp(user: user)
            async let v = api.views(user: user)
            (resume, nextUp, views) = try await (r, n, v)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func search() async {
        let term = query.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results = (try? await api.search(user: user, term: term)) ?? []
    }

    private static func icon(for view: JellyfinItem) -> String {
        switch view.collectionType {
        case "tvshows": "tv"
        case "movies": "film"
        case "music": "music.note"
        default: "folder"
        }
    }
}

/// Which Jellyfin app on the network we're controlling, and what it's playing.
private struct TargetSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jellyfin = model.jellyfin
        let target = jellyfin.target(for: model.current)
        Section {
            if let target {
                NowPlaying(session: target)
            } else if jellyfin.sessions.isEmpty {
                Text("Jellyfin isn't open on any TV. Pick something to play and the app will open Jellyfin on \(model.current?.name ?? "your TV") first.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if jellyfin.sessions.count > 1 {
                Picker("Play on", selection: Binding(
                    get: { target?.id },
                    set: { id in if let s = jellyfin.sessions.first(where: { $0.id == id }) { jellyfin.choose(s, for: model.current) } }
                )) {
                    Text("Choose…").tag(String?.none)
                    ForEach(jellyfin.sessions) { Text($0.title).tag(Optional($0.id)) }
                }
            }
        }
        .task {
            // Keep the now-playing view fresh while the sheet is open.
            while !Task.isCancelled {
                await jellyfin.refreshSessions()
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private struct NowPlaying: View {
    @Environment(AppModel.self) private var model
    let session: JellyfinSession

    var body: some View {
        let jellyfin = model.jellyfin
        VStack(alignment: .leading, spacing: 10) {
            Text(session.title).font(.caption).foregroundStyle(.secondary)
            if let item = session.nowPlaying {
                Text(item.seriesName.map { "\($0) — \(item.label)" } ?? item.label).font(.headline).lineLimit(2)
                if let position = session.playState?.positionTicks, let total = item.runTimeTicks, total > 0 {
                    ProgressView(value: Double(position), total: Double(total)).tint(jellyfinPurple)
                }
                HStack(spacing: 28) {
                    control("gobackward.30") { jellyfin.send(.seek, to: session, seekBy: -30) }
                    control(session.playState?.isPaused == true ? "play.fill" : "pause.fill") { jellyfin.send(.playPause, to: session) }
                    control("goforward.30") { jellyfin.send(.seek, to: session, seekBy: 30) }
                    control("stop.fill") { jellyfin.send(.stop, to: session) }
                    control("forward.end.fill") { jellyfin.send(.next, to: session) }
                }
                .frame(maxWidth: .infinity)
            } else {
                Text("Nothing playing").foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func control(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 20, weight: .semibold)) }
            .buttonStyle(.borderless)
    }
}

private struct FolderView: View {
    @Environment(AppModel.self) private var model
    let folder: JellyfinItem
    @State private var items: [JellyfinItem]?

    var body: some View {
        List {
            if let items {
                ForEach(items) { ItemRow(item: $0) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(folder.name)
        .task {
            guard let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else { return }
            items = (try? await api.items(user: user, parent: folder.id)) ?? []
        }
        .safeAreaInset(edge: .bottom) { StatusBar() }
    }
}

private struct SeriesView: View {
    @Environment(AppModel.self) private var model
    let series: JellyfinItem
    @State private var seasons: [JellyfinItem] = []
    @State private var season: String?
    @State private var episodes: [JellyfinItem]?

    var body: some View {
        List {
            if seasons.count > 1 {
                Picker("Season", selection: $season) {
                    ForEach(seasons) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            if let episodes {
                ForEach(episodes) { ItemRow(item: $0) }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(series.name)
        .task {
            guard let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else { return }
            seasons = (try? await api.seasons(user: user, series: series.id)) ?? []
            // Start on the first season with something unwatched.
            season = seasons.first { $0.userData?.played != true }?.id ?? seasons.first?.id
        }
        .task(id: season) {
            guard let season, let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else { return }
            episodes = nil
            episodes = (try? await api.episodes(user: user, series: series.id, season: season)) ?? []
        }
        .safeAreaInset(edge: .bottom) { StatusBar() }
    }
}

/// One show, movie or episode. Tapping a playable item plays it on the TV.
private struct ItemRow: View {
    @Environment(AppModel.self) private var model
    let item: JellyfinItem
    @State private var asking = false

    var body: some View {
        if item.isPlayable {
            Button {
                if item.resumeTicks != nil { asking = true } else { play(resume: false) }
            } label: { row }
            .buttonStyle(.plain)
            .confirmationDialog(item.name, isPresented: $asking) {
                Button("Resume") { play(resume: true) }
                Button("Play from the beginning") { play(resume: false) }
            }
        } else {
            NavigationLink(value: item) { row }
        }
    }

    private var row: some View {
        HStack(spacing: 12) {
            AsyncImage(url: model.jellyfin.api?.imageURL(item, width: 240)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.white.opacity(0.06)
            }
            .frame(width: item.type == "Episode" ? 96 : 54, height: 54)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                if let series = item.seriesName, item.type == "Episode" {
                    Text(series).font(.caption).foregroundStyle(.secondary)
                }
                Text(item.label).font(.body.weight(.medium)).lineLimit(2)
                if let year = item.year, item.type != "Episode" {
                    Text(String(year)).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if item.userData?.played == true {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.secondary)
            } else if item.isPlayable {
                Image(systemName: "play.fill").foregroundStyle(jellyfinPurple)
            }
        }
        .contentShape(Rectangle())
    }

    private func play(resume: Bool) {
        Haptics.tap()
        model.jellyfin.play(item, resume: resume, on: model.current) { app in model.launch(app) }
    }
}

/// Progress and errors for the last play request.
private struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jellyfin = model.jellyfin
        Group {
            switch jellyfin.playStatus {
            case .idle: EmptyView()
            case .openingApp: banner("Opening Jellyfin on the TV…", progress: true)
            case .sent(let name): banner("Playing \(name)", progress: false)
            case .failed(let message): banner(message, progress: false, color: Theme.power)
            }
        }
        .task(id: jellyfin.playStatus) {
            if case .sent = jellyfin.playStatus {
                try? await Task.sleep(for: .seconds(3))
                jellyfin.clearStatus()
            }
        }
    }

    private func banner(_ text: String, progress: Bool, color: Color = Theme.label) -> some View {
        HStack(spacing: 10) {
            if progress { ProgressView().controlSize(.small) }
            Text(text).font(.footnote.weight(.semibold)).foregroundStyle(color).lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}
