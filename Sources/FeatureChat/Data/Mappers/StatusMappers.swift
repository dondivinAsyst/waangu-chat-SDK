import Foundation

protocol StatusMappersProtocol {
    func toDomain(from response: StatusItemDTO) -> StatusItem
    func toDomain(from request: ViewStory) -> ViewStoryDTO
}

class StatusMappers: StatusMappersProtocol {

    func toDomain(from request: ViewStory) -> ViewStoryDTO {
        ViewStoryDTO(
            myId: request.myId,
            username: request.username,
            image: request.image,
            userId: request.userId,
            storyId: request.storyId,
            liked: request.liked,
            time: request.time
        )
    }

    func toDomain(from response: StatusItemDTO) -> StatusItem {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let resolvedId = response.storyId ?? response.id ?? ""
        let resolvedUserId = response.creatorId ?? response.userId ?? ""
        let resolvedCodeStatus = response.codeStatus ?? resolvedId
        let resolvedType = StoryType.fromAPI(response.storyType ?? response.type ?? StoryType.text.rawValue)
        let parsedFont = Self.parseFont(response.font ?? response.fontText)

        return StatusItem(
            id: resolvedId,
            userId: resolvedUserId,
            codeStatus: resolvedCodeStatus,
            userImage: response.userImage,
            userName: response.userName,
            type: resolvedType,
            content: response.content,
            caption: response.caption,
            thumbnail: response.thumbnail,
            background: response.background,
            fontText: parsedFont.text,
            fontSize: nil,
            fontWeight: parsedFont.weight ?? response.fontWeight,
            lastStatusTime: response.lastStatusTime.flatMap { dateFormatter.date(from: $0) },
            seenUsers: response.seenUsers?.map {
                SeenUser(
                    userId: $0.userId,
                    username: $0.username,
                    image: $0.image,
                    viewedAt: dateFormatter.date(from: $0.viewedAt) ?? Date(),
                    liked: $0.liked ?? false,
                    reaction: $0.reaction
                )
            } ?? [],
            unseenUsers: response.unseenUsers ?? [],
            viewCount: response.viewCount ?? 0,
            likeCount: response.likeCount ?? 0,
            shareCount: response.shareCount ?? 0,
            isActive: response.isActive ?? false,
            isPinned: response.isPinned ?? false,
            uploaded: true,
            uploadedUrl: response.content,
            isPublished: response.isPublished ?? true,
            createdAt: dateFormatter.date(from: response.createdAt ?? "") ?? Date(),
            expiresAt: response.expiresAt.flatMap { dateFormatter.date(from: $0) },
            duration: 5.0,
            viewed: false,
            syncStatus: .synced,
            syncError: nil,
            retryCount: 0,
            lastSyncAttempt: nil,
            filename: nil,
            mimeType: nil,
            fileSize: 0
        )
    }

    private static func parseFont(_ value: String?) -> (text: String?, weight: String?) {
        guard let value, !value.isEmpty else { return (nil, nil) }
        let parts = value.split(separator: "|", maxSplits: 1).map(String.init)
        if parts.count == 2 {
            return (parts[0], parts[1])
        }
        return (value, nil)
    }
}
