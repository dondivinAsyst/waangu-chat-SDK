//
//  ChatActionsDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

public final class ChatActionsDataSourceFactory {

    public static let shared = ChatActionsDataSourceFactory()

    private init() {}
    
    func makeLocalDataSource(
        store: any DatabaseRepositoryProtocol
    ) -> LocalChatActionsDataSourceProtocol {
        return GRDBChatActionsDataSource(
            store: store,
            mapper: ChatActionMapper()
        )
    }

    public func makeChatActionsUseCase(
        store: any DatabaseRepositoryProtocol
    ) -> ChatActionsUseCaseProtocol {
        let dataSource = makeLocalDataSource(store: store)
        return ChatActionsUseCase(localDataSource: dataSource)
    }
}
