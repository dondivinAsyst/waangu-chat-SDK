// FeatureChat/Data/DTOs/Realtime/UserPresenceDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: PresencePayload
// ─────────────────────────────────────────────────────────────
// Topic : waangu-chat/presence (publish + subscribe)
//
// Outbound : lifecycle (foreground → ONLINE, background/logout → OFFLINE)
// Inbound  : contact presence updates broadcast by the server

public enum PresenceStatus: String, Codable, Sendable {
    case online = "ONLINE"
    case offline = "OFFLINE"
    case busy = "BUSY"
}

public struct PresencePayloadDTO: Codable, Sendable, Equatable {
    public let userId: String
    public let status: PresenceStatus
    public let lastSeen: String?
    public let country: String?
    public let tenantId: String?
    public let currentRideId: String?

    public init(
        userId: String,
        status: PresenceStatus,
        lastSeen: String? = nil,
        country: String? = nil,
        tenantId: String? = nil,
        currentRideId: String? = nil
    ) {
        self.userId = userId
        self.status = status
        self.lastSeen = lastSeen
        self.country = country
        self.tenantId = tenantId
        self.currentRideId = currentRideId
    }
}
