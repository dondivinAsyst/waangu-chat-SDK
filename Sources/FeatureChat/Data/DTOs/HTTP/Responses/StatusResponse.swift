import Foundation

// MARK: - StatusItemDTO
// HTTP response DTO for a single status item from the server

struct StatusItemDTO: Codable {
    let storyId: String?
    let creatorId: String?
    let storyType: String?
    let font: String?

    // Legacy / alternate keys still used by older payloads
    let id: String?
    let userId: String?
    let codeStatus: String?
    let userImage: String?
    let userName: String?
    let type: String?
    let content: String?
    let caption: String?
    let thumbnail: String?
    let background: String?
    let fontText: String?
    let fontWeight: String?
    let lastStatusTime: String?
    let seenUsers: [SeenUserDTO]?
    let unseenUsers: [String]?
    let viewCount: Int?
    let likeCount: Int?
    let shareCount: Int?
    let isActive: Bool?
    let isPinned: Bool?
    let isPublished: Bool?
    let createdAt: String?
    let expiresAt: String?
}

struct SeenUserDTO: Codable {
    let userId: String
    let username: String
    let image: String?
    let viewedAt: String
    let liked: Bool?
    let reaction: String?
}

// MARK: - ViewStoryDTO
// HTTP request DTO for marking a story as viewed

struct ViewStoryDTO: Codable {
    let myId: String
    let username: String
    let image: String
    let userId: String
    let storyId: String
    let liked: Bool
    let time: Date?
}
