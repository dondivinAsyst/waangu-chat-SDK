//
//  WaanguPinProvider.swift
//  SecurityKit
//
//  Bloc 9, G9-01 — source des broches d'épinglage.
//

import Foundation
import WaanguCoreKit

/// Sert les broches d'épinglage de production.
///
/// **Les broches ne sont pas encore renseignées.** `pins` est délibérément vide,
/// et tant qu'il l'est ce fournisseur se comporte exactement comme
/// `NoCertificatePinning` : aucun hôte n'est épinglé, aucune connexion n'est
/// refusée. Le mécanisme est en place ; il est inerte.
///
/// Le remplir est une décision d'exploitation, pas de développement : il faut
/// les empreintes SPKI des certificats de production **et** de leur secours,
/// obtenues ainsi :
///
/// ```
/// openssl s_client -servername api.waangu.bi -connect api.waangu.bi:443 \
///   | openssl x509 -pubkey -noout \
///   | openssl pkey -pubin -outform der \
///   | openssl dgst -sha256 -binary | openssl enc -base64
/// ```
///
/// Deux règles à ne pas contourner au moment de les ajouter :
///
/// 1. **Au moins deux broches par hôte.** Une seule signifie qu'une
///    régénération de clé — planifiée ou en urgence après compromission — coupe
///    tous les clients jusqu'à la prochaine version sur l'App Store, soit
///    plusieurs jours d'indisponibilité totale.
/// 2. **`isEnforced: false` d'abord.** Le mode observation émet les échecs sans
///    bloquer. Activer directement sur une broche fausse coupe l'ensemble du
///    parc d'un seul coup, et le symptôme — « l'application ne se connecte
///    plus » — ne désigne pas sa cause.
public struct WaanguPinProvider: CertificatePinProviding {

    private let policies: [String: CertificatePinPolicy]

    public init(policies: [CertificatePinPolicy] = WaanguPinProvider.productionPins) {
        self.policies = Dictionary(
            policies.map { ($0.host, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    public func policy(for host: String) -> CertificatePinPolicy? {
        // Correspondance **exacte**. Pas de joker : un `*.waangu.bi` épinglé
        // couvrirait aussi un sous-domaine compromis, ce qui retire à
        // l'épinglage l'essentiel de ce qu'il apporte.
        policies[host]
    }

    /// Broches de production.
    ///
    /// Vide tant que l'exploitation ne les a pas fournies. Laisser un tableau
    /// vide plutôt que des valeurs d'exemple est délibéré : une broche fausse
    /// livrée en production coupe tout le parc, et une valeur d'exemple finit
    /// toujours par être prise pour une vraie.
    public static let productionPins: [CertificatePinPolicy] = []
}
