import Foundation

/// Single entry-point for the 4-step transaction pipeline.
///
/// Features call `perform` (raw — full response) or the convenience
/// `execute` (standard `APIResponseDTO` envelope) provided by DomainKit.
///
/// ```swift
/// // Standard envelope (via DomainKit extension)
/// await gateway.execute(step: .request, request: dto) { (data: MyDataDTO) in
///     MyMapper.map(data)
/// }
///
/// // Custom response shape
/// await gateway.perform(step: .request, request: dto, policy: .standard) { (resp: CustomDTO) in
///     CustomMapper.map(resp)
/// }
/// ```
public protocol TransactionGatewayProtocol: AnyObject, Sendable {

    /// Execute a transaction step and transform the raw decoded response.
    ///
    /// Use this when the backend response doesn't follow the standard
    /// `APIResponseDTO<T>` envelope (e.g. extra top-level fields like `display`).
    func perform<RequestDTO: Encodable & Sendable,
                 ResponseDTO: Decodable & Sendable,
                 Entity>(
        step: TransactionStep,
        request: RequestDTO,
        policy: TransactionStepPolicy,
        transform: @Sendable (ResponseDTO) throws -> Entity
    ) async -> Result<Entity, AppError>
}
