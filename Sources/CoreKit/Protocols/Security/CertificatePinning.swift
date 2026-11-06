//
//  CertificatePinning.swift
//  CoreKit
//
//  Bloc 9, §11 (ch. 72) — épinglage gouverné et rotation d'urgence.
//

import Foundation

/// Politique d'épinglage pour un hôte.
///
/// **Épingle la clé publique (SPKI), jamais le certificat feuille.** Un
/// certificat feuille est renouvelé plusieurs fois par an ; l'épingler
/// transforme chaque renouvellement en panne totale de l'application, ce qui
/// finit toujours par faire désactiver l'épinglage. La clé publique, elle,
/// survit au renouvellement tant que la paire n'est pas régénérée.
public struct CertificatePinPolicy: Sendable, Equatable {

    /// Hôte exact concerné. Pas de joker : un `*.example.com` épinglé couvre
    /// aussi un sous-domaine compromis.
    public let host: String

    /// Empreintes SHA-256 des SPKI acceptées, encodées en base64.
    ///
    /// **Au moins deux.** Une seule broche signifie qu'une régénération de clé
    /// — planifiée ou en urgence après compromission — casse l'application
    /// jusqu'à la prochaine version sur l'App Store, soit plusieurs jours. La
    /// broche de secours est ce qui rend la rotation possible.
    public let spkiSHA256Base64: Set<String>

    /// `false` journalise sans bloquer.
    ///
    /// Sert au déploiement progressif : on observe le taux d'échec réel avant
    /// de fermer. Un épinglage activé d'emblée sur une broche fausse coupe
    /// tous les clients d'un coup.
    public let isEnforced: Bool

    public init(host: String, spkiSHA256Base64: Set<String>, isEnforced: Bool) {
        self.host = host
        self.spkiSHA256Base64 = spkiSHA256Base64
        self.isEnforced = isEnforced
    }
}

/// Fournit les politiques d'épinglage en vigueur.
///
/// Un fournisseur plutôt qu'une constante : le §11 exige une **rotation
/// d'urgence**, donc les broches doivent pouvoir changer sans livrer une
/// nouvelle version. L'implémentation décide de la source — configuration
/// signée, valeurs compilées de secours — mais la couche réseau n'en sait rien.
public protocol CertificatePinProviding: Sendable {

    /// Politique applicable à cet hôte, ou `nil` si l'hôte n'est pas épinglé.
    ///
    /// `nil` **n'est pas** un échec : tous les hôtes ne sont pas épinglés, et
    /// rendre l'absence de politique bloquante casserait les CDN et les
    /// domaines tiers légitimes.
    func policy(for host: String) -> CertificatePinPolicy?
}

/// N'épingle rien.
///
/// Défaut explicite. Rend l'absence d'épinglage visible dans le graphe de
/// dépendances plutôt que silencieuse — on voit qui l'a injecté.
public struct NoCertificatePinning: CertificatePinProviding {
    public init() {}
    public func policy(for host: String) -> CertificatePinPolicy? { nil }
}

/// Échec d'épinglage, à des fins d'audit.
public enum CertificatePinningFailure: Error, Sendable, Equatable {

    /// La chaîne présentée ne contient aucune clé épinglée.
    case noPinMatched(host: String)

    /// La chaîne n'a pas passé la validation système avant même l'épinglage.
    case systemTrustRejected(host: String)

    /// La clé publique n'a pas pu être extraite du certificat.
    case publicKeyUnavailable(host: String)
}
