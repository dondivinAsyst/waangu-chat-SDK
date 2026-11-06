import Foundation

/// Contrat de geolocalisation pour les features.
///
/// L'implementation concrete (LocationManager) vit dans LocationKit.
/// Les features importent uniquement CoreKit pour ce protocole
/// et consomment `LocationSnapshot` (pas `LocationData`).
///
/// Pattern identique a :
///   - `APIClientProtocol` (CoreKit) → `APIClient` (NetworkKit)
///   - `TokenManagerProtocol` (CoreKit) → `TokenManager` (AuthKit)
public protocol LocationServiceProtocol: Sendable {

    /// Requete one-shot avec timeout.
    func requestCurrentLocation(timeout: TimeInterval) async throws -> LocationSnapshot

    /// Flux continu de positions (throttle integre cote LocationKit).
    /// Le stream se ferme automatiquement quand le consommateur arrete d'iterer.
    func snapshotStream() -> AsyncThrowingStream<LocationSnapshot, Error>
}
