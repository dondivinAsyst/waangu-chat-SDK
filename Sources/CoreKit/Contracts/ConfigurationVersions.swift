//
//  ConfigurationVersions.swift
//  CoreKit
//
//  Versions de configuration portées par toute mutation — Bloc 4 §54 (GAP-05).
//

import Foundation

/// Sous quelle configuration une opération a été composée.
///
/// **Le backend ne peut pas deviner ce que le client avait sous les yeux.** Un
/// paiement composé avec un formulaire retiré, un workflow révoqué ou un
/// catalogue périmé doit être refusé — et pour le refuser, il faut savoir
/// lesquels ont servi.
///
/// C'est la règle §54 : `REJECT_STALE_CONFIGURATION`. Sans ces trois valeurs
/// transportées à chaque mutation, un fournisseur suspendu continue de recevoir
/// des opérations composées avant sa suspension.
public struct ConfigurationVersions: Codable, Sendable, Hashable {

    public let catalogVersion: String
    public let workflowVersion: String?
    public let schemaVersion: String

    public init(catalogVersion: String, workflowVersion: String? = nil, schemaVersion: String) {
        self.catalogVersion = catalogVersion
        self.workflowVersion = workflowVersion
        self.schemaVersion = schemaVersion
    }

    /// En-têtes HTTP correspondants.
    ///
    /// Un dictionnaire plutôt que trois champs épars : le site d'appel qui en
    /// oublierait un enverrait une mutation que le backend ne pourrait pas
    /// valider, et le défaut ne se verrait qu'en production.
    public var httpHeaders: [String: String] {
        var headers = [
            "X-Catalog-Version": catalogVersion,
            "X-Schema-Version": schemaVersion
        ]
        if let workflowVersion {
            headers["X-Workflow-Version"] = workflowVersion
        }
        return headers
    }
}

// MARK: - Refus

/// Ce que le backend répond quand la configuration n'est plus autorisée.
public struct StaleConfigurationRejection: Codable, Sendable, Hashable {

    /// Ce qui a été refusé, pour que l'interface dise *quoi* rafraîchir.
    public let staleComponent: ConfigurationComponent

    /// Version exigée. `nil` quand le composant est retiré et non remplacé —
    /// un fournisseur suspendu n'a pas de version « plus récente ».
    public let requiredVersion: String?

    public init(staleComponent: ConfigurationComponent, requiredVersion: String?) {
        self.staleComponent = staleComponent
        self.requiredVersion = requiredVersion
    }
}

public enum ConfigurationComponent: String, Codable, Sendable, CaseIterable {
    case catalog, workflow, schema

    /// Un composant inconnu invalide **tout** : ne sachant pas ce qui est
    /// périmé, la seule réponse sûre est de tout resynchroniser.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConfigurationComponent(rawValue: raw) ?? .catalog
    }
}

public extension StaleConfigurationRejection {

    /// `true` si un simple rafraîchissement suffit à reprendre l'opération.
    ///
    /// Sans version exigée, le composant a été retiré : il n'y a rien à
    /// rafraîchir, et proposer « réessayer » enverrait l'utilisateur en boucle.
    var isRecoverableByRefresh: Bool { requiredVersion != nil }
}
