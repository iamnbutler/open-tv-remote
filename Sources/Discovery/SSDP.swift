import Foundation

/// Blocking SSDP M-SEARCH over a plain UDP socket. Run off the main thread.
enum SSDP {
    struct Response: Sendable {
        let ip: String
        let headers: [String: String]
    }

    private static let searchTargets = [
        "roku:ecp",
        "urn:samsung.com:device:RemoteControlReceiver:1",
        "urn:lge-com:service:webos-second-screen:1",
    ]

    static func search(timeout: TimeInterval) -> [Response] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var tv = timeval(tv_sec: 0, tv_usec: 250_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var ttl: UInt8 = 4
        setsockopt(fd, IPPROTO_IP, IP_MULTICAST_TTL, &ttl, socklen_t(MemoryLayout<UInt8>.size))

        var dest = sockaddr_in()
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = in_port_t(1900).bigEndian
        dest.sin_addr.s_addr = inet_addr("239.255.255.250")

        for _ in 0..<2 {
            for st in searchTargets {
                let msg = "M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: \"ssdp:discover\"\r\nMX: 2\r\nST: \(st)\r\n\r\n"
                _ = msg.withCString { ptr in
                    withUnsafePointer(to: &dest) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            sendto(fd, ptr, strlen(ptr), 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                        }
                    }
                }
            }
        }

        var responses: [Response] = []
        var buffer = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var from = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            let n = withUnsafeMutablePointer(to: &from) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { recvfrom(fd, &buffer, buffer.count, 0, $0, &len) }
            }
            guard n > 0 else { continue }
            let text = String(decoding: buffer[0..<n], as: UTF8.self)
            var headers: [String: String] = [:]
            for line in text.components(separatedBy: "\r\n") {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].uppercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let ip = String(cString: inet_ntoa(from.sin_addr))
            responses.append(Response(ip: ip, headers: headers))
        }
        // One response per device+target is plenty.
        var seen = Set<String>()
        return responses.filter { seen.insert($0.ip + ($0.headers["ST"] ?? "")).inserted }
    }
}
