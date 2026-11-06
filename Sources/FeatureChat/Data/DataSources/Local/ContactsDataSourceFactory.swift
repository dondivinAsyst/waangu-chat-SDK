//
//  ContactsDataSourceFactory.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

final class ContactsDataSourceFactory {
    static func makeDataSource(
        store: any DatabaseRepositoryProtocol,
        fieldEncryptionService: any FieldEncryptionServiceProtocol
    ) -> LocalContactsDataSourceProtocol {
        GRDBContactsDataSource(
            store: store,
            mapper: ContactsMappers(fieldEncryptionService: fieldEncryptionService)
        )
    }
}
