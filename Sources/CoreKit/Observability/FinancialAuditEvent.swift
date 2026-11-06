//
//  FinancialAuditEvent.swift
//  CoreKit
//
//  Journal d'audit métier — Bloc 4 §36 (GAP-08).
//

import Foundation

/// Un fait métier consigné, immuable.
///
/// **Distinct d'`AuditBreadcrumb`**, qui couvre la sécurité. La ligne « Audit »
/// de la matrice transversale du Bloc 4 était vide sur les huit chapitres : un
/// bloc qui manipule mandats, prélèvements et jetons porteurs de valeur n'avait
/// aucune trace métier.
///
/// Ne porte **aucun secret** : ni jeton, ni code, ni PIN. Les identifiants
/// d'objet y sont hachés, comme dans `FinanceLogContext` — un journal d'audit
/// qui fuit est un journal qui aggrave l'incident qu'il documente.
public struct FinancialAuditEvent: Sendable, Hashable, Codable {

    public let id: String
    public let action: FinancialAuditAction
    public let category: FinancialAuditCategory

    /// Qui a agi. `system` pour une exécution automatique de mandat.
    public let actorID: String
    public let actorType: String

    /// Objet concerné, **haché**.
    public let resourceIDHash: String

    /// Horodatage **local**, celui de l'appareil.
    ///
    /// Renommé depuis `occurredAt` pour dire ce qu'il est. L'horloge d'un
    /// téléphone se règle à la main : sur un appareil compromis, c'est une
    /// valeur que l'attaquant choisit. Elle sert au débogage, jamais à ordonner
    /// des faits.
    public let occurredAtClient: Date

    /// Horodatage **serveur**, seul faisant foi.
    ///
    /// `nil` tant que l'événement n'a pas été accepté : le §21 exige un
    /// horodatage serveur, et le fabriquer côté client reviendrait à signer une
    /// preuve avec l'outil qu'on cherche à contrôler.
    public let occurredAtServer: Date?

    public let correlationID: CorrelationId

    /// Événement qui a **causé** celui-ci.
    ///
    /// Distinct de `correlationID`, qui regroupe : la corrélation dit « même
    /// histoire », la causation dit « à cause de quoi ». Sans elle, une chaîne
    /// d'actions ne se reconstitue pas, et c'est la capacité forensic du §23
    /// qui disparaît.
    public let causationID: String?

    /// Session au cours de laquelle l'action a eu lieu.
    public let sessionID: String?

    /// Appareil ayant émis l'action, **haché**.
    ///
    /// Haché comme `resourceIDHash` : un identifiant d'appareil en clair dans un
    /// journal exporté est un traceur qui suit l'utilisateur.
    public let deviceIDHash: String?

    /// Décision Risk invoquée, s'il y en a eu une.
    ///
    /// L'identifiant, pas le verdict : le journal doit permettre de retrouver la
    /// décision dans le moteur qui l'a rendue, pas d'en rejouer une copie
    /// locale qui pourrait diverger.
    public let riskDecisionID: String?

    /// Décision Compliance invoquée, même règle.
    public let complianceDecisionID: String?

    /// Empreinte de l'événement précédent de la chaîne.
    ///
    /// Le §22 place la chaîne **côté serveur** — le mobile n'est jamais la
    /// source unique de preuve. Le champ est transporté, pas calculé ici : le
    /// remplir localement donnerait une chaîne que l'attaquant B peut réécrire
    /// en entier, c'est-à-dire une garantie qui n'en est pas une.
    public let previousHash: String?

    /// Contexte additionnel. Le constructeur écarte les clés sensibles.
    public let metadata: [String: String]

    public init(
        // Minuscules : `UUID.uuidString` rend des majuscules, et la convention
        // du projet est le minuscule partout — sur le fil, en base, dans les
        // journaux. Un même identifiant émis dans les deux casses produit deux
        // chaînes qui ne comparent jamais égal, donc des événements qui ne se
        // corrèlent simplement pas. Pour un journal d'audit, dont la corrélation
        // est la seule raison d'être, le défaut est total et silencieux.
        id: String = UUID().lowercasedString,
        action: FinancialAuditAction,
        category: FinancialAuditCategory,
        actorID: String,
        actorType: String,
        resourceIDHash: String,
        occurredAtClient: Date = Date(),
        occurredAtServer: Date? = nil,
        correlationID: CorrelationId,
        causationID: String? = nil,
        sessionID: String? = nil,
        deviceIDHash: String? = nil,
        riskDecisionID: String? = nil,
        complianceDecisionID: String? = nil,
        previousHash: String? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.action = action
        self.category = category
        self.actorID = actorID
        self.actorType = actorType
        self.resourceIDHash = resourceIDHash
        self.occurredAtClient = occurredAtClient
        self.occurredAtServer = occurredAtServer
        self.correlationID = correlationID
        self.causationID = causationID
        self.sessionID = sessionID
        self.deviceIDHash = deviceIDHash
        self.riskDecisionID = riskDecisionID
        self.complianceDecisionID = complianceDecisionID
        self.previousHash = previousHash
        // Le filtre est ici plutôt qu'au site d'appel : un journal d'audit est
        // consulté après incident, quand personne ne relit les appelants.
        self.metadata = metadata.filter { !FinancialAuditEvent.forbiddenKeys.contains($0.key.lowercased()) }
    }

    /// Clés qui ne doivent jamais entrer dans un journal d'audit.
    public static let forbiddenKeys: Set<String> = [
        "pin", "otp", "token", "secret", "cvv", "pan", "code",
        "cashoutcode", "electricitytoken", "voucher", "password", "authorization"
    ]
}

public enum FinancialAuditAction: String, Codable, Sendable, CaseIterable {
    case created, confirmed, executed, failed, cancelled
    case refundRequested, refunded, reversed, disputed
    case mandateCreated, mandateSuspended, mandateResumed, mandateRevoked
    case mandateExecuted
    case secretRevealed, secretShared
    case configurationRejected
    case killSwitchHonoured
}

public enum FinancialAuditCategory: String, Codable, Sendable, CaseIterable {
    case payment, mandate, delivery, refund, dispute, configuration, support
}
