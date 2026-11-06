import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: GroupRosterParticipantDTO
// ─────────────────────────────────────────────────────────────
// One member as a group event lists them.
//
// The roster rides inside the event's `content`, so it is decoded as part of
// `MessageContentDTO` rather than separately — that way it reaches the app by the
// same route on every inbound path, including the ones with no parser in between.
//
// Only `GROUP_CREATED`, `USER_ADDED_TO_GROUP`, `USER_LEFT_GROUP` and
// `USER_REMOVED_FROM_GROUP` carry it; the role and metadata events do not.

public struct GroupRosterParticipantDTO: Codable, Sendable {
    public let userId:   String
    public let username: String?
    public let name:     String?
    public let phone:    String?
    public let role:     String?

    public var displayName: String {
        [username, name].compactMap { $0 }.first { !$0.isEmpty } ?? ""
    }

    /// The wire has sent both `"MEMBER"` and `"member"` at different times, so the
    /// comparison is deliberately case-insensitive rather than a raw-value decode.
    public var participantRole: ParticipantRoleModel {
        switch role?.lowercased() {
        case "owner":  return .owner
        case "admin":  return .admin
        default:       return .member
        }
    }
}
