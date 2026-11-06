import Foundation

/// The 4 generic steps of the Waangu transaction pipeline.
///
/// Every transactional feature (SendMoney, MoveMoney, MobileTopup, etc.)
/// shares the same backend endpoints — only the request/response DTOs differ.
public enum TransactionStep: String, Sendable, CaseIterable {
    case check
    case request
    case confirm
    case verify

    public var path: String {
        switch self {
        case .check:   "/api/transaction/checkTransaction"
        case .request: "/api/transaction/requestTransaction"
        case .confirm: "/api/transaction/confirmTransaction"
        case .verify:  "/api/transaction/verifyTransaction"
        }
    }
}
