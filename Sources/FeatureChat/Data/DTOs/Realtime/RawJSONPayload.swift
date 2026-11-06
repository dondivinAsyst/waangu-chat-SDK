//
//  RawJSONPayload.swift
//  FeatureChat
//
//  The SFU client hands us `dtlsParameters`, `rtpParameters` and
//  `rtpCapabilities` as JSON *strings*, while the signaling contract expects
//  them nested as JSON *objects*. This bridges the two without modelling
//  structures the server owns and may extend at any time.
//

import Foundation

/// Retroactive conformance: the enum's payloads are all value types, so it is
/// already safe to send — it simply predates the concurrency annotations.
extension JSONValue: @unchecked Sendable {}

/// Encodes a JSON string as the value it represents.
public struct RawJSONPayload: Encodable, Sendable {

    private let value: JSONValue

    /// Fails when `jsonString` is not valid JSON, so a malformed payload is
    /// caught here rather than rejected by the server as a bare string.
    public init?(jsonString: String) {
        guard
            let data = jsonString.data(using: .utf8),
            let value = try? JSONDecoder().decode(JSONValue.self, from: data)
        else { return nil }
        self.value = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
