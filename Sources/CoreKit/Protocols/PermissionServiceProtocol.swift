import Foundation

// MARK: - PermissionType

/// Toutes les permissions systeme gerees par l'application.
///
/// Defini dans CoreKit (types purs, zero framework) pour que les features
/// puissent verifier/demander des permissions sans dependre de PermissionKit.
public enum PermissionType: String, Sendable, CaseIterable {
    case locationWhenInUse
    case locationAlways
    case camera
    case microphone
    case notifications
    case contacts
    case photoLibrary
}

// MARK: - PermissionStatus

/// Statut unifie d'une permission systeme.
///
/// Mappe les statuts heterogenes de chaque framework (CLAuthorizationStatus,
/// AVAuthorizationStatus, UNAuthorizationStatus...) vers un vocabulaire commun.
public enum PermissionStatus: String, Sendable {
    case notDetermined
    case restricted
    case denied
    case authorized
    case limited
    case provisional

    /// `true` si l'application peut utiliser la fonctionnalite (meme partiellement).
    public var isGranted: Bool {
        switch self {
        case .authorized, .limited, .provisional: return true
        case .notDetermined, .restricted, .denied: return false
        }
    }
}

// MARK: - PermissionServiceProtocol

/// Contrat central de gestion des permissions.
///
/// L'implementation concrete (PermissionCenter) vit dans PermissionKit.
/// Les features importent uniquement CoreKit pour ce protocole.
///
/// Pattern identique a :
///   - `APIClientProtocol` (CoreKit) → `APIClient` (NetworkKit)
///   - `NetworkMonitoringProtocol` (CoreKit) → `NetworkMonitor` (NetworkKit)
@MainActor
public protocol PermissionServiceProtocol: AnyObject, Sendable {

    /// Verifie le statut actuel sans declencher de dialogue.
    func status(for type: PermissionType) async -> PermissionStatus

    /// Declenche la demande systeme et retourne le nouveau statut.
    /// Si deja demandee, retourne le statut actuel sans dialogue.
    func request(_ type: PermissionType) async -> PermissionStatus

    /// Flux de statut : premier yield = etat initial, puis mises a jour temps reel.
    func statusStream(for type: PermissionType) -> AsyncStream<PermissionStatus>
}
