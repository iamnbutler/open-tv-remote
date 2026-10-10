import SwiftUI

/// Popular streaming apps and how to launch them on each platform.
/// Tiles are drawn as plain colored wordmarks rather than official logos.
struct CatalogApp: Identifiable, Hashable {
    let id: String
    let name: String
    let background: Color
    let foreground: Color
    let androidLink: String?
    let rokuID: String?
    let samsungID: String?
    let lgID: String?

    func launchID(for brand: TVBrand) -> String? {
        switch brand {
        case .androidTV: androidLink
        case .roku: rokuID
        case .samsung: samsungID
        case .lg: lgID
        }
    }

    func tvApp(for brand: TVBrand) -> TVApp? {
        launchID(for: brand).map { TVApp(name: name, launchID: $0, extra: brand == .samsung ? "DEEP_LINK" : nil) }
    }

    /// Match an installed app (from the TV's own list) back to a catalog entry for coloring.
    static func match(name: String) -> CatalogApp? {
        let n = name.lowercased()
        return all.first { n == $0.name.lowercased() }
            ?? all.first { n.hasPrefix($0.name.lowercased()) }
    }
}

extension CatalogApp {
    private static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }

    static let all: [CatalogApp] = [
        CatalogApp(id: "netflix", name: "Netflix", background: rgb(0x111111), foreground: rgb(0xE50914),
                   androidLink: "https://www.netflix.com/title", rokuID: "12", samsungID: "3201907018807", lgID: "netflix"),
        CatalogApp(id: "youtube", name: "YouTube", background: .white, foreground: rgb(0xFF0000),
                   androidLink: "https://www.youtube.com", rokuID: "837", samsungID: "111299001912", lgID: "youtube.leanback.v4"),
        CatalogApp(id: "prime", name: "Prime Video", background: rgb(0x00A8E1), foreground: .white,
                   androidLink: "https://app.primevideo.com", rokuID: "13", samsungID: "3201910019365", lgID: "amazon"),
        CatalogApp(id: "disney", name: "Disney+", background: rgb(0x0B1F5C), foreground: .white,
                   androidLink: "https://www.disneyplus.com", rokuID: "291097", samsungID: "3201901017640", lgID: "com.disney.disneyplus-prod"),
        CatalogApp(id: "hulu", name: "Hulu", background: rgb(0x1CE783), foreground: rgb(0x0B0C0F),
                   androidLink: "https://www.hulu.com", rokuID: "2285", samsungID: "3201601007625", lgID: "hulu"),
        CatalogApp(id: "max", name: "Max", background: rgb(0x002BE7), foreground: .white,
                   androidLink: "https://play.max.com", rokuID: "61322", samsungID: "3202301029760", lgID: "com.hbo.hbomax"),
        CatalogApp(id: "appletv", name: "Apple TV", background: rgb(0x1C1C1E), foreground: .white,
                   androidLink: "https://tv.apple.com", rokuID: "551012", samsungID: "3201807016597", lgID: "com.apple.appletv"),
        CatalogApp(id: "youtubetv", name: "YouTube TV", background: .white, foreground: rgb(0xCC0000),
                   androidLink: "https://tv.youtube.com", rokuID: "195316", samsungID: "3201707014448", lgID: "youtube.leanback.ytv.v1"),
        CatalogApp(id: "peacock", name: "Peacock", background: rgb(0x000000), foreground: .white,
                   androidLink: "https://www.peacocktv.com", rokuID: "593099", samsungID: "3202006020991", lgID: "com.peacocktv.peacockwebos"),
        CatalogApp(id: "paramount", name: "Paramount+", background: rgb(0x0064FF), foreground: .white,
                   androidLink: "https://www.paramountplus.com", rokuID: "31440", samsungID: "3201710014981", lgID: "com.cbs-ott.2"),
        CatalogApp(id: "spotify", name: "Spotify", background: rgb(0x1DB954), foreground: rgb(0x0B0C0F),
                   androidLink: "spotify://", rokuID: "22297", samsungID: "3201606009684", lgID: "spotify-beehive"),
        CatalogApp(id: "plex", name: "Plex", background: rgb(0x1F2326), foreground: rgb(0xE5A00D),
                   androidLink: "plex://", rokuID: "13535", samsungID: "3201512006963", lgID: "cdp-30"),
    ]
}
