//
//  NotificationRedactor.swift
//  CoreKit
//
//  Ce qu'une notification financière a le droit de montrer — Bloc 3 §28 et §53.
//

import Foundation

/// Décide de ce qui peut apparaître dans une notification financière.
///
/// **Liste blanche, pas liste noire.** Interdire « PAN, CVV, PIN, OTP, code de
/// retrait » suppose de les reconnaître ; il suffit qu'un champ arrive sous un
/// nom neuf pour passer. Ici seuls les champs explicitement déclarés sûrs
/// survivent, et tout le reste disparaît — y compris ce que cette version du
/// client ne sait pas nommer.
///
/// La différence n'est pas théorique : un code de retrait est un **porteur de
/// valeur**. Contrairement à un identifiant d'opération, quiconque le lit sur un
/// écran verrouillé peut retirer l'argent.
public struct NotificationRedactor: Sendable {

    public init() {}

    /// Champs autorisés dans une notification financière.
    ///
    /// Aucun ne permet, seul ou combiné, d'exécuter une opération ni d'identifier
    /// un compte. Ils servent à dire *qu'il s'est passé quelque chose*, jamais
    /// *quoi exactement* — le détail se lit dans l'application, après
    /// déverrouillage.
    public static let allowedKeys: Set<String> = [
        "type",            // nature de l'événement
        "objectType",      // PAYMENT, MONEY_REQUEST…
        "objectId",        // opaque, non exploitable seul
        "version",         // révision, pour éviter une lecture inutile
        "correlationId",   // corrélation technique
        "conversationId",  // pour router vers le bon fil
        "timestamp"
    ]

    /// Champs dont la seule présence doit alerter.
    ///
    /// Ils ne sont pas filtrés — la liste blanche s'en charge — mais leur
    /// arrivée signale que le backend envoie des données qu'il ne devrait pas,
    /// et cela doit remonter avant qu'un autre client, moins strict, les affiche.
    public static let forbiddenKeys: Set<String> = [
        "pan", "cardNumber", "cvv", "pin", "otp", "token", "accessToken",
        "authorization", "cashOutCode", "withdrawalCode", "secret",
        "qrSecret", "accountNumber", "iban", "kycDocument", "biometric"
    ]

    // MARK: - Redaction

    public struct Result: Sendable, Equatable {
        public let payload: [String: String]
        /// Clés interdites rencontrées. Non vide ⇒ incident à journaliser.
        public let forbiddenEncountered: [String]
        /// Clés inconnues écartées par la liste blanche.
        public let droppedKeys: [String]
    }

    /// Ne garde que ce qui est explicitement autorisé.
    public func redact(_ payload: [String: String]) -> Result {
        var kept: [String: String] = [:]
        var forbidden: [String] = []
        var dropped: [String] = []

        for (key, value) in payload {
            let normalised = key.lowercased()

            if Self.forbiddenKeys.contains(where: { $0.lowercased() == normalised }) {
                forbidden.append(key)
                continue
            }
            if Self.allowedKeys.contains(key) {
                kept[key] = value
            } else {
                dropped.append(key)
            }
        }

        return Result(
            payload: kept,
            forbiddenEncountered: forbidden.sorted(),
            droppedKeys: dropped.sorted()
        )
    }

    // MARK: - Texte visible

    /// Corps de notification sûr pour un événement financier.
    ///
    /// **Aucun montant, aucune contrepartie, aucune référence.** Un écran
    /// verrouillé est lisible par quiconque tient le téléphone : « Vous avez
    /// reçu 250 000 BIF de Jean D. » désigne à la fois une somme et une
    /// relation, sans que personne ne se soit authentifié.
    ///
    /// Le texte dit qu'il s'est passé quelque chose et invite à ouvrir.
    public func safeBody(for kind: FinancialNotificationKind) -> String {
        switch kind {
        case .paymentReceived:   return "notification.finance.payment_received"
        case .paymentSent:       return "notification.finance.payment_sent"
        case .paymentFailed:     return "notification.finance.payment_failed"
        case .moneyRequested:    return "notification.finance.money_requested"
        case .refundUpdate:      return "notification.finance.refund_update"
        case .actionRequired:    return "notification.finance.action_required"
        case .securityAlert:     return "notification.finance.security_alert"
        }
    }

    /// `true` si l'aperçu doit être masqué même déverrouillé.
    ///
    /// Une alerte de sécurité et une action requise touchent des parcours où
    /// l'utilisateur doit s'authentifier de toute façon : afficher un aperçu
    /// n'apporte rien et donne une prise de plus.
    public func requiresHiddenPreview(for kind: FinancialNotificationKind) -> Bool {
        kind == .securityAlert || kind == .actionRequired
    }
}

// MARK: - Nature

public enum FinancialNotificationKind: String, Codable, Sendable, CaseIterable {
    case paymentReceived, paymentSent, paymentFailed
    case moneyRequested, refundUpdate, actionRequired, securityAlert

    /// Une nature inconnue devient `actionRequired` : la plus discrète, et celle
    /// qui invite à ouvrir l'application plutôt qu'à conclure quoi que ce soit.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FinancialNotificationKind(rawValue: raw) ?? .actionRequired
    }
}
