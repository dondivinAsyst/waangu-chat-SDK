//
//  ChannelCommunityDebugMockStore.swift
//  FeatureChat
//
//  In-memory stand-ins for the channel/community routes Identity does not have.
//

import Foundation

#if DEBUG

/// Holds what the missing endpoints would have stored.
///
/// Everything lives for the life of the process: these are stand-ins that let
/// the screens be finished and demoed, not a local database. A relaunch starts
/// from the seeds below, which is the honest behaviour for a mock — nobody
/// should mistake it for persistence.
enum ChannelCommunityDebugMockStore {

    private static let lock = NSLock()

    // MARK: - Channel description

    private static var channelDescriptions: [String: String] = [:]

    static func description(channelId: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return channelDescriptions[channelId]
    }

    static func setDescription(_ description: String?, channelId: String) {
        lock.lock(); defer { lock.unlock() }
        channelDescriptions[channelId] = description
    }

    // MARK: - Channel admins

    private static var channelAdmins: [String: [ChannelAdminDto]] = [:]

    static func admins(channelId: String) -> [ChannelAdminDto] {
        lock.lock(); defer { lock.unlock() }
        return channelAdmins[channelId] ?? []
    }

    static func addAdmin(_ admin: ChannelAdminDto, channelId: String) {
        lock.lock(); defer { lock.unlock() }
        var current = channelAdmins[channelId] ?? []
        guard !current.contains(where: { $0.userId == admin.userId }) else { return }
        current.append(admin)
        channelAdmins[channelId] = current
    }

    static func removeAdmin(userId: String, channelId: String) {
        lock.lock(); defer { lock.unlock() }
        channelAdmins[channelId]?.removeAll { $0.userId == userId }
    }

    // MARK: - Community permissions

    private static var communitySettings: [String: CommunitySettingsDto] = [:]

    static func settings(communityId: String) -> CommunitySettingsDto {
        lock.lock(); defer { lock.unlock() }

        if let stored = communitySettings[communityId] {
            return stored
        }

        // WhatsApp's defaults, and the safer pair: admins add people, anyone
        // proposes a group.
        let seeded = CommunitySettingsDto(
            communityId: communityId,
            whoCanAddMembers: "ADMINS",
            whoCanAddGroups: "EVERYONE"
        )
        communitySettings[communityId] = seeded
        return seeded
    }

    static func updateSettings(_ settings: CommunitySettingsDto) {
        lock.lock(); defer { lock.unlock() }
        communitySettings[settings.communityId] = settings
    }

    // MARK: - Sub-group membership

    private static var joinedGroups: Set<String> = []

    static func joinGroup(communityId: String, groupId: String) {
        lock.lock(); defer { lock.unlock() }
        joinedGroups.insert("\(communityId)|\(groupId)")
    }

    static func hasJoined(communityId: String, groupId: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return joinedGroups.contains("\(communityId)|\(groupId)")
    }
}

#endif
