//
//  RemoteFormProviding.swift
//  CoreKit
//
//  Formulaires distants — Bloc 1, chapitre 7.
//
//  **BACKEND CONTRACT REQUIRED** — définition, validation, soumission.
//

import Foundation

/// Formulaires dont **le backend décide de la forme**.
///
/// Le moteur du Biller Hub fait déjà cela pour les facturiers. Celui-ci le
/// généralise : champs complémentaires d'une commande, collecte réglementaire,
/// question d'un partenaire. Un nouveau formulaire n'exige alors pas une
/// nouvelle version de l'application.
///
/// La validation qui fait foi reste serveur. Ce qui est validé ici sert à ne
/// pas envoyer un formulaire manifestement incomplet — pas à décider qu'il est
/// bon : le client n'a pas les règles, et les inventer refuserait des saisies
/// pourtant valides.
public protocol RemoteFormProviding: Sendable {

    /// Définition d'un formulaire.
    func form(id: String, context: [String: String]) async -> Result<RemoteForm, FinanceError>

    /// Soumet les valeurs saisies.
    func submit(
        formID: String,
        formVersion: String,
        values: [String: String],
        idempotency: IdempotencyContext
    ) async -> Result<RemoteFormOutcome, FinanceError>
}

// MARK: - Le formulaire

public struct RemoteForm: Codable, Sendable, Hashable, Identifiable {

    public let id: String

    /// Version de la définition. Soumise avec les valeurs : sans elle, le
    /// serveur ne peut pas savoir quel formulaire l'utilisateur a réellement
    /// rempli, et une définition modifiée entre l'affichage et l'envoi passerait
    /// inaperçue.
    public let version: String

    public let titleKey: String
    public let descriptionKey: String?
    public let fields: [RemoteFormField]
    public let submitLabelKey: String?

    public init(id: String, version: String, titleKey: String, descriptionKey: String? = nil,
                fields: [RemoteFormField], submitLabelKey: String? = nil) {
        self.id = id
        self.version = version
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.fields = fields
        self.submitLabelKey = submitLabelKey
    }

    /// Les champs requis que ce client **ne sait pas rendre**.
    ///
    /// Non vide ⇒ le formulaire n'est pas soumettable, même si tout le reste
    /// est rempli : un champ requis invisible serait envoyé vide.
    public func unrenderableRequiredFields() -> [RemoteFormField] {
        fields.filter { $0.isRequired && $0.kind == .unsupported }
    }
}

public struct RemoteFormField: Codable, Sendable, Hashable, Identifiable {

    public var id: String { name }
    public let name: String
    public let labelKey: String
    public let placeholderKey: String?
    public let helpKey: String?
    public let kind: RemoteFormFieldKind
    public let isRequired: Bool

    /// Valeurs autorisées pour `.select`. Vide pour les autres types.
    ///
    /// Une liste fermée rendue en saisie libre laisserait taper n'importe quoi
    /// là où le partenaire attend une valeur de la liste — c'est précisément ce
    /// que le champ `select` existe pour empêcher.
    public let options: [RemoteFormOption]

    /// Valeur pré-remplie **par le backend**.
    public let defaultValue: String?

    public init(name: String, labelKey: String, placeholderKey: String? = nil,
                helpKey: String? = nil, kind: RemoteFormFieldKind, isRequired: Bool,
                options: [RemoteFormOption] = [], defaultValue: String? = nil) {
        self.name = name
        self.labelKey = labelKey
        self.placeholderKey = placeholderKey
        self.helpKey = helpKey
        self.kind = kind
        self.isRequired = isRequired
        self.options = options
        self.defaultValue = defaultValue
    }
}

public struct RemoteFormOption: Codable, Sendable, Hashable, Identifiable {
    public var id: String { value }
    public let value: String
    public let labelKey: String

    public init(value: String, labelKey: String) {
        self.value = value
        self.labelKey = labelKey
    }
}

public enum RemoteFormFieldKind: String, Codable, Sendable, CaseIterable {
    case text
    case number
    case phone
    case email
    case date
    case select
    case toggle
    case multilineText

    /// Type que cette version ne sait pas rendre.
    case unsupported

    /// Un type inconnu devient `.unsupported`, **jamais** `.text`.
    ///
    /// Retomber sur du texte libre paraît inoffensif et ne l'est pas : un
    /// sélecteur rendu en saisie libre accepte des valeurs que le partenaire
    /// refusera, et l'erreur n'apparaît qu'après l'envoi.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RemoteFormFieldKind(rawValue: raw.lowercased()) ?? .unsupported
    }
}

// MARK: - Résultat

public struct RemoteFormOutcome: Codable, Sendable, Hashable {

    public let isAccepted: Bool
    public let messageKey: String?

    /// Erreurs par champ, rendues par le serveur. Elles s'affichent sous le
    /// champ concerné plutôt qu'en un bloc : « champ invalide » sans dire lequel
    /// fait relire tout le formulaire.
    public let fieldErrors: [String: String]

    /// Identifiant de l'objet créé, quand la soumission en crée un.
    public let resultID: String?

    public init(isAccepted: Bool, messageKey: String? = nil,
                fieldErrors: [String: String] = [:], resultID: String? = nil) {
        self.isAccepted = isAccepted
        self.messageKey = messageKey
        self.fieldErrors = fieldErrors
        self.resultID = resultID
    }
}

// MARK: - Défaut fermé

/// Ne rend aucun formulaire et n'en soumet aucun.
public struct ClosedRemoteFormProvider: RemoteFormProviding {

    public init() {}

    public func form(id: String, context: [String: String]) async -> Result<RemoteForm, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func submit(formID: String, formVersion: String, values: [String: String],
                       idempotency: IdempotencyContext) async -> Result<RemoteFormOutcome, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
