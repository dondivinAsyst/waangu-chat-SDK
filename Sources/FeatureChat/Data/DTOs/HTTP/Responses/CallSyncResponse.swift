//
//  CallSyncResponse.swift
//  FeatureChat
//
//  Call history synchronization response DTOs
//  Endpoint: GET /api/v1/me/calls/sync
//
//  Only the fields `CallLogModel` has somewhere to put are declared. The payload
//  also carries `callRoomId`, `deviceId`, `tenantId`, `country`, an `events[]`
//  timeline and per-participant `invitedAt`/`joinedAt`/`leftAt` — none of which
//  have a column, so they are left undeclared and dropped at decode.
//
//  `sortKey` is the exception: never stored, but it carries the pagination
//  watermark for when the server's cursor cannot be read as a date.
//

import Foundation

// MARK: - Main Response

public struct CallSyncResponseDTO: Codable {
    let success: Bool?
    let data: CallSyncDataDTO?
    let nextCursor: String?
    let prevCursor: String?
    let hasMore: Bool?
    let count: Int?
    let message: String?
    let timestamp: String?
}

// MARK: - Data Container

public struct CallSyncDataDTO: Codable {
    let serverTime: String?
    let nextSinceCursor: String?
    let changedCalls: [ChangedCallDTO]?
}

// MARK: - Changed Call

public struct ChangedCallDTO: Codable {
    let callId: String
    let conversationId: String?
    /// Epoch milliseconds.
    let sortKey: Double?
    let initiator: CallSyncParticipantDTO?
    let participants: [CallSyncParticipantDTO]?
    let callType: String?          // "VOICE" | "VIDEO"
    let initiatedAt: String?
    let endedAt: String?
    let durationSec: Int?
    let status: String?            // "ENDED", "MISSED", …

    var initiatedAtDate: Date? { LenientISO8601.date(from: initiatedAt) }
    var endedAtDate: Date? { LenientISO8601.date(from: endedAt) }

    /// The instant the next page must start after.
    var watermark: Date? {
        if let sortKey, sortKey > 0 {
            return Date(timeIntervalSince1970: sortKey / 1000)
        }
        return endedAtDate ?? initiatedAtDate
    }
}

// MARK: - Participant

public struct CallSyncParticipantDTO: Codable {
    let userId: String?
    let displayName: String?
    let phone: String?
    let status: String?            // "LEFT", "MISSED", "JOINED", …
}

// MARK: - Server vocabulary → domain vocabulary

enum CallSyncVocabulary {

    static func media(_ raw: String?) -> CallMedia {
        raw?.uppercased() == "VIDEO" ? .video : .voice
    }

    /// What the call amounted to *for the participant in question*.
    ///
    /// The call-level status describes how the call ended (`ENDED`), not what
    /// the user lived through: in one ended call, one party hung up (`LEFT`)
    /// while the other never picked up (`MISSED`). So the participant's own
    /// status wins, and the call's is only the fallback for when we are not
    /// listed among them.
    static func outcome(
        participantStatus: String?,
        callStatus: String?,
        durationSeconds: Int
    ) -> CallOutcome {
        if let mapped = outcome(participantStatus) { return mapped }
        if let mapped = outcome(callStatus) { return mapped }
        // `ENDED` says nothing on its own — the duration does.
        return durationSeconds > 0 ? .answered : .missed
    }

    static func outcome(_ raw: String?) -> CallOutcome? {
        switch raw?.uppercased() {
        case "ANSWERED", "JOINED", "LEFT", "CONNECTED", "IN_CALL":
            return .answered
        case "MISSED":
            return .missed
        case "DECLINED", "REJECTED":
            return .declined
        case "CANCELLED", "CANCELED":
            return .cancelled
        case "NO_ANSWER", "NOANSWER", "TIMEOUT":
            return .noAnswer
        case "BUSY":
            return .busy
        case "FAILED", "ERROR":
            return .failed
        default:
            return nil
        }
    }
}
