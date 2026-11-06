//
//  CommunitiesViewModel.swift
//  FeatureChat
//

import Foundation
import UIKit
import WaanguCoreKit

/// The communities tab: what this user belongs to, and the two ways in —
/// creating one, or joining with an invite code.
@available(iOS 16.0, *)
@MainActor
public final class CommunitiesViewModel: ObservableObject {

    @Published private(set) var communities: [Community] = []
    /// Conversation activity for every group on screen, keyed by conversation
    /// id. Identity knows the groups; only the inbox knows what was last said
    /// in them.
    @Published private(set) var previews: [String: ConversationPreview] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var isWorking = false
    /// Set when something failed and the screen should say so. Cleared on retry.
    @Published var errorMessage: String?

    private let useCases: CommunityUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    /// Parks an avatar in media storage and hands back its URL. The same one the
    /// profile screen uses — an avatar is an avatar.
    private let uploadAvatar: UploadProfilePhotoUseCaseProtocol
    let translationService: (any TranslationServiceProtocol)?

    init(
        useCases: CommunityUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        uploadAvatar: UploadProfilePhotoUseCaseProtocol,
        translationService: (any TranslationServiceProtocol)?
    ) {
        self.useCases = useCases
        self.discussionUseCases = discussionUseCases
        self.uploadAvatar = uploadAvatar
        self.translationService = translationService
    }

    /// What was last said in a group, when the inbox has that conversation.
    func preview(for group: CommunityGroupSummary) -> ConversationPreview? {
        guard let conversationId = group.conversationId else { return nil }
        return previews[conversationId]
    }

    var isEmpty: Bool {
        communities.isEmpty && !isLoading
    }

    // MARK: - Loading

    /// Shows the last read straight away, then refreshes.
    ///
    /// The refresh is what makes a community joined on another device appear;
    /// the cached read is what keeps the tab from flashing empty on every visit.
    func onAppear() {
        Task { await load(refresh: communities.isEmpty) }
    }

    func refresh() async {
        await load(refresh: true)
    }

    private func load(refresh: Bool) async {
        isLoading = communities.isEmpty
        defer { isLoading = false }

        do {
            communities = try await useCases.listMine.execute(refresh: refresh)
            previews = ConversationPreview.index(
                (try? await discussionUseCases.getDiscussions.execute()) ?? []
            )
            errorMessage = nil
        } catch {
            // A failed refresh must not wipe a list that is already on screen.
            if communities.isEmpty {
                errorMessage = message(for: error)
            }
        }
    }

    // MARK: - Actions

    /// - Returns: the new community, or nil when creation failed.
    ///
    /// The avatar is uploaded first, because the community carries its URL. A
    /// failed upload stops the whole thing: creating the community anyway would
    /// silently drop the picture the user chose.
    func create(_ draft: NewCommunityDraft, avatar: UIImage?) async -> Community? {
        isWorking = true
        defer { isWorking = false }

        var draft = draft
        if let avatar {
            switch await uploadAvatar.execute(imageData: ChatImageSendEncoder.encodeAvatar(avatar)) {
            case .failure(let error):
                errorMessage = error.localizedDescription
                return nil
            case .success(let url):
                draft.image = url
            }
        }

        do {
            let community = try await useCases.createCommunity.execute(draft)
            await load(refresh: true)
            errorMessage = nil
            return community
        } catch {
            errorMessage = message(for: error)
            return nil
        }
    }

    /// - Returns: `true` when the user is now a member — including when they
    ///   already were, which Identity reports as a refusal but is not one.
    func join(inviteCode: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await useCases.joinCommunity.execute(inviteCode: inviteCode)
            await load(refresh: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func join(communityId: String) async -> Bool {
        isWorking = true
        defer { isWorking = false }

        do {
            _ = try await useCases.joinCommunity.execute(communityId: communityId)
            await load(refresh: true)
            errorMessage = nil
            return true
        } catch {
            errorMessage = message(for: error)
            return false
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func message(for error: Error) -> String {
        (error as? CommunityError)?.errorDescription ?? error.localizedDescription
    }
}
