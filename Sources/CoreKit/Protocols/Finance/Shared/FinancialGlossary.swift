//
//  FinancialGlossary.swift
//  CoreKit
//
//  Glossaire financier versionné — Bloc 7, §31.18 et §58.
//
//  **BACKEND CONTRACT REQUIRED** — le glossaire est servi et versionné par le
//  backend. Ce fichier n'en décrit que la forme et la vérification.
//

import Foundation

/// Ce qu'une politique dit d'un terme.
///
/// `FinanceTranslationKeys.swift` centralise déjà la terminologie et le CI
/// vérifie qu'aucune vue n'écrit de littéral — c'est un acquis réel. Mais c'est
/// un fichier de chaînes : il dit **ce qu'on affiche**, pas **ce qu'on n'a pas
/// le droit d'écrire**. Un terme interdit qui entre par une traduction, par un
/// texte fournisseur ou par une réponse du Copilot n'y est pas visible.
public enum GlossaryPolicy: String, Sendable, Hashable, Codable, CaseIterable {

    /// Le terme canonique est le seul admis pour ce concept. Toute variante
    /// détectée est une violation, corrigeable automatiquement.
    case required        = "REQUIRED"

    /// Le terme canonique est préférable ; une variante est signalée sans
    /// bloquer.
    case preferred       = "PREFERRED"

    /// Aucun contrôle. Présent au glossaire pour la documentation.
    case allowed         = "ALLOWED"

    /// À éviter. Bloque dans un parcours critique, avertit ailleurs.
    case discouraged     = "DISCOURAGED"

    /// **Interdit partout.** C'est le cas que le §31.18 rend non négociable :
    /// promesse de rendement, garantie d'agrément, formulation qui laisse
    /// croire à une couverture qui n'existe pas.
    case forbidden       = "FORBIDDEN"

    /// Ne doit jamais être traduit — nom de produit, terme réglementaire dont
    /// la version française fait foi. Se protège comme un montant : voir
    /// ``Glossary/protectedSegments(in:)``.
    case doNotTranslate  = "DO_NOT_TRANSLATE"

    /// Politique inconnue de ce client.
    ///
    /// Un backend qui ajoute une politique ne doit pas la voir silencieusement
    /// dégradée en `allowed` : un terme nouvellement interdit passerait sans
    /// bruit sur toutes les versions déjà installées. Traitée comme
    /// `discouraged` — bloquante en parcours critique, signalée ailleurs.
    case unrecognized    = "UNRECOGNIZED"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GlossaryPolicy(rawValue: raw) ?? .unrecognized
    }

    /// Ce qu'une occurrence vaut quand elle est trouvée.
    public var severity: GlossaryFindingSeverity {
        switch self {
        case .forbidden:                        return .blocking
        case .required:                         return .correctable
        case .discouraged, .unrecognized:       return .contextual
        case .preferred, .doNotTranslate:       return .advisory
        case .allowed:                          return .advisory
        }
    }

    /// Le terme canonique lui-même doit-il être cherché ?
    ///
    /// Pour `required` et `preferred`, non : c'est la forme *correcte*. Seules
    /// ses variantes constituent une occurrence à signaler.
    var matchesCanonicalForm: Bool {
        switch self {
        case .forbidden, .discouraged, .doNotTranslate, .unrecognized: return true
        case .required, .preferred, .allowed:                          return false
        }
    }

    var isChecked: Bool { self != .allowed }
}

/// La gravité d'une occurrence, indépendamment du parcours.
public enum GlossaryFindingSeverity: String, Sendable, Hashable, Codable, CaseIterable {

    /// Bloque partout.
    case blocking    = "BLOCKING"

    /// Bloque, mais la correction est mécanique : remplacer par la forme
    /// canonique.
    case correctable = "CORRECTABLE"

    /// Bloque en parcours critique seulement.
    case contextual  = "CONTEXTUAL"

    /// Signalé, jamais bloquant.
    case advisory    = "ADVISORY"

    public func blocks(in journey: GlossaryJourney) -> Bool {
        switch self {
        case .blocking, .correctable: return true
        case .contextual:             return journey.isCritical
        case .advisory:               return false
        }
    }
}

// MARK: - Parcours (§31.18)

/// Où le texte est affiché.
///
/// Le §31.18 ne parle pas d'un terme interdit dans l'absolu, mais d'un terme
/// interdit **dans un parcours critique**. La distinction porte tout le
/// dimensionnement : appliquer la sévérité maximale partout ferait échouer le
/// linter sur des textes marketing, et l'équipe le désactiverait.
public enum GlossaryJourney: String, Sendable, Hashable, Codable, CaseIterable {

    // Critiques — l'utilisateur engage de l'argent ou du consentement.
    case confirmation = "CONFIRMATION"
    case legal        = "LEGAL"
    case onboarding   = "ONBOARDING"
    case dispute      = "DISPUTE"
    case statement    = "STATEMENT"

    // Ordinaires.
    case assistance   = "ASSISTANCE"
    case notification = "NOTIFICATION"
    case marketing    = "MARKETING"
    case discovery    = "DISCOVERY"

    case unknown      = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = GlossaryJourney(rawValue: raw) ?? .unknown
    }

    /// Un parcours inconnu est traité comme critique.
    ///
    /// L'inverse laisserait une nouvelle surface d'affichage échapper au
    /// contrôle par simple omission.
    public var isCritical: Bool {
        switch self {
        case .confirmation, .legal, .onboarding, .dispute, .statement, .unknown:
            return true
        case .assistance, .notification, .marketing, .discovery:
            return false
        }
    }
}

// MARK: - Termes

/// Une entrée du glossaire.
public struct GlossaryTerm: Sendable, Hashable, Codable, Identifiable {

    public let id: String

    /// La forme canonique.
    public let term: String

    /// Langue de l'entrée — un glossaire est par langue.
    public let locale: String

    public let policy: GlossaryPolicy

    /// Ce qu'il faut écrire à la place. Renseigné pour `required` et
    /// `forbidden` : une interdiction sans alternative se contourne mal.
    public let replacement: String?

    /// Autres formes détectables — flexions, synonymes, abréviations,
    /// orthographes accentuées ou non.
    ///
    /// La détection est insensible à la casse mais **pas** aux diacritiques :
    /// « intérêt » et « interet » sont deux entrées à lister, parce que replier
    /// les accents déplacerait les positions et rendrait le report faux.
    public let variants: [String]

    /// Parcours concernés. `nil` vaut « tous ».
    public let journeys: Set<GlossaryJourney>?

    /// Clé de message expliquant l'interdiction, pour l'outillage.
    public let reasonKey: String?

    public let note: String?

    public init(id: String, term: String, locale: String, policy: GlossaryPolicy,
                replacement: String? = nil, variants: [String] = [],
                journeys: Set<GlossaryJourney>? = nil,
                reasonKey: String? = nil, note: String? = nil) {
        self.id = id
        self.term = term
        self.locale = locale
        self.policy = policy
        self.replacement = replacement
        self.variants = variants
        self.journeys = journeys
        self.reasonKey = reasonKey
        self.note = note
    }

    /// S'applique-t-il à ce parcours ?
    public func applies(to journey: GlossaryJourney) -> Bool {
        guard let journeys else { return true }
        return journeys.contains(journey)
    }

    /// Les formes à chercher dans le texte, selon la politique.
    var searchableForms: [String] {
        policy.matchesCanonicalForm ? [term] + variants : variants
    }
}

/// Un glossaire versionné, pour une langue.
///
/// La version compte autant que le contenu : une traduction produite sous la
/// version 4 n'est pas revalidée par la version 7, et ``TranslatedText`` porte
/// `glossaryVersion` exactement pour permettre ce rapprochement.
public struct Glossary: Sendable, Hashable, Codable {

    public let version: String
    public let locale: String
    public let terms: [GlossaryTerm]

    public init(version: String, locale: String, terms: [GlossaryTerm]) {
        self.version = version
        self.locale = locale
        self.terms = terms
    }

    public func terms(for journey: GlossaryJourney) -> [GlossaryTerm] {
        terms.filter { $0.policy.isChecked && $0.applies(to: journey) }
    }

    /// Les termes à ne jamais traduire, sous la forme attendue par
    /// ``ProtectedText/protect(_:segments:)``.
    ///
    /// C'est la jonction avec l'étape précédente : un terme `doNotTranslate`
    /// se défend exactement comme un montant — en le retirant du texte avant
    /// qu'un traducteur le voie, plutôt qu'en vérifiant après coup qu'il est
    /// resté intact.
    public func protectedSegments(in text: String) -> [(String, ProtectedSegmentKind)] {
        terms
            .filter { $0.policy == .doNotTranslate }
            .flatMap { term in ([term.term] + term.variants) }
            .filter { text.contains($0) }
            .map { ($0, ProtectedSegmentKind.glossaryTerm) }
    }
}

// MARK: - Résultat du linter

public struct GlossaryFinding: Sendable, Hashable {

    public let termID: String

    /// La forme effectivement rencontrée — pas la forme canonique.
    public let matched: String

    public let policy: GlossaryPolicy
    public let severity: GlossaryFindingSeverity
    public let replacement: String?
    public let occurrences: Int
    public let reasonKey: String?

    public init(termID: String, matched: String, policy: GlossaryPolicy,
                severity: GlossaryFindingSeverity, replacement: String?,
                occurrences: Int, reasonKey: String?) {
        self.termID = termID
        self.matched = matched
        self.policy = policy
        self.severity = severity
        self.replacement = replacement
        self.occurrences = occurrences
        self.reasonKey = reasonKey
    }
}

/// Ce que le linter conclut.
public enum GlossaryLintResult: Sendable, Equatable {

    case clean

    case findings([GlossaryFinding])

    /// Aucun glossaire n'a pu être chargé.
    ///
    /// **N'est pas `clean`.** Même asymétrie que ``PromptScreeningVerdict``: un
    /// contrôle absent ne valide rien. En parcours critique on refuse
    /// d'afficher ; ailleurs, bloquer tout texte parce qu'un fichier de
    /// terminologie n'a pas été téléchargé serait disproportionné.
    case unavailable

    public var findings: [GlossaryFinding] {
        if case .findings(let list) = self { return list }
        return []
    }

    /// Le texte peut-il être affiché dans ce parcours ?
    public func permitsDisplay(in journey: GlossaryJourney) -> Bool {
        switch self {
        case .clean:
            return true
        case .unavailable:
            return !journey.isCritical
        case .findings(let list):
            return !list.contains { $0.severity.blocks(in: journey) }
        }
    }

    /// Les occurrences qui bloquent réellement, pour le message d'erreur.
    public func blockingFindings(in journey: GlossaryJourney) -> [GlossaryFinding] {
        findings.filter { $0.severity.blocks(in: journey) }
    }
}

// MARK: - Linter (§31.18)

/// Cherche les termes du glossaire dans un texte.
///
/// Volontairement synchrone et sans dépendance : il tourne aussi bien dans un
/// test, dans un script de CI que devant l'affichage d'une réponse du Copilot.
public struct GlossaryLinter: Sendable {

    private let glossary: Glossary

    public init(glossary: Glossary) {
        self.glossary = glossary
    }

    /// Analyse un texte brut.
    public func lint(_ text: String, journey: GlossaryJourney) -> GlossaryLintResult {

        guard !text.isEmpty else { return .clean }

        var found: [GlossaryFinding] = []

        for term in glossary.terms(for: journey) {
            for form in term.searchableForms {
                let count = Self.occurrences(of: form, in: text)
                guard count > 0 else { continue }
                found.append(GlossaryFinding(
                    termID: term.id,
                    matched: form,
                    policy: term.policy,
                    severity: term.policy.severity,
                    replacement: term.replacement ?? (term.policy.matchesCanonicalForm ? nil : term.term),
                    occurrences: count,
                    reasonKey: term.reasonKey
                ))
            }
        }

        return found.isEmpty ? .clean : .findings(found)
    }

    /// Analyse un texte dont les valeurs financières ont déjà été retirées.
    ///
    /// C'est la forme à préférer sur un texte destiné à la traduction. Analyser
    /// le texte masqué évite le faux positif le plus courant : une référence de
    /// transaction ou un identifiant qui contient par hasard la séquence d'un
    /// terme surveillé. Ces valeurs ne sont pas de la langue, et n'ont rien à
    /// faire dans un contrôle terminologique.
    public func lint(_ protected: ProtectedText, journey: GlossaryJourney) -> GlossaryLintResult {
        lint(protected.maskedText, journey: journey)
    }

    /// Compte les occurrences d'une forme, en mot entier et sans tenir compte
    /// de la casse.
    ///
    /// Le mot entier est indispensable : sans lui, « prêt » signalerait
    /// « prêteur » et « emprunt », et le linter deviendrait inutilisable.
    static func occurrences(of form: String, in text: String) -> Int {

        let trimmed = form.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }

        let escaped = NSRegularExpression.escapedPattern(for: trimmed)

        // `\b` ne s'accroche qu'à un caractère de mot. Une forme qui commence
        // ou finit par une ponctuation — « % net », « garanti ! » — n'en a pas
        // à cet endroit, et exiger la frontière ne trouverait jamais rien.
        let leading  = trimmed.first.map(Self.isWordCharacter)  == true ? "\\b" : ""
        let trailing = trimmed.last.map(Self.isWordCharacter)   == true ? "\\b" : ""

        guard let regex = try? NSRegularExpression(
            pattern: leading + escaped + trailing,
            options: [.caseInsensitive]
        ) else { return 0 }

        return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}

// MARK: - Fourniture

/// Sert le glossaire de la langue demandée.
public protocol FinancialGlossaryProviding: Sendable {

    /// Le glossaire actif pour une langue.
    func glossary(for locale: String) async -> Result<Glossary, FinanceError>

    /// Le glossaire dans une version précise, pour revérifier un texte produit
    /// sous une version antérieure.
    func glossary(for locale: String, version: String) async -> Result<Glossary, FinanceError>
}

// MARK: - Défaut fermé

/// Ne connaît aucun terme, et le dit.
///
/// Rend `capabilityUnavailable` plutôt qu'un glossaire vide : un glossaire vide
/// répondrait `clean` à tout, ce qui est exactement l'angle mort que le §31.18
/// décrit. L'appelant reçoit ``GlossaryLintResult/unavailable`` et en tire la
/// conséquence selon le parcours.
public struct ClosedGlossaryProvider: FinancialGlossaryProviding {

    public init() {}

    public func glossary(for locale: String) async -> Result<Glossary, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func glossary(for locale: String, version: String) async -> Result<Glossary, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
