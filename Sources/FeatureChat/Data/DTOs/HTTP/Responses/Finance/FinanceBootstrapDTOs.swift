//
//  FinanceBootstrapDTOs.swift
//  FeatureChat
//
//  Phase 1 — amorçage de session et Hub (INTEGRATION_CHAT_FINANCE.md §1–2).
//
//  Ces types suivent le JSON du contrat, champ pour champ. Tout champ dont le
//  contrat ne garantit pas la présence est optionnel : un champ absent ne doit
//  jamais faire échouer le décodage de tout l'amorçage, et son absence est lue
//  **fermée** par les mappers (un droit non affirmé n'est pas un droit).
//

import Foundation

// MARK: - §1.2 — GET /chat-core/experience/config

struct ExperienceConfigDTO: Decodable, Equatable, Sendable {
    let schemaVersion: String?
    let country: String?
    let allowedCountries: [String]?
    let countryApproved: Bool?
    let countryLocalized: Bool?
    let currency: String?
    let paymentsAllowed: Bool?
    let financialActionsLocked: Bool?
    let safeMode: String?
    let killSwitchGlobal: Bool?
    let killSwitchCountry: Bool?
    let contractVersion: String?
    let configGeneration: Int?
    let configHash: String?
    /// `false` ⇒ plus aucune consultation financière (solde, relevé, cartes).
    /// Absent ⇒ aucune restriction **de plus** : les serveurs antérieurs ne
    /// l'envoient pas, et `FINANCE_READ` reste exigé de toute façon.
    var consultationAllowed: Bool? = nil
    /// Relecture de statut (`intent/requery`) permise. Lu, pas encore appliqué.
    var statusRequeryAllowed: Bool? = nil
}

// MARK: - §1.3 — GET /chat-core/governance/capabilities

struct GovernanceSnapshotDTO: Decodable, Equatable, Sendable {
    let schemaVersion: String?
    let country: String?
    let countryApproved: Bool?
    let allowedCountries: [String]?
    let currency: String?
    let contractVersion: String?
    let configGeneration: Int?
    let configHash: String?
    let killSwitchGlobal: Bool?
    let killSwitchCountry: Bool?
    let safeMode: String?
    let paymentsAllowed: Bool?
    let capabilities: [CapabilityDecisionDTO]
}

/// Une décision effective par capacité — `EffectiveCapabilityDecision`.
struct CapabilityDecisionDTO: Decodable, Equatable, Sendable {
    let country: String?
    let capabilityKey: String
    /// `GENERAL` · `PILOT` · `LIMITED` · `INTERNAL` · `PARTNER_ONLY` · `DISABLED` · `PROHIBITED`.
    let state: String?
    let countryApproved: Bool?
    let killSwitch: Bool?
    let allowed: Bool?
    let reason: String?
    let errorCode: String?
}

// MARK: - §1.5 — GET /chat-core/security/capabilities

/// Capacités de **session** (epoch, risque, kill-switch sécurité).
///
/// **Le contrat ne publie pas ce JSON.** Il nomme les capacités (`FINANCE_READ`,
/// `PAYMENT_PREPARE`, `PAYMENT_CONFIRM`, `CASH_OUT`, …) et `financialActionsLocked`,
/// sans la forme de la liste. D'où un décodage qui accepte toutes les formes
/// raisonnables et **ne lève jamais** :
///
/// - `"capabilities": ["FINANCE_READ", …]` — listée ⇒ accordée ;
/// - `"capabilities": [{ "capability": "FINANCE_READ", "disposition": "ALLOW" }]` — **forme réelle**
///   du serveur ; seul `ALLOW` accorde, `UNAVAILABLE` ou toute autre valeur refuse ;
/// - `"capabilities": [{ "key"|"capabilityKey"|"name": "…", "allowed"|"granted": true }]` ;
/// - `"capabilities": { "FINANCE_READ": true, … }` ou `{ "FINANCE_READ": { "allowed": true } }` ;
/// - un tableau racine à la place de l'objet.
///
/// Une forme inattendue donne **aucun droit** (tout refusé), jamais un échec
/// de décodage : sinon tout l'amorçage tomberait, et avec lui la lecture —
/// alors que le serveur l'autorise peut-être.
struct SecurityCapabilitiesDTO: Decodable, Equatable, Sendable {
    let financialActionsLocked: Bool?
    let capabilities: [SecurityCapabilityDTO]?

    init(financialActionsLocked: Bool?, capabilities: [SecurityCapabilityDTO]?) {
        self.financialActionsLocked = financialActionsLocked
        self.capabilities = capabilities
    }

    private enum CodingKeys: String, CodingKey { case financialActionsLocked, capabilities }

    init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            // Tableau racine : la liste elle-même.
            self.init(financialActionsLocked: nil, capabilities: Self.list(from: decoder))
            return
        }
        let locked: Bool? = try? container.decodeIfPresent(Bool.self, forKey: .financialActionsLocked)
        let capabilities: [SecurityCapabilityDTO]?
        if let nested = try? container.superDecoder(forKey: .capabilities) {
            capabilities = Self.list(from: nested) ?? Self.map(from: nested)
        } else {
            capabilities = nil
        }
        self.init(financialActionsLocked: locked, capabilities: capabilities)
    }

    /// `true` si le serveur accorde explicitement cette capacité.
    ///
    /// Clés comparées sous une forme normalisée (B41). Dans la forme dictionnaire
    /// (`{ "FINANCE_READ": true }`), le décodeur imbriqué hérite de
    /// `convertFromSnakeCase` — celui de `APIClient` aussi — et livre la clé
    /// `financeRead` : comparée telle quelle, aucune capacité n'était accordée.
    func allows(_ key: String) -> Bool {
        let wanted = Self.normalized(key)
        return capabilities?.contains { Self.normalized($0.key) == wanted && $0.allowed } ?? false
    }

    /// Même forme avant et après `convertFromSnakeCase` : minuscules, sans `_`.
    static func normalized(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: "").lowercased()
    }

    private static func list(from decoder: Decoder) -> [SecurityCapabilityDTO]? {
        guard let items = try? [LossyCapability](from: decoder) else { return nil }
        return items.compactMap(\.value)
    }

    private static func map(from decoder: Decoder) -> [SecurityCapabilityDTO]? {
        if let flags = try? [String: Bool](from: decoder) {
            return flags.map { SecurityCapabilityDTO(key: $0.key, allowed: $0.value) }
        }
        if let objects = try? [String: GrantFlag](from: decoder) {
            return objects.map { SecurityCapabilityDTO(key: $0.key, allowed: $0.value.allowed) }
        }
        return nil
    }

    /// Un élément illisible est ignoré — il ne fait pas tomber les autres.
    private struct LossyCapability: Decodable {
        let value: SecurityCapabilityDTO?
        init(from decoder: Decoder) throws { value = try? SecurityCapabilityDTO(from: decoder) }
    }

    private struct GrantFlag: Decodable {
        let allowed: Bool
        private enum CodingKeys: String, CodingKey { case disposition, allowed, granted }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            // `try?` aplatit déjà l'optionnel : absent ou illisible ⇒ refusé.
            let disposition: String? = try? container.decodeIfPresent(String.self, forKey: .disposition)
            let allowed: Bool? = try? container.decodeIfPresent(Bool.self, forKey: .allowed)
            let granted: Bool? = try? container.decodeIfPresent(Bool.self, forKey: .granted)
            self.allowed = SecurityCapabilityDTO.isGranted(disposition: disposition, allowed: allowed ?? granted)
        }
    }
}

struct SecurityCapabilityDTO: Decodable, Equatable, Sendable {
    let key: String
    let allowed: Bool

    private enum CodingKeys: String, CodingKey { case key, capability, capabilityKey, name, disposition, allowed, granted }

    init(key: String, allowed: Bool) { self.key = key; self.allowed = allowed }

    init(from decoder: Decoder) throws {
        if let raw = try? decoder.singleValueContainer().decode(String.self) {
            // Une capacité listée seule est une capacité accordée.
            self.init(key: raw, allowed: true)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let key = try container.decodeIfPresent(String.self, forKey: .key)
            ?? container.decodeIfPresent(String.self, forKey: .capabilityKey)
            ?? container.decodeIfPresent(String.self, forKey: .capability)
            ?? container.decode(String.self, forKey: .name)
        let disposition = try container.decodeIfPresent(String.self, forKey: .disposition)
        let allowed = try container.decodeIfPresent(Bool.self, forKey: .allowed)
            ?? container.decodeIfPresent(Bool.self, forKey: .granted)
        self.init(key: key, allowed: Self.isGranted(disposition: disposition, allowed: allowed))
    }

    /// `disposition` l'emporte quand il est présent : **seul `ALLOW` accorde**.
    /// `UNAVAILABLE` (moteur de risque absent), `DENY` ou une valeur inconnue
    /// refusent. Sans `disposition`, le booléen décide ; sans rien, refusé.
    static func isGranted(disposition: String?, allowed: Bool?) -> Bool {
        if let disposition { return disposition.uppercased() == "ALLOW" }
        return allowed ?? false
    }
}

// MARK: - §1.6 — GET|POST /chat-core/financial/session/resume

struct ResumeStateDTO: Decodable, Equatable, Sendable {
    let userId: String?
    let tenantId: String?
    let sessionId: String?
    let deviceId: String?
    let syncAcknowledged: Bool?
    let iamValid: Bool?
    let complianceValid: Bool?
    let capabilityValid: Bool?
    let resumedAt: String?
    let expiresAt: String?
    let locked: Bool?
}

// MARK: - §5.1.1 — GET /chat-core/financial/self-conversation

/// Le dossier personnel — « Mes factures ».
///
/// Payer sa facture n'a **pas** de destinataire chat : l'argent va au
/// facturier. Ouvrir un 1-1 avec quelqu'un pour payer sa propre facture n'a
/// aucun sens, et c'est pourtant ce qu'exigeait l'ancien contrat, qui refusait
/// un prepare sans `conversationId` (`SYS_002`, « conversationId must not be
/// blank »). Core tient désormais un dossier à un seul membre, qu'il crée ou
/// réutilise, et c'est lui que portent le prepare et l'execute des factures,
/// recharges et opérations d'espèces ouvertes hors conversation.
struct SelfConversationDTO: Decodable, Equatable, Sendable {
    let conversationId: String
    /// Époque d'appartenance à envoyer en `X-Membership-Epoch` — périmée ⇒ `CF_074`.
    let membershipEpoch: Int?
    let kind: String?
    /// Intitulé rédigé par le serveur (« Mes factures »), pas par l'app.
    let title: String?
    /// Type à passer au Hub (`SELF`) pour obtenir les actions de ce dossier.
    let hubConversationType: String?
}

// MARK: - §2.1 — GET /chat-core/financial/hub/actions

struct ResolvedActionDTO: Decodable, Equatable, Sendable {
    let code: String
    let label: String?
    let intentType: String?
    let version: String?
    let visible: Bool?
    let enabled: Bool?
    let requiresStepUp: Bool?
    let shortcutGroup: String?
    let reason: String?
}

// MARK: - §2.2 — POST /chat-core/financial/hub/intent/parse

/// Un texte lu par le Hub. `draftOnly` est **toujours** `true` : c'est un
/// brouillon, jamais une commande (`CF_027` si on le traite comme tel).
struct IntentDraftDTO: Decodable, Equatable, Sendable {
    let actionCode: String?
    let rawText: String?
    let amountMinor: Int64?
    let currency: String?
    let counterpartyHint: String?
    let draftOnly: Bool?
    let message: String?
}

// MARK: - §2.3 — POST /chat-core/financial/hub/handoff (+ /consume)

/// Le contexte que le jeton transporte — rendu une seule fois par `/consume`.
struct HandoffPayloadDTO: Decodable, Equatable, Sendable {
    let userId: String?
    let conversationId: String?
    let actionCode: String?
    let financialIntentRef: String?
    let tenantId: String?
    let country: String?
}

/// `HandoffTicket` — jeton à usage unique, lié à l'utilisateur, ~3 min.
struct HandoffTicketDTO: Decodable, Equatable, Sendable {
    let token: String
    let expiresAt: String?
    let payload: HandoffPayloadDTO?
}
