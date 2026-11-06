//
//  GroupPendingJoinRequestsViewModel.swift
//  FeatureChat
//

import Foundation

@MainActor
final class GroupPendingJoinRequestsViewModel: ObservableObject {
    @Published private(set) var requests: [GroupJoinRequest] = []
    @Published var isLoading = false
    @Published var actionInProgressId: String?
    @Published var errorMessage: String?

    let discussionId: String
    let groupName: String

    private let groupUseCases: GroupUseCasesProtocol

    init(
        discussionId: String,
        groupName: String,
        groupUseCases: GroupUseCasesProtocol
    ) {
        self.discussionId = discussionId
        self.groupName = groupName
        self.groupUseCases = groupUseCases
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            requests = try await groupUseCases.fetchPendingJoinRequests.execute(groupId: discussionId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approve(_ request: GroupJoinRequest) async {
        actionInProgressId = request.id
        errorMessage = nil
        defer { actionInProgressId = nil }

        do {
            try await groupUseCases.approveJoinRequest.execute(
                requestId: request.id,
                groupId: discussionId,
                ownerId: CurrentSessionInfo.shared.currentUid
            )
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func decline(_ request: GroupJoinRequest) async {
        actionInProgressId = request.id
        errorMessage = nil
        defer { actionInProgressId = nil }

        do {
            try await groupUseCases.declineJoinRequest.execute(
                requestId: request.id,
                groupId: discussionId,
                ownerId: CurrentSessionInfo.shared.currentUid
            )
            requests.removeAll { $0.id == request.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
