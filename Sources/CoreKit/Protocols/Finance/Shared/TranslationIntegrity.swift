//
//  TranslationIntegrity.swift
//  CoreKit
//
//  Traduction financière — Bloc 7, chapitre 58.
//
//  **BACKEND CONTRACT REQUIRED** — détection, traduction, sélection de
//  fournisseur, résidence des données.
//

import Foundation

/// Traduit un texte financier **sans en altérer les valeurs**.
///
/// Le §31 en fait deux critères de non-validation : « un montant peut être
/// altéré par traduction » et « un statut machine peut être traduit ». Les deux
/// se produisent silencieusement — `1,000.00 USD` rendu `1.000,00 USD` change le
/// montant d'un facteur mille, et aucune relecture humaine ne le rattrape à
/// l'échelle.
///
/// La défense n'est pas de faire confiance au traducteur. C'est de **retirer les
/// valeurs du texte avant de traduire**, puis de vérifier qu'elles sont toutes
/// revenues intactes.
public protocol FinancialTranslating: Sendable {

    /// Langue détectée, avec sa confiance.
    func detect(_ text: String) async -> Result<LanguageDetection, FinanceError>

    /// Traduit un texte **déjà protégé**.
    ///
    /// Prend un `ProtectedText`, pas une `String` : le type impose que la
    /// protection ait eu lieu. Passer une chaîne brute est impossible, donc
    /// oublier l'étape aussi.
    func translate(
        _ protected: ProtectedText,
        to targetLocale: String,
        glossaryVersion: String?
    ) async -> Result<TranslatedText, FinanceError>
}

// MARK: - Segments protégés (§58.1)

/// Ce qu'un traducteur ne doit jamais voir.
public enum ProtectedSegmentKind: String, Sendable, Hashable, Codable, CaseIterable {
    case amount            = "AMOUNT"
    case currency          = "CURRENCY"
    case reference         = "REFERENCE"
    case identifier        = "IDENTIFIER"
    case token             = "TOKEN"
    case code              = "CODE"
    case voucher           = "VOUCHER"
    /// Date contractuelle — échéance, date de valeur. Une date décalée d'un
    /// jour par un format localisé change une obligation.
    case contractualDate   = "CONTRACTUAL_DATE"
    /// Statut machine. **Jamais traduit** : c'est une valeur, pas une phrase.
    case machineStatus     = "MACHINE_STATUS"
    /// Terme de glossaire marqué « ne pas traduire » — nom de produit, terme
    /// réglementaire dont la version d'origine fait foi. Voir
    /// ``Glossary/protectedSegments(in:)``.
    case glossaryTerm      = "GLOSSARY_TERM"
    case unknown           = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProtectedSegmentKind(rawValue: raw) ?? .unknown
    }
}

/// Une valeur retirée du texte, remplacée par un jeton.
public struct ProtectedSegment: Sendable, Hashable, Codable {

    /// Jeton substitué dans le texte — `⟦W0⟧`, `⟦W1⟧`.
    public let token: String

    /// La valeur d'origine. **Ne quitte jamais l'appareil** avec le texte à
    /// traduire : c'est tout l'objet de la substitution.
    public let originalValue: String

    public let kind: ProtectedSegmentKind

    public init(token: String, originalValue: String, kind: ProtectedSegmentKind) {
        self.token = token
        self.originalValue = originalValue
        self.kind = kind
    }
}

/// Un texte dont les valeurs financières ont été retirées.
///
/// Ne peut pas être construit sans passer par ``ProtectedText/protect(_:segments:)``,
/// ce qui rend l'étape de protection obligatoire par typage plutôt que par
/// discipline.
public struct ProtectedText: Sendable, Hashable, Codable {

    /// Texte avec jetons, prêt à partir chez le traducteur.
    public let maskedText: String

    /// Ce qui a été retiré.
    public let segments: [ProtectedSegment]

    /// Texte d'origine, conservé pour la comparaison finale.
    public let sourceText: String

    private init(maskedText: String, segments: [ProtectedSegment], sourceText: String) {
        self.maskedText = maskedText
        self.segments = segments
        self.sourceText = sourceText
    }

    /// Retire les segments du texte et les remplace par des jetons.
    ///
    /// Les jetons utilisent des crochets mathématiques `⟦ ⟧` plutôt que des
    /// accolades ou des chevrons : ces derniers apparaissent dans du texte
    /// ordinaire et dans du balisage, et un traducteur les réordonne parfois.
    /// Un délimiteur qu'on ne rencontre jamais survit mieux au passage.
    public static func protect(_ text: String, segments raw: [(String, ProtectedSegmentKind)]) -> ProtectedText {
        var masked = text
        var built: [ProtectedSegment] = []

        // Les plus longs d'abord : remplacer « 10 » avant « 10.50 » couperait
        // le second en deux et laisserait « .50 » dans le texte traduit.
        let ordered = raw.enumerated().sorted { $0.element.0.count > $1.element.0.count }

        for (index, entry) in ordered {
            let (value, kind) = entry
            guard masked.contains(value) else { continue }
            let token = "⟦W\(index)⟧"
            masked = masked.replacingOccurrences(of: value, with: token)
            built.append(ProtectedSegment(token: token, originalValue: value, kind: kind))
        }

        return ProtectedText(maskedText: masked, segments: built, sourceText: text)
    }

    /// Le texte reconstitué à partir d'une traduction.
    public func restore(into translated: String) -> String {
        var output = translated
        for segment in segments {
            output = output.replacingOccurrences(of: segment.token, with: segment.originalValue)
        }
        return output
    }
}

/// Un texte traduit, avec sa vérification d'intégrité.
public struct TranslatedText: Sendable, Hashable, Codable {

    public let text: String
    public let targetLocale: String
    public let authority: TranslationAuthority
    public let glossaryVersion: String?
    public let providerID: String?

    public init(text: String, targetLocale: String, authority: TranslationAuthority,
                glossaryVersion: String? = nil, providerID: String? = nil) {
        self.text = text
        self.targetLocale = targetLocale
        self.authority = authority
        self.glossaryVersion = glossaryVersion
        self.providerID = providerID
    }
}

/// D'où vient une traduction (§58.4).
///
/// Un texte juridique officiel ne doit **jamais** être remplacé silencieusement
/// par une traduction automatique : le type oblige à distinguer les trois, et
/// `isBindingQuality` dit lesquelles peuvent porter un engagement.
public enum TranslationAuthority: String, Sendable, Hashable, Codable, CaseIterable {
    case official      = "OFFICIAL"
    case humanReviewed = "HUMAN_REVIEWED"
    case machine       = "MACHINE"

    /// Une autorité inconnue est traitée comme `machine` — la moins engageante.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TranslationAuthority(rawValue: raw) ?? .machine
    }

    /// Peut porter un texte contractuel ou réglementaire.
    public var isBindingQuality: Bool { self == .official }

    /// Doit s'afficher avec une mention indiquant l'origine automatique.
    public var requiresDisclaimer: Bool { self == .machine }
}

// MARK: - Vérification (§58.1)

/// Ce que la vérification d'intégrité constate.
public enum TranslationIntegrityResult: Sendable, Equatable {

    case intact

    /// **Un segment protégé a disparu, changé ou été dupliqué.**
    ///
    /// Le §31.4 en fait un critère de non-validation. Le texte traduit ne doit
    /// pas être affiché : mieux vaut la version d'origine qu'un montant faux.
    case failure(TranslationIntegrityFailure)

    public var isIntact: Bool { self == .intact }
}

public struct TranslationIntegrityFailure: Sendable, Equatable {

    /// Jetons présents à la source, absents de la traduction.
    public let missingTokens: [String]

    /// Jetons apparus en trop — un traducteur qui duplique une phrase
    /// dupliquerait un montant avec elle.
    public let duplicatedTokens: [String]

    /// Segments dont la valeur restituée diffère de l'originale.
    public let alteredValues: [String]

    public init(missingTokens: [String] = [], duplicatedTokens: [String] = [],
                alteredValues: [String] = []) {
        self.missingTokens = missingTokens
        self.duplicatedTokens = duplicatedTokens
        self.alteredValues = alteredValues
    }
}

public extension ProtectedText {

    /// Vérifie qu'aucune valeur protégée n'a bougé.
    ///
    /// Trois contrôles, et chacun attrape une défaillance réelle :
    ///
    /// - **Absent** : le traducteur a supprimé le jeton — le montant disparaît.
    /// - **Dupliqué** : il a répété une phrase — le montant apparaît deux fois.
    /// - **Altéré** : le jeton est là mais la valeur restituée diffère — signe
    ///   que quelqu'un a reconstruit le texte au lieu de le restituer.
    func verifyIntegrity(of translated: String) -> TranslationIntegrityResult {

        var missing: [String] = []
        var duplicated: [String] = []

        for segment in segments {
            let occurrences = translated.components(separatedBy: segment.token).count - 1
            let expected = maskedText.components(separatedBy: segment.token).count - 1

            if occurrences == 0 {
                missing.append(segment.token)
            } else if occurrences > expected {
                duplicated.append(segment.token)
            }
        }

        // La restitution doit rendre exactement les valeurs d'origine.
        let restored = restore(into: translated)
        let altered = segments
            .filter { !restored.contains($0.originalValue) }
            .map(\.originalValue)

        guard missing.isEmpty, duplicated.isEmpty, altered.isEmpty else {
            return .failure(TranslationIntegrityFailure(
                missingTokens: missing, duplicatedTokens: duplicated, alteredValues: altered
            ))
        }
        return .intact
    }
}

// MARK: - Détection

public struct LanguageDetection: Sendable, Hashable, Codable {
    public let locale: String
    /// Confiance, entre 0 et 1. En dessous du seuil, on n'affiche pas de
    /// traduction : proposer « traduire depuis le swahili » sur un texte
    /// français est pire que ne rien proposer.
    public let confidence: Double

    public init(locale: String, confidence: Double) {
        self.locale = locale
        self.confidence = confidence
    }

    public func isReliable(threshold: Double = 0.7) -> Bool { confidence >= threshold }
}

// MARK: - Langues (§58.5)

/// Ce qu'il faut vérifier avant d'activer une langue.
///
/// Une langue partiellement couverte est pire qu'une langue absente :
/// l'utilisateur voit un parcours qui bascule en anglais au moment de
/// confirmer un paiement.
public struct LanguageReadiness: Sendable, Hashable, Codable {

    public let locale: String
    /// Couverture de l'interface, entre 0 et 1.
    public let coverage: Double
    public let glossaryCoverage: Double
    public let translationQuality: Double
    /// Les textes juridiques sont-ils disponibles en version officielle ?
    public let hasLegalCoverage: Bool
    public let qaApproved: Bool

    public init(locale: String, coverage: Double, glossaryCoverage: Double,
                translationQuality: Double, hasLegalCoverage: Bool, qaApproved: Bool) {
        self.locale = locale
        self.coverage = coverage
        self.glossaryCoverage = glossaryCoverage
        self.translationQuality = translationQuality
        self.hasLegalCoverage = hasLegalCoverage
        self.qaApproved = qaApproved
    }

    /// Les cinq conditions du §58.5, toutes nécessaires.
    ///
    /// `hasLegalCoverage` n'est pas négociable : activer une langue sans ses
    /// textes réglementaires ferait accepter des conditions dans une langue que
    /// l'utilisateur ne lit pas.
    public func isActivatable(minimumCoverage: Double = 0.95) -> Bool {
        coverage >= minimumCoverage
            && glossaryCoverage >= minimumCoverage
            && translationQuality >= minimumCoverage
            && hasLegalCoverage
            && qaApproved
    }
}

// MARK: - Défaut fermé

/// Ne traduit rien.
///
/// Le texte d'origine s'affiche tel quel — ce qui est toujours correct, alors
/// qu'une traduction non vérifiée peut être fausse.
public struct ClosedFinancialTranslator: FinancialTranslating {

    public init() {}

    public func detect(_ text: String) async -> Result<LanguageDetection, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func translate(_ protected: ProtectedText, to targetLocale: String,
                          glossaryVersion: String?) async -> Result<TranslatedText, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
