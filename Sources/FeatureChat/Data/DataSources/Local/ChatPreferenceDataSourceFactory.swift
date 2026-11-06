//
//  ChatPreferenceDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

enum ChatPreferenceDataSourceFactory {

    static func create(
        store: any DatabaseRepositoryProtocol
    ) -> LocalChatPreferenceDataSourceProtocol {
        GRDBChatPreferenceDataSource(store: store)
    }
}
