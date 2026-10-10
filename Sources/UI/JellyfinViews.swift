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

// MARK: - Rows on the remote

/// Continue watching and libraries, shown under the app shortcuts once signed in to Jellyfin.
struct JellyfinRows: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jellyfin = model.jellyfin
        VStack(alignment: .leading, spacing: 14) {
            if !jellyfin.resume.isEmpty {
                row("Continue watching") {
                    ForEach(jellyfin.resume) { item in
                        Button {
                            Haptics.tap()
                            jellyfin.play(item, resume: true, on: model.current) { model.launch($0) }
                        } label: {
                            Card(item: item, title: item.seriesName ?? item.name,
                                 subtitle: item.type == "Episode" ? item.label : nil, progress: item.progress)
                        }
                        .buttonStyle(PressScaleStyle())
                        .contextMenu {
                            Button("Play from the beginning", systemImage: "backward.end") {
                                jellyfin.play(item, resume: false, on: model.current) { model.launch($0) }
                            }
                            PinButton(item: item.pinTarget)
                        }
                    }
                }
            }
            if !jellyfin.libraries.isEmpty {
                row("Libraries") {
                    ForEach(jellyfin.libraries) { library in
                        NavigationLink(value: JellyfinRoute.library(library)) {
                            Card(item: library, title: library.name, subtitle: nil, progress: nil)
                        }
                        .buttonStyle(PressScaleStyle())
                        .contextMenu { PinButton(item: library) }
                    }
                }
            }
            if jellyfin.sessions.count > 1 {
                SessionPicker()
            }
        }
        .task(id: jellyfin.server) {
            await jellyfin.refreshHome()
            // Keep now playing and the session list current while the remote is on screen.
            while !Task.isCancelled {
                await jellyfin.refreshSessions()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionTitle(title)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) { content() }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }
            .padding(.horizontal, -20)
        }
    }
}

/// A 16:9 picture with a title under it.
private struct Card: View {
    @Environment(AppModel.self) private var model
    let item: JellyfinItem
    let title: String
    let subtitle: String?
    let progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            AsyncImage(url: model.jellyfin.api?.imageURL(item, width: 400, wide: true)) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ZStack {
                    Color.white.opacity(0.06)
                    Image(systemName: "film").foregroundStyle(Theme.secondary)
                }
            }
            .frame(width: 168, height: 94)
            .overlay(alignment: .bottom) {
                if let progress {
                    GeometryReader { g in
                        Capsule().fill(.white.opacity(0.25)).overlay(alignment: .leading) {
                            Capsule().fill(jellyfinPurple).frame(width: g.size.width * progress)
                        }
                    }
                    .frame(height: 4)
                    .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.label).lineLimit(1)
                if let subtitle {
                    Text(subtitle).font(.system(size: 11)).foregroundStyle(Theme.secondary).lineLimit(1)
                }
            }
            .frame(width: 168, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// Which Jellyfin app to control when more than one is open.
private struct SessionPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let jellyfin = model.jellyfin
        let target = jellyfin.target(for: model.current)
        Menu {
            ForEach(jellyfin.sessions) { session in
                Button(session.title) { jellyfin.choose(session, for: model.current) }
            }
        } label: {
            Label("Jellyfin plays on: \(target?.title ?? "choose…")", systemImage: "play.tv")
                .font(.footnote.weight(.semibold))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondary)
    }
}

enum JellyfinRoute: Hashable {
    case library(JellyfinItem)
    case series(JellyfinItem)
}

extension View {
    func jellyfinDestinations() -> some View {
        navigationDestination(for: JellyfinRoute.self) { route in
            switch route {
            case .library(let item): LibraryGallery(folder: item)
            case .series(let item): SeriesView(series: item)
            }
        }
    }
}

// MARK: - Library gallery

private struct LibraryGallery: View {
    @Environment(AppModel.self) private var model
    let folder: JellyfinItem
    @State private var items: [JellyfinItem]?
    @State private var query = ""

    var body: some View {
        ScrollView {
            if let items {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 14)], spacing: 18) {
                    ForEach(items) { Poster(item: $0) }
                }
                .padding(20)
                if items.isEmpty {
                    Text(query.isEmpty ? "This library is empty." : "Nothing matches.").foregroundStyle(Theme.secondary)
                }
            } else {
                ProgressView().padding(40)
            }
        }
        .background(Theme.background)
        .navigationTitle(folder.name)
        .searchable(text: $query, prompt: "Search \(folder.name)")
        .task(id: query) {
            guard let api = model.jellyfin.api, let user = model.jellyfin.server?.userID else { return }
            let term = query.trimmingCharacters(in: .whitespaces)
            if !term.isEmpty { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled else { return }
            items = (try? await api.items(user: user, parent: folder.id, search: term.isEmpty ? nil : term)) ?? []
        }
    }
}

/// A 2:3 poster. Shows and folders open; movies play.
private struct Poster: View {
    @Environment(AppModel.self) private var model
    let item: JellyfinItem
    @State private var asking = false

    var body: some View {
        if item.isPlayable {
            Button {
                if item.resumeTicks != nil { asking = true } else { play(resume: false) }
            } label: { poster }
            .buttonStyle(PressScaleStyle())
            .contextMenu { PinButton(item: item) }
            .confirmationDialog(item.name, isPresented: $asking) {
                Button("Resume") { play(resume: true) }
                Button("Play from the beginning") { play(resume: false) }
            }
        } else {
            NavigationLink(value: item.type == "Series" ? JellyfinRoute.series(item) : JellyfinRoute.library(item)) { poster }
                .buttonStyle(PressScaleStyle())
                .contextMenu { PinButton(item: item) }
        }
    }

    private var poster: some View {
        VStack(alignment: .leading, spacing: 5) {
            Color.white.opacity(0.06)
                .aspectRatio(2 / 3, contentMode: .fit)
                .overlay {
                    AsyncImage(url: model.jellyfin.api?.imageURL(item, width: 300)) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Text(item.name).font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                            .multilineTextAlignment(.center).padding(6)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if item.userData?.played == true {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, jellyfinPurple).padding(6)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(item.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.label).lineLimit(1)
            if let year = item.year {
                Text(String(year)).font(.system(size: 11)).foregroundStyle(Theme.secondary)
            }
        }
        .contentShape(Rectangle())
    }

    private func play(resume: Bool) {
        Haptics.tap()
        model.jellyfin.play(item, resume: resume, on: model.current) { model.launch($0) }
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

private struct SeriesView: View {
    @Environment(AppModel.self) private var model
    let series: JellyfinItem
    @State private var seasons: [JellyfinItem] = []
    @State private var season: String?
    @State private var episodes: [JellyfinItem]?

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    bigButton("Next episode", systemImage: "play.fill", filled: true) {
                        model.jellyfin.playNext(in: series, on: model.current) { model.launch($0) }
                    }
                    bigButton("Shuffle", systemImage: "shuffle", filled: false) {
                        model.jellyfin.shuffle(series, on: model.current) { model.launch($0) }
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
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
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                let pinned = model.jellyfin.isPinned(series)
                Button(pinned ? "Unpin" : "Pin to Watch", systemImage: pinned ? "pin.slash" : "pin") {
                    model.jellyfin.togglePin(series)
                }
            }
        }
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
    }
}

extension SeriesView {
    fileprivate func bigButton(_ title: String, systemImage: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(filled ? Color.white : Theme.label)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(filled ? jellyfinPurple : Color.white.opacity(0.08)))
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Pins and now playing

/// Pin or unpin something on the Watch page.
private struct PinButton: View {
    @Environment(AppModel.self) private var model
    let item: JellyfinItem?

    var body: some View {
        if let item {
            let pinned = model.jellyfin.isPinned(item)
            Button(pinned ? "Unpin \(item.name)" : "Pin \(item.name) to Watch", systemImage: pinned ? "pin.slash" : "pin") {
                model.jellyfin.togglePin(item)
            }
        }
    }
}

/// Big posters for the things pinned to the Watch page. Shows open with Next episode and Shuffle.
struct JellyfinPinnedGrid: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle("Pinned")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 14)], spacing: 16) {
                ForEach(model.jellyfin.pins) { Poster(item: $0) }
            }
        }
    }
}

struct JellyfinNowPlayingCard: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let target = model.jellyfin.target(for: model.current), target.nowPlaying != nil {
            NowPlaying(session: target)
                .padding(14)
                .background(KeySurface(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        }
    }
}

extension JellyfinItem {
    /// What "pin" means for this item: an episode pins its show.
    var pinTarget: JellyfinItem? {
        guard type == "Episode" else { return self }
        guard let seriesID else { return nil }
        return JellyfinItem(id: seriesID, name: seriesName ?? name, type: "Series", collectionType: nil, seriesName: nil,
                            seriesID: nil, seasonNumber: nil, episodeNumber: nil, year: nil, overview: nil,
                            runTimeTicks: nil, imageTags: ["Primary": ""], userData: nil)
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
            NavigationLink(value: item.type == "Series" ? JellyfinRoute.series(item) : JellyfinRoute.library(item)) { row }
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
struct JellyfinStatusBar: View {
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
