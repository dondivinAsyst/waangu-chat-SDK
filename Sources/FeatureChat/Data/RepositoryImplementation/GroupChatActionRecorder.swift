import Foundation

enum GroupChatActionRecorder {
    static func record(
        chatActionsUseCase: ChatActionsUseCaseProtocol?,
        conversationId: String,
        actionType: ChatActionType,
        performedBy: String,
        targetId: String? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        guard let chatActionsUseCase else { return }
        
        let action = ChatActionItem(
            conversationId: conversationId,
            actionType: actionType,
            performedBy: performedBy,
            targetId: targetId,
            metadata: metadata,
            timestamp: timestamp
        )
        
        Task {
            do {
                try await chatActionsUseCase.recordAction(action)
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .chatActionsDidChange,
                        object: nil,
                        userInfo: ["conversationId": conversationId]
                    )
                }
            } catch {
                #if DEBUG
                print("Failed to record group chat action \(actionType): \(error)")
                #endif
            }
        }
    }
    
    static func performerMetadata(
        performedBy: String,
        performedByName: String? = nil
    ) -> [String: String] {
        var metadata: [String: String] = [:]
        let name = performedByName ?? CurrentSessionInfo.shared.userName
        if !name.isEmpty {
            metadata["performedByName"] = name
        }
        return metadata
    }
}
