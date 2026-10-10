import Foundation

/// Sends Wake-on-LAN "magic packets" to turn on TVs whose network connection is asleep.
enum WakeOnLAN {
    /// Parses "aa:bb:cc:dd:ee:ff" or "aa-bb-cc-dd-ee-ff".
    static func macBytes(_ mac: String) -> [UInt8]? {
        let parts = mac.split(whereSeparator: { $0 == ":" || $0 == "-" })
        guard parts.count == 6 else { return nil }
        let bytes = parts.compactMap { UInt8($0, radix: 16) }
        return bytes.count == 6 ? bytes : nil
    }

    /// Sends the packet straight to the TV's last known address and to the local broadcast address.
    /// iOS blocks broadcast without Apple's multicast entitlement, so the unicast copy is what
    /// usually works there (the router still knows the sleeping TV's MAC). On macOS both go out.
    static func wake(mac: String, host: String) {
        guard let bytes = macBytes(mac) else { return }
        let packet = [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: bytes, count: 16).joined())
        for target in [host, "255.255.255.255"] {
            for port: UInt16 in [9, 7] {
                send(packet, to: target, port: port)
            }
        }
    }

    private static func send(_ packet: [UInt8], to host: String, port: UInt16) {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return }
        defer { close(fd) }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &yes, socklen_t(MemoryLayout<Int32>.size))
        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return }
        _ = packet.withUnsafeBytes { buf in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buf.baseAddress, buf.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }
}
