//
//  ISO8601Timestamp.swift
//  FeatureChat
//
//  One tolerant reader for the timestamps this backend sends.
//

import Foundation

/// Parses an ISO-8601 timestamp with or without fractional seconds.
///
/// The shared `JSONDecoder` is configured with strict `.iso8601`, which rejects
/// `2026-08-28T10:15:30.123Z`. DTOs that keep their timestamps as `String` read
/// them back through here, so one unparseable date costs that one field instead
/// of the whole response.
enum ISO8601Timestamp {

    static func date(from value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
