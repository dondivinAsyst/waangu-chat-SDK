//
//  IdentityAPIResponse.swift
//  FeatureChat
//
//  The envelope every /identity route answers with.
//

import Foundation

/// `{ "statusCode": 200, "message": "…", "data": { … }, "metadata": null }`
///
/// `data` is optional because the mutation routes answer with the envelope and
/// nothing inside it. `statusCode` and `status` are both accepted: the groups
/// routes send the second spelling.
public struct IdentityAPIResponse<Payload: Decodable>: Decodable {

    public let statusCode: Int?
    public let status: Int?
    public let message: String?
    public let data: Payload?
    public let metadata: PaginationMetadataDTO?

    /// The error code Identity names in `message`, e.g. `ALREADY_MEMBER`.
    ///
    /// Only meaningful on a failure envelope; the mappers read it to tell a
    /// business refusal apart from a transport failure.
    public var code: String? {
        guard let message, !message.isEmpty else { return nil }
        return message
    }
}

/// Paging block on list routes.
///
/// Every field is optional: Identity spells the page size `size` on some routes
/// and `limit` on others, and a response that omits paging entirely must not
/// fail to decode.
public struct PaginationMetadataDTO: Decodable {
    public let page: Int?
    public let size: Int?
    public let limit: Int?
    public let totalPages: Int?
    public let totalElements: Int?

    /// Rows per page, whichever way this response spelled it.
    public var pageSize: Int? { size ?? limit }
}
