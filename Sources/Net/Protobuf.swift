import Foundation

/// Just enough protobuf to speak the Android TV remote protocol without a dependency.
struct ProtoWriter {
    private(set) var bytes: [UInt8] = []

    static func varint(_ value: UInt64) -> [UInt8] {
        var v = value
        var out: [UInt8] = []
        repeat {
            var byte = UInt8(v & 0x7F)
            v >>= 7
            if v != 0 { byte |= 0x80 }
            out.append(byte)
        } while v != 0
        return out
    }

    private mutating func tag(_ field: Int, _ wireType: UInt8) {
        bytes += Self.varint(UInt64(field) << 3 | UInt64(wireType))
    }

    mutating func uint(_ field: Int, _ value: UInt64) {
        tag(field, 0)
        bytes += Self.varint(value)
    }

    mutating func int(_ field: Int, _ value: Int) {
        uint(field, UInt64(bitPattern: Int64(value)))
    }

    mutating func bool(_ field: Int, _ value: Bool) {
        uint(field, value ? 1 : 0)
    }

    mutating func data(_ field: Int, _ value: [UInt8]) {
        tag(field, 2)
        bytes += Self.varint(UInt64(value.count))
        bytes += value
    }

    mutating func string(_ field: Int, _ value: String) {
        data(field, Array(value.utf8))
    }

    mutating func message(_ field: Int, _ build: (inout ProtoWriter) -> Void) {
        var nested = ProtoWriter()
        build(&nested)
        data(field, nested.bytes)
    }

    /// Length-delimited frame, as both Android TV sockets expect.
    var framed: [UInt8] { Self.varint(UInt64(bytes.count)) + bytes }
}

struct ProtoMessage {
    enum Value {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed(UInt64)
    }

    private(set) var fields: [Int: [Value]] = [:]

    init?(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            guard let key = Self.readVarint(bytes, &i) else { return nil }
            let field = Int(key >> 3)
            switch key & 7 {
            case 0:
                guard let v = Self.readVarint(bytes, &i) else { return nil }
                fields[field, default: []].append(.varint(v))
            case 1:
                guard i + 8 <= bytes.count else { return nil }
                let v = bytes[i..<i + 8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                i += 8
                fields[field, default: []].append(.fixed(v))
            case 2:
                guard let len = Self.readVarint(bytes, &i), i + Int(len) <= bytes.count else { return nil }
                fields[field, default: []].append(.bytes(Array(bytes[i..<i + Int(len)])))
                i += Int(len)
            case 5:
                guard i + 4 <= bytes.count else { return nil }
                let v = bytes[i..<i + 4].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                i += 4
                fields[field, default: []].append(.fixed(v))
            default:
                return nil
            }
        }
    }

    static func readVarint(_ bytes: [UInt8], _ i: inout Int) -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while i < bytes.count {
            let b = bytes[i]
            i += 1
            result |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return result }
            shift += 7
            if shift > 63 { return nil }
        }
        return nil
    }

    func has(_ field: Int) -> Bool { fields[field] != nil }

    func uint(_ field: Int) -> UInt64? {
        if case .varint(let v)? = fields[field]?.last { return v }
        return nil
    }

    func int(_ field: Int) -> Int? { uint(field).map { Int(Int64(bitPattern: $0)) } }

    func bool(_ field: Int) -> Bool { (uint(field) ?? 0) != 0 }

    func data(_ field: Int) -> [UInt8]? {
        if case .bytes(let b)? = fields[field]?.last { return b }
        return nil
    }

    func string(_ field: Int) -> String? { data(field).map { String(decoding: $0, as: UTF8.self) } }

    /// Present-but-empty submessages (like ConfigurationAck) decode to an empty message.
    func message(_ field: Int) -> ProtoMessage? { data(field).flatMap(ProtoMessage.init) }
}

/// Splits a byte stream into varint-length-prefixed frames.
struct ProtoFramer {
    private var buffer: [UInt8] = []

    mutating func append(_ data: Data) { buffer += data }

    mutating func next() -> [UInt8]? {
        var i = 0
        guard let len = ProtoMessage.readVarint(buffer, &i), buffer.count - i >= Int(len) else { return nil }
        let frame = Array(buffer[i..<i + Int(len)])
        buffer.removeFirst(i + Int(len))
        return frame
    }
}
