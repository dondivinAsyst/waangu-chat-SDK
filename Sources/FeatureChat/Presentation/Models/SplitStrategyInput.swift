//
//  SplitStrategyInput.swift
//  FeatureChat
//
//  La saisie d'une répartition, avant qu'elle devienne une stratégie.
//

import Foundation
import WaanguCoreKit

/// Ce que l'organisateur a saisi pour répartir un partage.
///
/// Garde le **texte** tapé pour chaque participant et ne le convertit qu'à la
/// demande : un champ en cours d'édition — « 12, » — n'est pas encore un nombre,
/// et le convertir à chaque frappe effacerait la virgule sous le doigt.
///
/// Ne calcule aucune part. La stratégie est déclarée ; le backend répartit.
struct SplitStrategyInput: Equatable {

    enum Kind: String, CaseIterable, Identifiable {
        case equal, custom, proportional
        var id: String { rawValue }
    }

    var kind: Kind = .equal
    /// Texte saisi par identifiant de participant — montant ou poids selon `kind`.
    var values: [String: String] = [:]

    /// La stratégie à soumettre, ou `nil` si la saisie n'en forme pas encore une.
    ///
    /// Seuls les participants **encore choisis** comptent : une valeur laissée
    /// par quelqu'un qu'on a retiré ne doit pas voyager dans la demande.
    func strategy(for participantIDs: [String]) -> SplitStrategy? {
        switch kind {
        case .equal:
            return .equal
        case .custom, .proportional:
            var parsed: [String: Decimal] = [:]
            for id in participantIDs {
                guard let value = Self.decimal(values[id]), value > 0 else { return nil }
                parsed[id] = value
            }
            guard !parsed.isEmpty else { return nil }
            return kind == .custom ? .custom(parsed) : .proportional(parsed)
        }
    }

    /// Somme des montants saisis, pour **signaler** un écart au total.
    ///
    /// `nil` hors montants personnalisés : une somme de poids n'a pas à égaler
    /// le total. N'est jamais un montant à débiter.
    func customSum(for participantIDs: [String]) -> Decimal? {
        guard kind == .custom else { return nil }
        let amounts = participantIDs.compactMap { Self.decimal(values[$0]) }
        return amounts.isEmpty ? nil : amounts.reduce(0, +)
    }

    /// Accepte la virgule comme séparateur : c'est celui du clavier en français.
    static func decimal(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        let normalized = text
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }
}
