//
//  HTTPGroupPermissionsDataSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class HTTPGroupPermissionsDataSource: RemoteGroupPermissionsDataSourceProtocol {

    private let httpClient: APIClientProtocol

    init(httpClient: APIClientProtocol) {
        self.httpClient = httpClient
    }

    func updatePermissions(_ request: UpdateGroupPermissionsRequest) async throws {
        let endpoint = GroupEndpoints.updatePermissions(request)
        let _: EmptyResponse = try await httpClient.request(endpoint: endpoint)
    }
}
