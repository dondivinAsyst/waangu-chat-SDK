//
//  ChatOutboxFlush.swift
//  WaanguChatSDK
//
//  Moved from the Waangu app target into WaanguChatSDK (SDK plan, step 1.9).
//

import Foundation
import WaanguCoreKit
import WaanguFeatureChat
import WaanguStorageKit

/// What the chat outbox does with a batch of queued actions: send them to the chat backend
/// in one request and report, per item, whether the server accepted it.
public enum ChatOutboxFlush {

    /// - Parameter apiClient: builds the chat API client. Called once per batch, so a client
    ///   that is created asynchronously (or replaced after a login) is always the current one.
    ///
    /// A request that fails reports **every** item of the batch as failed with the error text;
    /// the outbox decides what to retry.
    public static func makeHandler(
        apiClient: @escaping @Sendable () async throws -> any APIClientProtocol
    ) -> @Sendable ([ChatOutboxItem]) async throws -> [OutboxFlushResult] {
        { batch in
            do {
                let client = try await apiClient()
                let request = ChatOutboxBatchRequestDTO(items: batch)
                let response: ChatOutboxBatchResponseDTO = try await client.request(
                    endpoint: HTTPChatSyncEndpoints.flushOutbox(request)
                )
                return response.results.map { $0.toFlushResult() }
            } catch {
                return batch.map {
                    OutboxFlushResult(
                        localId: $0.id,
                        success: false,
                        error: error.localizedDescription
                    )
                }
            }
        }
    }
}
