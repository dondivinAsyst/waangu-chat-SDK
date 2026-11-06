//
//  ChatCoreAPIResponse.swift
//  FeatureChat
//
//  The envelope every WAANGU Chat Core route answers with —
//  INTEGRATION_CHAT_FINANCE.md §0.4.
//

import Foundation

/// `{ "success": true, "message": "...", "statusCode": 200, "data": {}, "error": null, "timestamp": "…" }`
///
/// Distinct from `IdentityAPIResponse` (`statusCode`/`message`/`data`) and from
/// NetworkKit's `APIResponseDTO` (`err`/`message`/`data`): Chat Core carries its
/// business refusal in `error.code` (`CF_xxx`), and only that code is
/// authoritative — `statusCode` in the body is not always filled.
struct ChatCoreAPIResponse<Payload: Decodable>: Decodable {
    let success: Bool
    let message: String?
    let statusCode: Int?
    let data: Payload?
    let error: ChatCoreErrorBody?
    /// Server ISO-8601, kept as text: the shared decoder expects numeric dates.
    let timestamp: String?
}

/// `error` of the envelope. `details` is ignored: its shape is not contractual.
struct ChatCoreErrorBody: Decodable, Equatable {
    let code: String
    let message: String?
}

/// `data` of the responses that carry nothing useful.
struct FinanceCoreEmpty: Decodable, Equatable, Sendable {}
