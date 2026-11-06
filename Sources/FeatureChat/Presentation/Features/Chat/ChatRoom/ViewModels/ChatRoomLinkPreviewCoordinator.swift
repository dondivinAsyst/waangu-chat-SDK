//
//  ChatRoomLinkPreviewCoordinator.swift
//  FeatureChat
//

import Foundation

/// Link detection and preview fetching while composing a message.
enum ChatRoomLinkPreviewCoordinator {

    static func shouldFetchPreview(for text: String, currentURL: URL?) -> URL? {
        guard !text.isEmpty,
              let url = LinkPreviewProvider.extractFirstURL(from: text) else {
            return nil
        }
        guard url != currentURL else { return nil }
        return url
    }

    static func fetchPreviewTask(
        for url: URL,
        onResult: @escaping @MainActor (LinkPreviewData?) -> Void
    ) -> Task<Void, Never> {
        Task {
            let preview = await LinkPreviewProvider.shared.fetchPreview(for: url)
            guard !Task.isCancelled else { return }
            await onResult(preview)
        }
    }
}
