//
//  FieldGovernance.swift
//  CoreKit
//
//  Registre de gouvernance des champs — Bloc 5 §24 (GAP5-14).
//

import Foundation

/// Ce qu'on sait d'un champ financier.
///
/// > « Aucun champ financier critique ne doit être *implicite*. » (§24)
///
/// Le registre existe pour qu'une question comme « ce champ est-il persisté ? »
/// ou « est-il redacté dans les logs ? » ait une réponse écrite plutôt qu'à
/// retrouver en lisant le code. Il est déclaratif et vérifiable par test — le
/// but n'est pas de documenter, mais de rendre une omission détectable.
public struct FieldGovernance: Sendable, Hashable, Codable {

    public let fieldName: String
    public let domain: String
    public let type: String
    public let required: Bool

    /// Le champ porte une donnée sensible.
    public let sensitive: Bool

    /// Qui fait autorité. `backend` pour toute valeur financière exécutable.
    public let sourceOfTruth: FieldSource

    /// `true` si le client peut en produire la valeur.
    ///
    /// Doit être `false` pour tout champ dont `sourceOfTruth == .backend` —
    /// c'est l'invariant que `isCoherent` vérifie.
    public let writableByClient: Bool

    public let persistedLocally: Bool
    public let auditable: Bool
    public let redactedInLogs: Bool

    /// `true` quand la persistance passe **exclusivement** par un stockage
    /// protégé — trousseau, Secure Enclave, base chiffrée.
    ///
    /// Ajouté après qu'un test a signalé `refreshToken` comme incohérent : le
    /// champ *est* persisté, et c'est correct. La règle « sensible + persisté =
    /// violation » visait les caches non protégés, `UserDefaults` et les
    /// fichiers temporaires — pas le trousseau. Sans cette distinction, la seule
    /// façon de rendre le registre cohérent était de mentir sur le champ.
    public let protectedStorageOnly: Bool

    public let contractVersion: String

    public init(
        fieldName: String, domain: String, type: String, required: Bool,
        sensitive: Bool, sourceOfTruth: FieldSource, writableByClient: Bool,
        persistedLocally: Bool, auditable: Bool, redactedInLogs: Bool,
        protectedStorageOnly: Bool = false,
        contractVersion: String
    ) {
        self.fieldName = fieldName
        self.domain = domain
        self.type = type
        self.required = required
        self.sensitive = sensitive
        self.sourceOfTruth = sourceOfTruth
        self.writableByClient = writableByClient
        self.persistedLocally = persistedLocally
        self.auditable = auditable
        self.redactedInLogs = redactedInLogs
        self.protectedStorageOnly = protectedStorageOnly
        self.contractVersion = contractVersion
    }
}

public enum FieldSource: String, Codable, Sendable, CaseIterable {
    case backend, client, partner, compliance
}

// MARK: - Invariants

public extension FieldGovernance {

    /// Incohérences de gouvernance détectables mécaniquement.
    ///
    /// Ce ne sont pas des règles de style : chacune décrit une situation où le
    /// champ ferait, en production, exactement ce que l'architecture interdit.
    var violations: [FieldGovernanceViolation] {
        var found: [FieldGovernanceViolation] = []

        // Un champ dont le backend fait autorité et que le client peut écrire
        // est un champ que le client peut fabriquer — un montant, un taux, un
        // statut.
        if sourceOfTruth == .backend && writableByClient {
            found.append(.backendFieldWritableByClient)
        }

        // Un champ sensible non redacté finit en clair dans un journal consulté
        // après incident.
        if sensitive && !redactedInLogs {
            found.append(.sensitiveFieldNotRedacted)
        }

        // Un champ sensible persisté **hors stockage protégé** survit à la
        // perte de l'appareil et se lit dans une sauvegarde.
        if sensitive && persistedLocally && !protectedStorageOnly {
            found.append(.sensitiveFieldPersisted)
        }

        // Une donnée de conformité non auditable ne peut pas être produite en
        // contestation, ce qui la rend inutile là où elle compte.
        if sourceOfTruth == .compliance && !auditable {
            found.append(.complianceFieldNotAuditable)
        }

        return found
    }

    var isCoherent: Bool { violations.isEmpty }
}

public enum FieldGovernanceViolation: String, Sendable, Equatable, CaseIterable {
    case backendFieldWritableByClient
    case sensitiveFieldNotRedacted
    case sensitiveFieldPersisted
    case complianceFieldNotAuditable
}

// MARK: - Registre

/// Le registre des champs critiques du Bloc 5.
///
/// Volontairement non exhaustif à ce stade et **explicitement daté** : il couvre
/// les champs qui portent une valeur financière ou un consentement. Le compléter
/// est un travail continu ; le prétendre complet serait la fausse complétude que
/// le §41 interdit.
public enum FinancialFieldRegistry {

    public static let contractVersion = "1.0"

    public static let entries: [FieldGovernance] = [
        // ── Devis ────────────────────────────────────────────
        .init(fieldName: "exchangeRate", domain: "quote", type: "Decimal", required: true,
              sensitive: false, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),
        .init(fieldName: "totalDebit", domain: "quote", type: "Decimal", required: true,
              sensitive: false, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),
        .init(fieldName: "quoteHash", domain: "quote", type: "String", required: true,
              sensitive: false, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),

        // ── Champs interdits du Bloc 9, §5 ───────────────────
        //
        // Inscrits ici précisément **parce qu'ils ne doivent jamais être
        // persistés ni journalisés**. Un champ absent du registre n'a pas de
        // règle ; un champ présent en a une, et `violations` la vérifie.
        .init(fieldName: "pin", domain: "auth", type: "String", required: false,
              sensitive: true, sourceOfTruth: .client, writableByClient: true,
              persistedLocally: false, auditable: false, redactedInLogs: true,
              contractVersion: contractVersion),
        .init(fieldName: "otp", domain: "auth", type: "String", required: false,
              sensitive: true, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: false, redactedInLogs: true,
              contractVersion: contractVersion),
        .init(fieldName: "cvv", domain: "card", type: "String", required: false,
              sensitive: true, sourceOfTruth: .client, writableByClient: true,
              persistedLocally: false, auditable: false, redactedInLogs: true,
              contractVersion: contractVersion),
        .init(fieldName: "pan", domain: "card", type: "String", required: false,
              sensitive: true, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: false, redactedInLogs: true,
              contractVersion: contractVersion),
        .init(fieldName: "refreshToken", domain: "auth", type: "String", required: true,
              sensitive: true, sourceOfTruth: .backend, writableByClient: false,
              // Persisté, mais **dans le trousseau uniquement**.
              persistedLocally: true, auditable: false, redactedInLogs: true,
              protectedStorageOnly: true,
              contractVersion: contractVersion),
        .init(fieldName: "executionPermitID", domain: "payment", type: "String", required: false,
              sensitive: true, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: true,
              contractVersion: contractVersion),

        // ── Soldes ───────────────────────────────────────────
        .init(fieldName: "availableMinorUnits", domain: "wallet", type: "Int64", required: true,
              sensitive: false, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),

        // ── Porteurs de valeur ───────────────────────────────
        .init(fieldName: "DeliveredSecret.value", domain: "delivery", type: "String", required: true,
              sensitive: true, sourceOfTruth: .partner, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: true,
              contractVersion: contractVersion),
        .init(fieldName: "CashOutAuthorization.code", domain: "cashOut", type: "String", required: true,
              sensitive: true, sourceOfTruth: .backend, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: true,
              contractVersion: contractVersion),

        // ── Consentements ────────────────────────────────────
        .init(fieldName: "consentEvidenceID", domain: "mandate", type: "String", required: true,
              sensitive: false, sourceOfTruth: .compliance, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),
        .init(fieldName: "consentVersion", domain: "mandate", type: "String", required: true,
              sensitive: false, sourceOfTruth: .compliance, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),

        // ── Idempotence ──────────────────────────────────────
        .init(fieldName: "idempotencyKey", domain: "idempotency", type: "String", required: true,
              sensitive: false, sourceOfTruth: .client, writableByClient: true,
              persistedLocally: true, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),

        // ── Crédit ───────────────────────────────────────────
        .init(fieldName: "ratePercent", domain: "credit", type: "Decimal", required: true,
              sensitive: false, sourceOfTruth: .partner, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion),
        .init(fieldName: "suitabilityLevel", domain: "investment", type: "Int", required: true,
              sensitive: false, sourceOfTruth: .compliance, writableByClient: false,
              persistedLocally: false, auditable: true, redactedInLogs: false,
              contractVersion: contractVersion)
    ]

    /// Champs dont la gouvernance est incohérente. **Doit rester vide.**
    public static var incoherentEntries: [FieldGovernance] {
        entries.filter { !$0.isCoherent }
    }
}
