//
//  RemoteCallSyncDataSourceProtocol.swift
//  FeatureChat
//
//  Protocol for remote call history synchronization data source
//

import Foundation

public protocol RemoteCallSyncDataSourceProtocol {
    /// Fetches calls changed since the given date.
    /// - Parameters:
    ///   - since: Optional date to fetch changes from (nil = all calls)
    ///   - limit: Maximum number of calls per page
    /// - Returns: Call sync response with the changed calls
    func syncCalls(since: Date?, limit: Int) async throws -> CallSyncResponseDTO
}
