import Foundation

/// Settings that follow someone to their other devices through iCloud's key-value store.
///
/// Each device reads its own UserDefaults; iCloud carries writes between devices and the last
/// write wins. The first time a device joins, its settings are merged with what's already there
/// instead of being replaced. Pairing credentials never go through here: they belong to one device.
@MainActor
enum CloudSettings {
    /// Posted after settings from another device land in UserDefaults; `userInfo["keys"]` lists them.
    static let didChange = Notification.Name("CloudSettings.didChange")

    static let appChoices = "apps.visible.v1"
    static let jellyfinEnabled = "jellyfin.enabled"
    static let jellyfinServer = "jellyfin.server.v1"
    static let jellyfinPins = "jellyfin.pins.v1"
    static let devices = "devices.shared.v1"

    private static let keys = [appChoices, jellyfinEnabled, jellyfinServer, jellyfinPins, devices]
    private static let joinedKey = "cloud.joined.v1"
    /// Stands in for a removed value, so "removed on another device" differs from "never set".
    private static let removed = Data()

    private static var store: NSUbiquitousKeyValueStore { .default }

    /// Sorted keys keep the same value byte-for-byte, so an unchanged setting isn't re-uploaded.
    static func encode(_ value: some Encodable) -> Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try? encoder.encode(value)
    }
    private static var defaults: UserDefaults { .standard }

    static func set(_ value: Any?, forKey key: String) {
        #if DEBUG
        if DemoMode.isEnabled { return }
        #endif
        defaults.set(value, forKey: key)
        let shared = value ?? removed
        if !same(store.object(forKey: key), shared) {
            store.set(shared, forKey: key)
        }
    }

    /// Pulls in what other devices wrote, shares what only this device has, and keeps listening.
    static func start() {
        #if DEBUG
        if DemoMode.isEnabled { return }
        #endif
        NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { note in
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String] ?? keys
            MainActor.assumeIsolated {
                // A different iCloud account brings its own settings; merge with them like a first join.
                if reason == NSUbiquitousKeyValueStoreAccountChange { defaults.set(false, forKey: joinedKey) }
                pull(changed.filter(keys.contains))
            }
        }
        store.synchronize()
        pull(keys)
    }

    private static func pull(_ changed: [String]) {
        let joined = defaults.bool(forKey: joinedKey)
        var updated: [String] = []
        for key in changed {
            let local = defaults.object(forKey: key)
            guard let cloud = store.object(forKey: key) else {
                if let local { store.set(local, forKey: key) }
                continue
            }
            var value: Any? = (cloud as? Data) == removed ? nil : cloud
            if !joined, let local, let incoming = value {
                value = merge(key, local: local, cloud: incoming)
                if !same(value, cloud) { store.set(value, forKey: key) }
            }
            if !same(value, local) {
                defaults.set(value, forKey: key)
                updated.append(key)
            }
        }
        defaults.set(true, forKey: joinedKey)
        if !updated.isEmpty {
            NotificationCenter.default.post(name: didChange, object: nil, userInfo: ["keys": updated])
        }
    }

    private static func same(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a?, b?): (a as AnyObject).isEqual(b)
        default: false
        }
    }

    /// Combines this device's settings with the cloud's the first time it joins, so nothing is lost.
    private static func merge(_ key: String, local: Any, cloud: Any) -> Any {
        switch key {
        case appChoices:
            guard let local = local as? [String: Bool], let cloud = cloud as? [String: Bool] else { return cloud }
            return local.merging(cloud) { _, cloud in cloud }
        case jellyfinEnabled:
            return (local as? Bool ?? false) || (cloud as? Bool ?? false)
        case jellyfinPins:
            return union(JellyfinStore.Pin.self, local, cloud) { "\($0.server)/\($0.item.id)" }
        case devices:
            return union(TVDevice.self, local, cloud, by: \.id)
        default:
            return cloud
        }
    }

    /// The cloud's list, followed by anything only this device had.
    private static func union<T: Codable, ID: Hashable>(_: T.Type, _ local: Any, _ cloud: Any, by id: (T) -> ID) -> Any {
        let decoder = JSONDecoder()
        guard let localData = local as? Data, let cloudData = cloud as? Data,
              let mine = try? decoder.decode([T].self, from: localData),
              let theirs = try? decoder.decode([T].self, from: cloudData) else { return cloud }
        let seen = Set(theirs.map(id))
        return encode(theirs + mine.filter { !seen.contains(id($0)) }) ?? cloud
    }
}
