import Foundation
import WaanguCoreKit

/// Narrow outbox contract for FeatureChat — avoids StorageKit dependency in the module.
public protocol ChatOutboxEnqueuing: Sendable {
    func enqueue(_ item: ChatOutboxItem) async throws
}
