//
//  HTTPCallSyncDataSource.swift
//  FeatureChat
//
//  HTTP implementation of call history synchronization data source
//

import Foundation
import WaanguCoreKit

public final class HTTPCallSyncDataSource: RemoteCallSyncDataSourceProtocol {

    // MARK: - Properties

    private let apiClient: any APIClientProtocol

    // MARK: - Initialization

    public init(apiClient: any APIClientProtocol) {
        self.apiClient = apiClient
    }

    // MARK: - RemoteCallSyncDataSourceProtocol

    public func syncCalls(since: Date?, limit: Int) async throws -> CallSyncResponseDTO {
        return try await apiClient.request(
            endpoint: CallSyncEndpoints.syncCalls(since: since, limit: limit)
        )
    }
}
