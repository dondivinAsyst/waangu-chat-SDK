// FeatureChat/Data/DTOs/StatusEventDTO.swift
import Foundation

// Legacy DTOs — prefer `StoryEventDTO.swift` for MQTT story realtime.

public struct OutboundStatusEventDTO: Codable, Sendable {
    public let statusId: String
    public let event: String

    public init(statusId: String, event: String) {
        self.statusId = statusId
        self.event = event
    }
}

public struct InboundStatusEventDTO: Codable, Sendable {
    public let statusId: String
    public let event: String
    public let timestamp: Double
    public let userId: String
    public let userName: String
    public let avatarURL: String?
    public let segmentIndex: Int?
    public let totalSegments: Int?
    public let mediaType: String?
    public let text: String?
    public let thumbnailURL: String?
    public let expiresAt: Double?
}
