import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: LenientISO8601
// ─────────────────────────────────────────────────────────────
// The sync endpoints send timestamps with however many fractional digits the
// server's clock happens to produce — `.453Z`, `.420822Z`, `.012167400Z` have
// all turned up in the same API. `ISO8601DateFormatter` accepts exactly three,
// and the shared `APIClient` decoder is configured for plain `.iso8601`, which
// accepts none at all: one message with microseconds and the whole response
// throws.
//
// So every date on a sync DTO is decoded as `String` and parsed here instead,
// by trimming the fraction to what the formatter will take. That keeps the
// leniency at the sync boundary rather than loosening decoding for the other
// forty endpoints that are happy as they are.

enum LenientISO8601 {

    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String?) -> Date? {
        guard let raw = string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        if let normalized = normalizingFraction(raw),
           let date = fractional.date(from: normalized) {
            return date
        }
        return plain.date(from: raw) ?? fractional.date(from: raw)
    }

    /// The format the endpoints expect for `since`.
    static func string(from date: Date) -> String {
        fractional.string(from: date)
    }

    /// Rewrites the fractional part to exactly three digits, leaving the rest of
    /// the timestamp — including the zone suffix — untouched.
    ///
    /// Returns `nil` when there is no fraction to fix, so the caller falls
    /// through to the plain parser rather than paying for a pointless rebuild.
    private static func normalizingFraction(_ value: String) -> String? {
        guard let dot = value.firstIndex(of: ".") else { return nil }

        let firstDigit = value.index(after: dot)
        var end = firstDigit
        while end < value.endIndex, value[end].isNumber {
            end = value.index(after: end)
        }
        guard end > firstDigit else { return nil }

        let digits = value[firstDigit..<end]
        let capped = digits.prefix(3)
        let padded = capped.count == 3
            ? String(capped)
            : capped + String(repeating: "0", count: 3 - capped.count)

        return String(value[value.startIndex..<firstDigit]) + padded + String(value[end...])
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: SinceCursor
// ─────────────────────────────────────────────────────────────
// `/me/*/sync` pages by advancing `since`, and hands back `nextSinceCursor` to
// advance it with — but not in one shape. Conversations return a timestamp;
// calls return `MTc4Njk1NDQ5MjAxMnxzeW5jfEFGVEVS`, which is base64 for
// `1786954492012|sync|AFTER`.
//
// Both reduce to an instant, so both are read here. A cursor that resists both
// readings is not fatal: the caller falls back to the newest item in the page,
// which is the same watermark by another route.

enum SinceCursor {

    static func date(from cursor: String?) -> Date? {
        guard let raw = cursor?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        if let date = LenientISO8601.date(from: raw) { return date }
        return epochMillisDate(in: raw) ?? decodedEpochMillisDate(in: raw)
    }

    /// Base64 cursors carry the millisecond watermark in their first field.
    private static func decodedEpochMillisDate(in cursor: String) -> Date? {
        // Tolerate the unpadded base64url some backends emit.
        var normalized = cursor
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: normalized),
              let decoded = String(data: data, encoding: .utf8) else { return nil }

        return epochMillisDate(in: decoded)
    }

    private static func epochMillisDate(in value: String) -> Date? {
        let leading = value.prefix { $0.isNumber }
        // Milliseconds since epoch are 13 digits and will be for the next few
        // centuries. Anything shorter is a page number or an id, not a time.
        guard leading.count >= 12, let millis = Double(leading) else { return nil }
        return Date(timeIntervalSince1970: millis / 1000)
    }
}
