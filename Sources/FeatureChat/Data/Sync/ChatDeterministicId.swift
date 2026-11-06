import Foundation

/// Derives a stable UUID string from arbitrary input.
///
/// Used wherever a record needs an id the server never sent but every device has
/// to agree on — a participant row keyed by conversation and user, or a system
/// message the backend projects into a thread without a message id. Deriving it
/// rather than generating one is what makes a replayed event update the existing
/// row instead of inserting a duplicate.
///
/// FNV-1a rather than `Hasher`: `Hasher` is seeded per process, so the same input
/// would produce a different id on the next launch.
enum ChatDeterministicId {

    static func uuid(from string: String) -> String {
        let hash = string.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { acc, byte in
            (acc ^ UInt64(byte)) &* 16_777_619
        }
        var bytes = [UInt8](repeating: 0, count: 16)
        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (i * 8)) & 0xFF)
            bytes[i + 8] = UInt8((hash >> (i * 8)) & 0xFF)
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        )).uuidString.lowercased()
    }
}
