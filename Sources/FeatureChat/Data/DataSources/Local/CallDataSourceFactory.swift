import Foundation
import WaanguCoreKit

final class CallDataSourceFactory {
    static func makeDataSource(
        store: any DatabaseRepositoryProtocol
    ) -> LocalCallDataSourceProtocol {
        GRDBCallDataSource(store: store)
    }
}
