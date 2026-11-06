//
//  DeepLinkValidator.swift
//  SecurityKit
//
//  Bloc 9, G9-06 (§15) — les liens profonds n'étaient ni signés, ni datés,
//  ni protégés contre le rejeu.
//

import Foundation
import WaanguCoreKit
import CryptoKit
import OSLog

/// Applique les étapes du §15 avant qu'un lien n'atteigne la navigation.
///
/// Ce validateur ne remplace pas `DeepLinkParser` : le parseur décide *où* va le
/// lien, le validateur décide *s'il a le droit d'y aller*. Les deux sont
/// séparés pour que l'ajout d'une route ne puisse pas emporter avec lui une
/// dispense de contrôle.
public actor DeepLinkValidator: DeepLinkValidating {

    /// Nonces déjà consommés.
    ///
    /// En mémoire, donc vidés au redémarrage. C'est une **limite assumée** :
    /// l'anti-rejeu durable appartient au serveur, qui seul voit tous les
    /// appareils. Ce cache attrape le rejeu immédiat — le lien renvoyé deux
    /// fois dans une conversation, le double-tap — pas l'attaquant patient.
    private var consumedNonces: Set<String> = []

    /// Borne du cache. Sans elle, une conversation qui pousse des liens fait
    /// croître l'ensemble jusqu'à la pression mémoire.
    private let maxConsumedNonces: Int

    private let clock: @Sendable () -> Date

    private static let log = Logger(subsystem: "com.waangu.security", category: "deeplink")

    public init(
        maxConsumedNonces: Int = 512,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.maxConsumedNonces = maxConsumedNonces
        self.clock = clock
    }

    public func validate(
        _ link: SecureDeepLink,
        requirement: DeepLinkTrustRequirement
    ) async throws {
        switch requirement {
        case .navigationOnly:
            // Aucune exigence cryptographique : une route de navigation pure ne
            // déplace rien. Exiger une signature ici rendrait les liens de
            // partage inutilisables, et la première dérogation accordée pour
            // cette raison finirait par couvrir aussi les routes financières.
            return

        case .authenticated:
            try checkExpiry(link)

        case .financial:
            // L'ordre compte : vérifier l'échéance avant la signature évite de
            // dépenser une vérification cryptographique sur un lien périmé, et
            // surtout évite qu'un lien expiré mais correctement signé passe
            // parce que la signature a été contrôlée en premier et le reste
            // oublié.
            try checkExpiry(link)
            try checkSignaturePresence(link)
            try checkNonce(link)
        }
    }

    // MARK: - Étapes

    private func checkExpiry(_ link: SecureDeepLink) throws {
        guard let expiresAt = link.expiresAt else { return }
        guard clock() < expiresAt else {
            Self.log.warning("Lien périmé sur \(link.route, privacy: .public)")
            throw DeepLinkRejection.expired(route: link.route)
        }
    }

    private func checkSignaturePresence(_ link: SecureDeepLink) throws {
        guard let signature = link.signature, !signature.isEmpty else {
            throw DeepLinkRejection.missingSignature(route: link.route)
        }
        // La **vérification** de la signature appartient au serveur : la clé
        // publique embarquée serait remplaçable sur un appareil compromis, et
        // une vérification locale donnerait une garantie que l'attaquant B
        // contrôle. Ici on impose seulement sa présence, pour qu'un lien non
        // signé ne traverse jamais le client.
    }

    private func checkNonce(_ link: SecureDeepLink) throws {
        guard let nonce = link.nonce, !nonce.isEmpty else {
            throw DeepLinkRejection.missingNonce(route: link.route)
        }

        guard !consumedNonces.contains(nonce) else {
            Self.log.error("Rejeu détecté sur \(link.route, privacy: .public)")
            throw DeepLinkRejection.replayed(nonce: nonce)
        }

        if consumedNonces.count >= maxConsumedNonces {
            // Purge totale plutôt que partielle : retirer « les plus anciens »
            // demanderait un ordre qu'un `Set` n'a pas, et une purge partielle
            // mal ordonnée rouvrirait une fenêtre de rejeu silencieuse. Vider
            // rend la limite visible — le rejeu redevient possible après 512
            // liens, ce que seul le contrôle serveur ferme pour de bon.
            consumedNonces.removeAll(keepingCapacity: true)
        }

        consumedNonces.insert(nonce)
    }
}
