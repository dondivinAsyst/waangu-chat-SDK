//
//  MerchantProfileProviding.swift
//  CoreKit
//
//  Profil marchand et paiement marchand — Bloc 1, chapitre 7.
//
//  **BACKEND CONTRACT REQUIRED** — profil, vérification KYB, encaissement.
//

import Foundation

/// Le profil d'un marchand, et le paiement qu'on lui fait.
///
/// Un marchand n'est pas un utilisateur avec un badge. C'est un acteur dont
/// l'identité a été **vérifiée par quelqu'un** (KYB), dont le statut peut être
/// retiré, et à qui l'on paie de l'argent en confiance parce que cette
/// vérification tient. Rien de tout cela n'est déductible côté client.
public protocol MerchantProfileProviding: Sendable {

    /// Profil complet d'un marchand.
    func profile(merchantID: String) async -> Result<MerchantProfile, FinanceError>

    /// Revalide une identité épinglée **juste avant** de payer.
    ///
    /// Un profil lu à l'ouverture de l'écran vieillit pendant que l'utilisateur
    /// tape un montant. Entre les deux, le marchand a pu être suspendu, perdre
    /// sa licence, ou changer de bénéficiaire. Payer sur la foi du profil chargé
    /// il y a deux minutes, c'est payer une identité qui n'existe peut-être plus.
    func revalidate(
        _ snapshot: MerchantIdentitySnapshot
    ) async -> Result<MerchantIdentityVerdict, FinanceError>

    /// Prépare un paiement vers ce marchand. Séparé de l'exécution : entre les
    /// deux, l'utilisateur voit un montant et le confirme.
    ///
    /// `identity` épingle **ce que l'utilisateur a vu**. Le backend rejette un
    /// devis demandé sur une identité périmée : c'est la seule défense contre
    /// une substitution de marchand entre l'affichage et le paiement.
    func quotePayment(
        merchantID: String,
        amount: Money,
        reference: String?,
        conversationID: String?,
        identity: MerchantIdentitySnapshot
    ) async -> Result<FinancialQuote, FinanceError>
}

// MARK: - Identité épinglée

/// Ce que l'utilisateur avait sous les yeux, figé.
///
/// Trois versions distinctes, parce que trois choses bougent indépendamment :
/// l'identité légale, les capacités accordées, et la politique affichée. Une
/// seule version globale rendrait impossible de dire *ce qui* a changé, donc
/// impossible de décider s'il faut un nouveau consentement ou un simple refus.
public struct MerchantIdentitySnapshot: Codable, Sendable, Hashable {

    public let merchantID: String

    /// Version de l'identité légale — raison sociale, bénéficiaire, KYB.
    public let identityVersion: String

    /// Version des politiques affichées — retours, remboursements.
    public let policyVersion: String

    /// Statut de vérification **au moment de l'affichage**.
    public let verification: VerificationStatus

    public let capturedAt: Date

    /// Échéance des capacités accordées au marchand. `nil` ⇒ le backend n'en
    /// borne pas la validité, ce qui n'est pas la même chose que « illimité » :
    /// c'est à lui de trancher, pas à l'écran de supposer.
    public let capabilityExpiresAt: Date?

    public init(merchantID: String, identityVersion: String, policyVersion: String,
                verification: VerificationStatus, capturedAt: Date,
                capabilityExpiresAt: Date? = nil) {
        self.merchantID = merchantID
        self.identityVersion = identityVersion
        self.policyVersion = policyVersion
        self.verification = verification
        self.capturedAt = capturedAt
        self.capabilityExpiresAt = capabilityExpiresAt
    }

    /// Capacité expirée : le marchand ne peut plus encaisser, quoi qu'en dise
    /// le profil affiché.
    public func hasExpiredCapability(at now: Date = Date()) -> Bool {
        guard let capabilityExpiresAt else { return false }
        return now >= capabilityExpiresAt
    }

    /// Trop vieux pour être payé sans revalidation.
    ///
    /// Une borne locale ne remplace pas le verdict serveur : elle évite
    /// seulement d'envoyer un devis qu'on sait déjà périmé, et elle force la
    /// revalidation quand l'écran est resté ouvert longtemps.
    public func isStale(at now: Date = Date(), maxAge: TimeInterval = 120) -> Bool {
        hasExpiredCapability(at: now) || now.timeIntervalSince(capturedAt) > maxAge
    }
}

/// Ce que le backend répond à une revalidation.
///
/// `changed` n'est **pas** une erreur : c'est un profil neuf que l'utilisateur
/// doit revoir. Le confondre avec un refus ferait abandonner un paiement
/// légitime ; le confondre avec `unchanged` ferait payer une identité que
/// l'utilisateur n'a jamais vue.
public enum MerchantIdentityVerdict: Sendable, Equatable {

    /// Rien n'a bougé : le paiement peut suivre.
    case unchanged

    /// Le profil a changé. À réafficher avant tout paiement.
    case changed(MerchantProfile)

    /// Suspendu par l'opérateur — temporaire, motivé.
    case suspended(reasonKey: String)

    /// Vérification retirée. Aucun paiement, aucun contournement.
    case revoked(reasonKey: String)

    /// Seul `unchanged` autorise à enchaîner sans geste utilisateur.
    public var permitsImmediatePayment: Bool { self == .unchanged }
}

// MARK: - Le profil

public struct MerchantProfile: Codable, Sendable, Hashable, Identifiable {

    public var id: String { actor.actorID }

    /// L'identité, avec son statut de vérification. C'est `actor.verification`
    /// qui décide du badge — pas un booléen local.
    public let actor: FinancialActor

    public let categoryKey: String?
    public let descriptionKey: String?

    /// Logo. `nil` ⇒ pas d'image, et surtout pas une image d'un autre marchand.
    public let logoURL: URL?

    /// Adresse affichable. Non structurée volontairement : le format d'adresse
    /// varie par pays, et l'imposer ici produirait des adresses fausses.
    public let addressLine: String?

    /// Coordonnée de contact **publiée par le marchand**, pas déduite du compte.
    public let publicContact: String?

    /// Le marchand accepte-t-il d'être payé en ce moment ? Un marchand fermé,
    /// suspendu ou en revue reste consultable mais ne s'encaisse pas.
    public let acceptsPayments: Bool
    public let unavailableReasonKey: String?

    /// Devises acceptées, **avec leur exposant décimal**.
    ///
    /// Un simple code ISO ne suffit pas : BIF vaut 0, CAD vaut 2, et certains
    /// rails travaillent en 3. Passer le code seul obligeait l'écran à deviner
    /// l'exposant pour composer un `Money` — un facteur 100 sur un montant réel.
    ///
    /// Vide ⇒ le backend ne l'a pas dit, et l'écran ne propose aucun paiement
    /// plutôt que d'en supposer une.
    public let acceptedCurrencies: [CurrencyCode]

    /// Politique de retour affichable, quand le marchand en publie une.
    public let returnPolicyKey: String?

    /// Version de l'identité légale, **rendue par le backend**.
    public let identityVersion: String

    /// Version des politiques affichées.
    public let policyVersion: String

    /// Échéance des capacités du marchand.
    public let capabilityExpiresAt: Date?

    public init(
        actor: FinancialActor, categoryKey: String? = nil, descriptionKey: String? = nil,
        logoURL: URL? = nil, addressLine: String? = nil, publicContact: String? = nil,
        acceptsPayments: Bool, unavailableReasonKey: String? = nil,
        acceptedCurrencies: [CurrencyCode] = [], returnPolicyKey: String? = nil,
        identityVersion: String, policyVersion: String,
        capabilityExpiresAt: Date? = nil
    ) {
        self.actor = actor
        self.categoryKey = categoryKey
        self.descriptionKey = descriptionKey
        self.logoURL = logoURL
        self.addressLine = addressLine
        self.publicContact = publicContact
        self.acceptsPayments = acceptsPayments
        self.unavailableReasonKey = unavailableReasonKey
        self.acceptedCurrencies = acceptedCurrencies
        self.returnPolicyKey = returnPolicyKey
        self.identityVersion = identityVersion
        self.policyVersion = policyVersion
        self.capabilityExpiresAt = capabilityExpiresAt
    }

    /// Épingle ce profil tel qu'il est affiché.
    ///
    /// **Non dérivable du seul `merchantID`** : ce sont les versions qui font la
    /// valeur de l'instantané, et elles viennent du backend.
    public func snapshot(at now: Date = Date()) -> MerchantIdentitySnapshot {
        MerchantIdentitySnapshot(
            merchantID: actor.actorID,
            identityVersion: identityVersion,
            policyVersion: policyVersion,
            verification: actor.verification,
            capturedAt: now,
            capabilityExpiresAt: capabilityExpiresAt
        )
    }

    /// Payable **et** autorisé à encaisser.
    ///
    /// Les deux conditions sont distinctes : un marchand peut être vérifié mais
    /// fermé, ou ouvert mais suspendu. Payer un marchand révoqué envoie de
    /// l'argent vers un compte que l'opérateur a lui-même désavoué.
    public var isPayable: Bool {
        acceptsPayments
            && actor.permissions.contains(.execute)
            && !actor.verification.warrantsWarning
    }
}

// MARK: - Défaut fermé

/// Refuse tout profil et tout devis.
///
/// Le défaut ne fabrique pas de marchand fictif : un profil inventé affiche un
/// badge de confiance sur une identité que personne n'a vérifiée.
public struct ClosedMerchantProfileProvider: MerchantProfileProviding {

    public init() {}

    public func profile(merchantID: String) async -> Result<MerchantProfile, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func revalidate(
        _ snapshot: MerchantIdentitySnapshot
    ) async -> Result<MerchantIdentityVerdict, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func quotePayment(
        merchantID: String, amount: Money, reference: String?,
        conversationID: String?, identity: MerchantIdentitySnapshot
    ) async -> Result<FinancialQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
