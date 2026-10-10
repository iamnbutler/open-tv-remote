import Foundation

enum TVBrand: String, Codable, CaseIterable, Identifiable, Sendable {
    case androidTV
    case roku
    case samsung
    case lg

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .androidTV: "Google TV / Android TV"
        case .roku: "Roku"
        case .samsung: "Samsung"
        case .lg: "LG webOS"
        }
    }

    var shortName: String {
        switch self {
        case .androidTV: "Google TV"
        case .roku: "Roku"
        case .samsung: "Samsung"
        case .lg: "LG"
        }
    }

    /// Shown before pairing so people know what's about to appear on their TV.
    var pairingExplanation: String {
        switch self {
        case .androidTV: "Your TV will show a 6-character code. Type it here to finish pairing."
        case .roku: "Roku TVs don't need pairing."
        case .samsung: "Your TV will ask whether to allow Open Remote. Choose Allow with your regular remote."
        case .lg: "Your TV will ask whether to accept the connection. Choose Accept with your regular remote."
        }
    }

    var examples: String {
        switch self {
        case .androidTV: "Sony, TCL, Hisense, Philips, Sharp, Chromecast with Google TV, Nvidia Shield"
        case .roku: "Roku TVs, Roku sticks and boxes"
        case .samsung: "Samsung Tizen smart TVs (2016+)"
        case .lg: "LG smart TVs running webOS"
        }
    }
}

struct TVDevice: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(brand.rawValue)@\(host)" }
    var name: String
    var brand: TVBrand
    var host: String
    var model: String?
    /// Samsung access token or LG client key, issued by the TV when the user allows us.
    var token: String?
    /// Android TV: the TV has accepted our client certificate.
    var isPaired: Bool = false
    /// Samsung: Wi-Fi/Ethernet MAC, so we can wake the TV with a Wake-on-LAN packet.
    var macAddress: String?

    /// What another device may know about this TV: pairing is between one device and the TV.
    var withoutCredentials: TVDevice {
        var shared = self
        shared.token = nil
        shared.isPaired = false
        return shared
    }

    var hasCredentials: Bool {
        switch brand {
        case .roku: true
        case .androidTV: isPaired
        case .samsung, .lg: token != nil
        }
    }
}

@MainActor
enum DeviceStore {
    private static let devicesKey = "devices.v1"
    private static let currentKey = "currentDevice.v1"

    static func load() -> [TVDevice] {
        guard let data = UserDefaults.standard.data(forKey: devicesKey),
              let devices = try? JSONDecoder().decode([TVDevice].self, from: data) else { return [] }
        return devices
    }

    static func save(_ devices: [TVDevice]) {
        if let data = try? JSONEncoder().encode(devices) {
            UserDefaults.standard.set(data, forKey: devicesKey)
        }
        CloudSettings.set(CloudSettings.encode(devices.map(\.withoutCredentials)), forKey: CloudSettings.devices)
    }

    /// The TVs saved on all of the user's devices, without pairing credentials.
    static func loadShared() -> [TVDevice]? {
        UserDefaults.standard.data(forKey: CloudSettings.devices).flatMap { try? JSONDecoder().decode([TVDevice].self, from: $0) }
    }

    static var currentID: String? {
        get { UserDefaults.standard.string(forKey: currentKey) }
        set { UserDefaults.standard.set(newValue, forKey: currentKey) }
    }
}
