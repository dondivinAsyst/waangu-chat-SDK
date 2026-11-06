import Testing
@testable import WaanguCoreKit

@Suite("CoreKit")
struct CoreKitTests {

    @Test("AppError retryable cases are correct")
    func appErrorRetryable() {
        #expect(AppError.timeout.isRetryable)
        #expect(AppError.serverError.isRetryable)
        #expect(AppError.noInternetConnection.isRetryable)
        #expect(!AppError.notFound.isRetryable)
        #expect(!AppError.sessionExpired.isRetryable)
    }

    @Test("AppError auth cases are correct")
    func appErrorAuth() {
        #expect(AppError.sessionExpired.isAuthError)
        #expect(AppError.tokenRefreshFailed.isAuthError)
        #expect(!AppError.timeout.isAuthError)
    }
}
