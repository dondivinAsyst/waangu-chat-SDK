import Foundation
import WaanguCoreKit

final class GroupDataSourceFactory {
    static func makeDataSource(
    store: any DatabaseRepositoryProtocol,
    fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> LocalGroupDataSourceProtocol {
        GRDBGroupDataSource(store: store, fieldCrypto: fieldCrypto)
    }
}
