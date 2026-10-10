import Foundation

enum LocalNetwork {
    struct Interface {
        let address: UInt32 // host byte order
        let netmask: UInt32
    }

    /// The primary IPv4 interface (Wi-Fi / Ethernet), if any.
    static func primaryIPv4() -> Interface? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var candidates: [(name: String, iface: Interface)] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                  let mask = ifa.ifa_netmask,
                  (Int32(ifa.ifa_flags) & IFF_UP) != 0, (Int32(ifa.ifa_flags) & IFF_LOOPBACK) == 0 else { continue }
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("en") else { continue }
            let a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            candidates.append((name, Interface(address: a, netmask: m)))
        }
        return candidates.sorted { $0.name < $1.name }.first?.iface
    }

    /// Every host address on the local subnet, capped to a /22 so a scan stays quick.
    static func subnetHosts() -> [String] {
        guard let iface = primaryIPv4() else { return [] }
        let mask = max(iface.netmask, 0xFFFF_FC00)
        let network = iface.address & mask
        let broadcast = network | ~mask
        guard broadcast > network + 1 else { return [] }
        return (network + 1..<broadcast).filter { $0 != iface.address }.map(format)
    }

    static func format(_ a: UInt32) -> String {
        "\(a >> 24 & 0xFF).\(a >> 16 & 0xFF).\(a >> 8 & 0xFF).\(a & 0xFF)"
    }

    static func isPrivateAddress(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 {
            switch (parts[0], parts[1]) {
            case (10, _), (192, 168), (169, 254): return true
            case (172, 16...31): return true
            default: return false
            }
        }
        return host.hasSuffix(".local") || host.hasPrefix("fe80") || host.hasPrefix("fd")
    }

    static func isValidIPv4(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { Int($0).map { (0...255).contains($0) } ?? false }
    }
}
