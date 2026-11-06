//
//  LocalGroupJoinRequestDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

public protocol LocalGroupJoinRequestDataSourceProtocol {
    func fetchPending(groupLocalId: String) async throws -> [GroupJoinRequest]
    func saveAll(_ requests: [GroupJoinRequest], groupLocalId: String) async throws
    func remove(requestId: String, groupLocalId: String) async throws
    func upsert(_ request: GroupJoinRequest, groupLocalId: String) async throws
}
