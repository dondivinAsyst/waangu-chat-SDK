import Foundation
import WaanguCoreKit
import WaanguNetworkKit

// MARK: - Convenience for standard APIResponseDTO envelope

public extension TransactionGatewayProtocol {

    /// Execute a transaction step assuming the standard `APIResponseDTO<DataDTO>` envelope.
    ///
    /// Automatically checks `BusinessStatusCode.success`, unwraps `data`,
    /// then delegates to `map` for feature-specific transformation.
    ///
    /// ```swift
    /// await gateway.execute(step: .request, request: dto) {
    ///     (data: WalletToWalletRequestTransactionDataDTO) in
    ///     WalletToWalletRequestTransactionResult(
    ///         transRefId: data.transRefId, ...
    ///     )
    /// }
    /// ```
    func execute<RequestDTO: Encodable & Sendable,
                 DataDTO: Codable & Sendable,
                 Entity>(
        step: TransactionStep,
        request: RequestDTO,
        policy: TransactionStepPolicy = .standard,
        map: @Sendable (DataDTO) throws -> Entity
    ) async -> Result<Entity, AppError> {
        await perform(step: step, request: request, policy: policy) {
            (response: APIResponseDTO<DataDTO>) throws -> Entity in

            guard response.err == BusinessStatusCode.success.rawValue else {
                throw AppError.unknown(response.message)
            }
            guard let data = response.data else {
                throw AppError.unknown("No data returned for \(step)")
            }
            return try map(data)
        }
    }
}

// MARK: - Concrete implementation

public final class TransactionGateway: TransactionGatewayProtocol, @unchecked Sendable {

    private let apiClient: any APIClientProtocol
    private let errorMapper: any ErrorMapperProtocol

    public init(
        apiClient: any APIClientProtocol,
        errorMapper: any ErrorMapperProtocol
    ) {
        self.apiClient = apiClient
        self.errorMapper = errorMapper
    }

    public func perform<RequestDTO: Encodable & Sendable,
                        ResponseDTO: Decodable & Sendable,
                        Entity>(
        step: TransactionStep,
        request: RequestDTO,
        policy: TransactionStepPolicy,
        transform: @Sendable (ResponseDTO) throws -> Entity
    ) async -> Result<Entity, AppError> {
        do {
            let endpoint = TransactionEndpoint(
                step: step,
                body: request,
                stepPolicy: policy
            )
            let response: ResponseDTO = try await apiClient.request(endpoint: endpoint)
            let entity = try transform(response)
            return .success(entity)
        } catch let appError as AppError {
            return .failure(appError)
        } catch let apiError as APIError {
            return .failure(errorMapper.map(apiError))
        } catch {
            return .failure(.unknown(error.localizedDescription))
        }
    }
}
