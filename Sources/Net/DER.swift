import Foundation

/// Minimal ASN.1 DER encoding — enough to mint a self-signed X.509 certificate,
/// which Android TV requires as the client's identity.
enum DER {
    static func tlv(_ tag: UInt8, _ content: [UInt8]) -> [UInt8] {
        [tag] + length(content.count) + content
    }

    static func length(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        }
        return [0x80 | UInt8(bytes.count)] + bytes
    }

    static func sequence(_ items: [[UInt8]]) -> [UInt8] { tlv(0x30, items.flatMap { $0 }) }
    static func set(_ items: [[UInt8]]) -> [UInt8] { tlv(0x31, items.flatMap { $0 }) }
    static func explicit(_ n: UInt8, _ content: [UInt8]) -> [UInt8] { tlv(0xA0 | n, content) }
    static let null: [UInt8] = [0x05, 0x00]
    static func boolean(_ v: Bool) -> [UInt8] { [0x01, 0x01, v ? 0xFF : 0x00] }
    static func utf8(_ s: String) -> [UInt8] { tlv(0x0C, Array(s.utf8)) }
    static func octetString(_ b: [UInt8]) -> [UInt8] { tlv(0x04, b) }
    static func bitString(_ b: [UInt8]) -> [UInt8] { tlv(0x03, [0x00] + b) }

    /// Big-endian unsigned integer bytes → DER INTEGER (adds a 0x00 pad when the high bit is set).
    static func integer(_ magnitude: [UInt8]) -> [UInt8] {
        var b = Array(magnitude.drop { $0 == 0 })
        if b.isEmpty { b = [0] }
        if b[0] & 0x80 != 0 { b.insert(0, at: 0) }
        return tlv(0x02, b)
    }

    static func integer(_ n: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        var v = n
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v > 0
        return integer(bytes)
    }

    static func oid(_ dotted: String) -> [UInt8] {
        let parts = dotted.split(separator: ".").compactMap { UInt64($0) }
        var out: [UInt8] = [UInt8(parts[0] * 40 + parts[1])]
        for p in parts.dropFirst(2) {
            var chunk: [UInt8] = [UInt8(p & 0x7F)]
            var v = p >> 7
            while v > 0 {
                chunk.insert(UInt8(v & 0x7F) | 0x80, at: 0)
                v >>= 7
            }
            out += chunk
        }
        return tlv(0x06, out)
    }

    static func time(_ date: Date) -> [UInt8] {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        let year = Calendar(identifier: .gregorian).dateComponents(in: f.timeZone, from: date).year ?? 2000
        if year < 2050 {
            f.dateFormat = "yyMMddHHmmss'Z'"
            return tlv(0x17, Array(f.string(from: date).utf8))
        }
        f.dateFormat = "yyyyMMddHHmmss'Z'"
        return tlv(0x18, Array(f.string(from: date).utf8))
    }

    // MARK: Reading

    /// Parses a PKCS#1 RSAPublicKey (what SecKeyCopyExternalRepresentation returns for RSA)
    /// into its modulus and exponent, with leading zero bytes stripped.
    static func rsaPublicKeyComponents(_ pkcs1: [UInt8]) -> (modulus: [UInt8], exponent: [UInt8])? {
        var i = 0
        guard let seq = read(pkcs1, &i), seq.tag == 0x30 else { return nil }
        var j = 0
        guard let n = read(seq.content, &j), n.tag == 0x02,
              let e = read(seq.content, &j), e.tag == 0x02 else { return nil }
        return (Array(n.content.drop { $0 == 0 }), Array(e.content.drop { $0 == 0 }))
    }

    private static func read(_ b: [UInt8], _ i: inout Int) -> (tag: UInt8, content: [UInt8])? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]
        var len = Int(b[i + 1])
        i += 2
        if len & 0x80 != 0 {
            let count = len & 0x7F
            guard count <= 4, i + count <= b.count else { return nil }
            len = b[i..<i + count].reduce(0) { $0 << 8 | Int($1) }
            i += count
        }
        guard i + len <= b.count else { return nil }
        defer { i += len }
        return (tag, Array(b[i..<i + len]))
    }
}
