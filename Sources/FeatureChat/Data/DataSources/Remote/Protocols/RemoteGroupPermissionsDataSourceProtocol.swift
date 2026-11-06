//
//  RemoteGroupPermissionsDataSourceProtocol.swift
//  FeatureChat
//

import Foundation

protocol RemoteGroupPermissionsDataSourceProtocol {
    func updatePermissions(_ request: UpdateGroupPermissionsRequest) async throws
}
