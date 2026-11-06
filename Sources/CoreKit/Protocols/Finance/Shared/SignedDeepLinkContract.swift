//
//  SignedDeepLinkContract.swift
//  CoreKit
//
//  Liens profonds signés — Bloc 6, chapitres 45, 46.2 et 52 (§20).
//
//  **BACKEND CONTRACT REQUIRED** — émission et vérification de signature.
//

import Foundation

/// Contexte transporté par un lien profond **actionnable**.
///
/// Tous les liens n'en ont pas besoin. `waangu://chat/conversation/{id}` ouvre
/// un écran : au pire, l'utilisateur voit une conversation qui n'est pas la
/// sienne — et le serveur le refuse. Un lien qui **déclenche** quelque chose —
/// payer, confirmer une commande, rappeler une mini-app — est d'une autre
/// nature : rejoué, il rejoue l'effet.
///
/// D'où ce contexte : il ne transporte aucune donnée financière, seulement de
/// quoi prouver qu'il a été émis pour **cet** utilisateur, pour **cette** cible,
/// et qu'il n'a pas déjà servi.
public struct SignedDeepLinkContext: Codable, Sendable, Hashable {

    /// Mini-app destinataire. Un contexte émis pour l'une ne vaut pas pour
    /// l'autre : sans ce champ, un lien de taxi ouvrirait un écran de pharmacie.
    public let appID: String

    public let objectType: String
    public let objectID: String

    /// Identifie l'émission. Sert à corréler le lien avec l'événement qui l'a
    /// produit, et donc à l'auditer après coup.
    public let contextID: String

    public let issuedAt: Date
    public let expiresAt: Date

    /// Valeur à usage unique. Consommée à la première ouverture.
    public let nonce: String

    /// Signature du backend émetteur. **Opaque** : elle n'est pas vérifiée ici,
    /// elle est transmise à qui détient la clé.
    public let signature: String

    /// Destinataire prévu — l'utilisateur pour qui le lien a été émis.
    ///
    /// Sans audience, un lien valide reste valide **pour tout le monde** : il
    /// suffirait de le transférer dans une autre conversation.
    public let audience: String?

    public init(appID: String, objectType: String, objectID: String,
                contextID: String, issuedAt: Date, expiresAt: Date,
                nonce: String, signature: String, audience: String? = nil) {
        self.appID = appID
        self.objectType = objectType
        self.objectID = objectID
        self.contextID = contextID
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.nonce = nonce
        self.signature = signature
        self.audience = audience
    }

    /// Expiré. Contrôle **local**, en complément de la vérification serveur.
    ///
    /// Il ne remplace pas la signature : il évite seulement de faire un aller-
    /// retour réseau pour un lien qu'on sait déjà périmé, et il ferme la fenêtre
    /// pendant laquelle un lien capturé reste présentable.
    public func hasExpired(at now: Date = Date()) -> Bool { now >= expiresAt }

    /// Fenêtre de validité anormalement longue.
    ///
    /// Un lien actionnable valable une semaine est un lien qu'on a le temps de
    /// voler. On ne le refuse pas ici — c'est au backend de fixer ses durées —
    /// mais on le signale, parce qu'une émission mal configurée doit se voir.
    public func hasSuspiciousLifetime(maximum: TimeInterval = 3600) -> Bool {
        expiresAt.timeIntervalSince(issuedAt) > maximum
    }
}

// MARK: - Vérification

/// Vérifie un contexte de lien profond.
///
/// La vérification de signature appartient au détenteur de la clé — backend ou
/// `SecurityKit`. Ce protocole est le point de passage obligé, pour qu'aucun
/// écran ne puisse « juste ouvrir » un lien.
public protocol DeepLinkVerifying: Sendable {

    /// Vérifie signature, émetteur, audience, expiration et unicité du nonce.
    func verify(
        _ context: SignedDeepLinkContext,
        expectedAudience: String
    ) async -> DeepLinkVerdict

    /// Marque le nonce comme consommé. Séparé de `verify` : un lien vérifié
    /// mais abandonné avant l'action ne doit pas être brûlé.
    func consume(nonce: String) async
}

/// Pourquoi un lien est refusé.
///
/// Les motifs sont distincts parce qu'ils appellent des réactions différentes :
/// une expiration invite à en redemander un, une signature invalide est un
/// incident de sécurité qui doit être tracé.
public enum DeepLinkVerdict: Sendable, Equatable {

    case valid

    /// Passé sa date. Bénin, fréquent.
    case expired

    /// Signature absente ou fausse. **Incident** : quelqu'un a fabriqué un lien.
    case invalidSignature

    /// Émetteur inconnu.
    case unknownIssuer

    /// Émis pour quelqu'un d'autre. Lien transféré.
    case wrongAudience

    /// Nonce déjà consommé. **Rejeu** : le lien a déjà servi.
    case replayed

    /// La mini-app visée n'est pas autorisée pour cet utilisateur.
    case unauthorizedApp

    /// L'objet visé n'est pas accessible à cet utilisateur.
    case unauthorizedObject

    public var isValid: Bool { self == .valid }

    /// Doit être remonté à l'observabilité comme incident de sécurité, et non
    /// comme simple échec d'ouverture.
    public var isSecurityIncident: Bool {
        switch self {
        case .invalidSignature, .unknownIssuer, .replayed, .wrongAudience:
            return true
        case .valid, .expired, .unauthorizedApp, .unauthorizedObject:
            return false
        }
    }
}

// MARK: - Garde anti-rejeu locale

/// Retient les nonces déjà consommés sur cet appareil.
///
/// **Première ligne, pas la dernière.** L'autorité reste le backend : un
/// registre local ne voit pas les ouvertures faites sur un autre appareil. Il
/// arrête le cas courant — le lien retapé deux fois, l'utilisateur qui revient
/// en arrière — sans aller-retour réseau.
public actor DeepLinkNonceStore {

    private struct Entry {
        let consumedAt: Date
        let expiresAt: Date
    }

    private var consumed: [String: Entry] = [:]

    /// Durée de rétention au-delà de l'expiration du lien.
    ///
    /// Retenir un nonce moins longtemps que le lien ne vit rouvrirait la fenêtre
    /// de rejeu juste avant l'expiration.
    private let grace: TimeInterval

    public init(grace: TimeInterval = 3600) {
        self.grace = grace
    }

    /// `true` si ce nonce a déjà servi.
    public func isConsumed(_ nonce: String, at now: Date = Date()) -> Bool {
        purge(at: now)
        return consumed[nonce] != nil
    }

    public func consume(_ nonce: String, expiringAt linkExpiry: Date, at now: Date = Date()) {
        purge(at: now)
        consumed[nonce] = Entry(consumedAt: now,
                                expiresAt: linkExpiry.addingTimeInterval(grace))
    }

    /// Oublie les nonces dont le lien ne peut plus être présenté.
    ///
    /// Sans purge, le registre grandit indéfiniment ; avec une purge trop
    /// agressive, il oublie un nonce encore rejouable.
    private func purge(at now: Date) {
        consumed = consumed.filter { $0.value.expiresAt > now }
    }

    public var count: Int { consumed.count }
}

// MARK: - Défaut fermé

/// Refuse tous les liens signés.
///
/// Le défaut ne renvoie pas `.valid` « en attendant » : un lien accepté sans
/// vérification est exactement ce que ce contrat existe pour empêcher.
public struct ClosedDeepLinkVerifier: DeepLinkVerifying {

    public init() {}

    public func verify(
        _ context: SignedDeepLinkContext, expectedAudience: String
    ) async -> DeepLinkVerdict {
        .unknownIssuer
    }

    public func consume(nonce: String) async {}
}

// MARK: - Ce qu'un lien exige

/// Tous les liens ne se valent pas.
///
/// La distinction n'est pas cosmétique : exiger une signature partout casserait
/// les liens de navigation légitimes (une conversation partagée, un profil), et
/// ne pas l'exiger là où il faut laisse rejouer un paiement.
///
/// La règle : **un lien qui produit un effet exige une preuve ; un lien qui
/// ouvre un écran n'en a pas besoin**, parce que le serveur revérifie de toute
/// façon l'appartenance de ce qu'il affiche.
public enum DeepLinkActionability: Sendable, Equatable {

    /// Ouvre un écran. Au pire, le serveur refuse d'afficher.
    case navigational

    /// Déclenche ou pré-remplit une opération financière. Rejoué, il rejoue
    /// l'effet : signature, audience, expiration et nonce obligatoires.
    case actionable

    /// Décide à partir de l'hôte et du premier segment de chemin.
    ///
    /// **Liste blanche inversée** : ce qui n'est pas explicitement navigationnel
    /// est traité comme actionnable. Un hôte ajouté demain sans toucher à cette
    /// fonction sera donc protégé par défaut, pas exposé par oubli.
    public static func classify(host: String, firstPathComponent: String?) -> DeepLinkActionability {
        switch (host, firstPathComponent) {
        // Navigation pure : ces cibles n'engagent rien.
        case ("chat", "conversation"), ("chat", "inbox"), ("chat", nil):
            return .navigational
        case ("wallet", _), ("ride", _), ("insurance", _):
            return .navigational

        // Lecture d'un objet financier par identifiant opaque. L'URL ne porte
        // aucun montant ; le serveur vérifie l'appartenance à la session.
        // Ouvrir la carte de quelqu'un d'autre est déjà impossible.
        case ("chat", "financial-object"):
            return .navigational

        // Lien de paiement d'une demande (INTEGRATION_CHAT_FINANCE.md Phase 4) :
        // `executable=false`. Il n'ouvre que la demande, relue au serveur par
        // `/payment-link/inspect`, qui valide jeton et nonce. Le paiement exige
        // ensuite devis et confirmation explicite : le lien seul ne déclenche
        // rien. Le traiter en actionnable exigerait une signature que le
        // contrat ne fournit pas — tout lien partagé serait refusé en silence.
        case ("chat", "pay-link"):
            return .navigational

        default:
            return .actionable
        }
    }
}

/// Décide si un lien peut être suivi.
///
/// Point de passage unique : sans lui, chaque site d'ouverture réimplémenterait
/// la vérification, et l'un d'eux finirait par l'oublier.
public actor DeepLinkGate {

    private let verifier: any DeepLinkVerifying
    private let nonces: DeepLinkNonceStore

    public init(verifier: any DeepLinkVerifying, nonces: DeepLinkNonceStore = DeepLinkNonceStore()) {
        self.verifier = verifier
        self.nonces = nonces
    }

    /// Autorise ou refuse l'ouverture.
    ///
    /// - Un lien navigationnel passe sans contexte.
    /// - Un lien actionnable **sans contexte** est refusé : l'absence de preuve
    ///   n'est pas une preuve d'innocence, et c'est exactement la forme qu'aurait
    ///   un lien fabriqué à la main.
    public func evaluate(
        actionability: DeepLinkActionability,
        context: SignedDeepLinkContext?,
        expectedAudience: String,
        at now: Date = Date()
    ) async -> DeepLinkVerdict {

        guard actionability == .actionable else { return .valid }

        guard let context else { return .invalidSignature }

        // L'expiration d'abord : inutile de solliciter le vérificateur pour un
        // lien qu'on sait périmé, et cela ferme la fenêtre côté client.
        if context.hasExpired(at: now) { return .expired }

        // Le rejeu ensuite : un nonce déjà brûlé n'a pas à repartir sur le
        // réseau, où il pourrait être accepté par une réplique en retard.
        if await nonces.isConsumed(context.nonce, at: now) { return .replayed }

        return await verifier.verify(context, expectedAudience: expectedAudience)
    }

    /// Brûle le nonce **après** que l'action a réellement démarré.
    ///
    /// Séparé de `evaluate` : un lien vérifié puis abandonné — l'utilisateur
    /// ferme l'écran — doit rester utilisable, sinon un geste hésitant coûte
    /// définitivement le lien.
    public func commit(_ context: SignedDeepLinkContext) async {
        await nonces.consume(context.nonce, expiringAt: context.expiresAt)
        await verifier.consume(nonce: context.nonce)
    }
}

// MARK: - Extraction depuis l'URL

public extension SignedDeepLinkContext {

    /// Nom du paramètre qui porte le contexte.
    static let queryItemName = "ctx"

    /// Décode le contexte d'une URL, s'il y en a un.
    ///
    /// Le contexte voyage en base64url dans un paramètre de requête plutôt que
    /// dans le chemin : un chemin se tronque, se réécrit par les redirections,
    /// et certains clients de messagerie le « nettoient ». Un paramètre survit
    /// mieux au transport, et sa corruption produit un décodage qui échoue —
    /// donc un refus — plutôt qu'un contexte partiel accepté.
    ///
    /// Rend `nil` sur toute anomalie. **Ne jamais interpréter `nil` comme
    /// « lien de confiance »** : c'est `DeepLinkGate` qui décide, et il refuse
    /// un lien actionnable sans contexte.
    static func extract(from url: URL) -> SignedDeepLinkContext? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == queryItemName })?.value,
              let data = Data(base64URLEncoded: raw)
        else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(SignedDeepLinkContext.self, from: data)
    }
}

extension Data {

    /// Décode du base64url — l'alphabet des URL, sans `+`, `/` ni `=`.
    ///
    /// Le base64 standard échouerait sur un contexte pourtant valide : `+` et
    /// `/` n'ont pas le même sens dans une query string, et les émetteurs
    /// utilisent l'alphabet URL précisément pour cette raison.
    init?(base64URLEncoded string: String) {
        var normalized = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Le remplissage est optionnel en base64url ; il faut le restituer.
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized.append(String(repeating: "=", count: 4 - remainder))
        }
        self.init(base64Encoded: normalized)
    }
}
