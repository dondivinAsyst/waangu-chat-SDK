//
//  StoriesSyncResponse.swift
//  FeatureChat
//
//  Stories synchronization response DTOs
//  Endpoint: GET /api/v1/me/stories/sync
//

import Foundation

// MARK: - Main Response

public struct StoriesSyncResponseDTO: Codable {
    let success: Bool
    let data: StoriesSyncDataDTO?
    let timestamp: String?
}

// MARK: - Data Container

public struct StoriesSyncDataDTO: Codable {
    let serverTime: String?
    let nextSinceCursor: String?
    let changedStories: [ChangedStoryGroupDTO]
    let hasMore: Bool? // Pagination flag
}

// MARK: - Changed Story Group (per creator)

public struct ChangedStoryGroupDTO: Codable {
    let creatorId: String
    let creatorDisplayName: String?
    let creatorAvatar: String?
    let creatorPhone: String?
    let muted: Bool?
    let favorite: Bool?
    let own: Bool?
    let hasUnseen: Bool?
    let lastStoryAt: String?
    let stories: [StoryDTO]
}

// MARK: - Individual Story

public struct StoryDTO: Codable {
    let storyId: String
    let creatorId: String
    let creatorDisplayName: String?
    let creatorAvatar: String?
    let creatorPhone: String?
    let muted: Bool?
    let favorite: Bool?
    let own: Bool?
    let viewed: Bool?
    let content: String?
    let storyType: String?
    let caption: String?
    let thumbnail: String?
    let font: String?
    let background: String?
    let expiresAt: String?
    let createdAt: String?
    let tenantId: String?
    let country: String?
    let deleted: Bool?
    let deletedAt: String?
    let expired: Bool?
    let expiredAt: String?
    let views: [StoryViewDTO]?
    let reactions: [StoryReactionDTO]?
}

// MARK: - Story View

public struct StoryViewDTO: Codable {
    let viewerId: String?
    let viewedAt: String?
}

// MARK: - Story Reaction

public struct StoryReactionDTO: Codable {
    let userId: String?
    let reaction: String?
    let reactedAt: String?
}
