//
//  SecurityRisk.swift
//  CoreKit
//
//  Bloc 9, chapitre 70 — registre de risques exploitable.
//

import Foundation

/// Gravité d'un risque, dérivée et non saisie.
public enum RiskSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"

    private var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        case .critical: return 3
        }
    }

    public static func < (lhs: RiskSeverity, rhs: RiskSeverity) -> Bool {
        lhs.rank < rhs.rank
    }

    /// Matrice vraisemblance × impact, sur 1–5 chacun.
    ///
    /// Dérivée plutôt que saisie : une gravité choisie à la main dérive de la
    /// matrice dès le deuxième relecteur, et le registre cesse d'être comparable.
    public init(likelihood: Int, impact: Int) {
        switch likelihood * impact {
        case 20...:  self = .critical
        case 12..<20: self = .high
        case 6..<12:  self = .medium
        default:      self = .low
        }
    }
}

/// Un risque identifié, avec son chemin d'attaque et son propriétaire.
public struct SecurityRisk: Codable, Sendable, Identifiable, Equatable {

    public let id: String
    public let chapter: Int
    public let asset: String
    public let threat: String

    /// Chaîne d'exploitation, en clair. Un risque sans chemin d'attaque n'est
    /// pas actionnable : on ne sait ni le reproduire ni vérifier qu'il est clos.
    public let attackPath: String

    /// 1–5.
    public let likelihood: Int
    public let impact: Int

    /// Dérivée de la matrice.
    public var severity: RiskSeverity { RiskSeverity(likelihood: likelihood, impact: impact) }

    /// Équipe responsable — MOBILE, BACKEND, SECURITY PLATFORM, COMPLIANCE, DEVOPS.
    public let owner: String

    /// Contrôles en place, par identifiant.
    public let controls: [String]

    /// 1–5. **Non dérivé** : le résiduel dépend de l'efficacité réelle des
    /// contrôles, qui s'évalue, elle ne se calcule pas.
    public let residualRisk: Int

    public let dueDate: Date?

    /// `true` quand le risque est accepté formellement plutôt que corrigé.
    public let isAccepted: Bool

    public init(
        id: String, chapter: Int, asset: String, threat: String, attackPath: String,
        likelihood: Int, impact: Int, owner: String, controls: [String] = [],
        residualRisk: Int, dueDate: Date? = nil, isAccepted: Bool = false
    ) {
        self.id = id
        self.chapter = chapter
        self.asset = asset
        self.threat = threat
        self.attackPath = attackPath
        self.likelihood = min(max(likelihood, 1), 5)
        self.impact = min(max(impact, 1), 5)
        self.owner = owner
        self.controls = controls
        self.residualRisk = min(max(residualRisk, 1), 5)
        self.dueDate = dueDate
        self.isAccepted = isAccepted
    }
}

// MARK: - Registre

/// Le registre du §8, interrogeable et exportable.
public struct SecurityRiskRegister: Sendable {

    public let risks: [SecurityRisk]

    public init(risks: [SecurityRisk]) { self.risks = risks }

    /// Risques qui bloquent une mise en production.
    ///
    /// Le filtre porte sur le **risque résiduel**, pas sur la gravité inhérente.
    /// La distinction s'est révélée à l'usage : le masquage d'écran a une
    /// gravité inhérente haute — l'instantané système est facile à obtenir — et
    /// un contrôle livré qui la ramène à 1. Filtrer sur l'inhérent le laissait
    /// bloquant pour toujours, ce qui revenait à ne jamais créditer un contrôle
    /// qui marche, et donc à rendre la liste des bloquants inutile.
    ///
    /// Seuil à 4 : c'est le niveau où le contrôle en place ne suffit pas.
    /// L'acceptation formelle lève le blocage — c'est ce qui distingue un risque
    /// assumé d'un risque oublié, comme l'exige le §34.
    public var blocking: [SecurityRisk] {
        risks.filter { $0.residualRisk >= 4 && !$0.isAccepted }
    }

    /// Répartition par gravité, pour la matrice.
    public var distribution: [RiskSeverity: Int] {
        Dictionary(grouping: risks, by: \.severity).mapValues(\.count)
    }

    /// Risques dont l'échéance est dépassée.
    public func overdue(asOf now: Date = Date()) -> [SecurityRisk] {
        risks.filter { risk in
            guard let due = risk.dueDate, !risk.isAccepted else { return false }
            return due < now
        }
    }

    /// Export CSV, pour la revue de sécurité.
    ///
    /// Le §8 demande un export automatisable ; un registre qui ne sort pas de
    /// l'application ne sert qu'à ceux qui lisent le code.
    public func exportCSV() -> String {
        let header = "id,chapter,asset,threat,likelihood,impact,severity,owner,residual,accepted"
        let rows = risks.map { r in
            [
                r.id, String(r.chapter), Self.escape(r.asset), Self.escape(r.threat),
                String(r.likelihood), String(r.impact), r.severity.rawValue,
                r.owner, String(r.residualRisk), r.isAccepted ? "yes" : "no"
            ].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n")
    }

    /// Échappe une valeur CSV. Sans cela, une virgule dans une description
    /// décale toutes les colonnes suivantes — et le tableau ment sans erreur.
    private static func escape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
