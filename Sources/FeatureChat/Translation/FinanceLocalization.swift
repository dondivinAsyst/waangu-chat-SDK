//
//  FinanceLocalization.swift
//  FeatureChat
//
//  Pont entre les libellés financiers et TranslationKit.
//

import Foundation
import WaanguCoreKit

/// Résout les libellés financiers par le moteur du projet.
///
/// `FinanceStrings` et cinq vues du dossier `Finance` résolvaient chacune par
/// `NSLocalizedString(bundle: .module)`. Ce module n'embarque **aucun**
/// catalogue `.strings` : chaque appel rendait donc la clé, et les vues la
/// capitalisaient — « Undetermined » s'affichait à la place d'une phrase, dans
/// les quatre langues. Le moteur du projet est TranslationKit ; c'est par lui
/// que tout doit passer.
///
/// Un point d'accès statique plutôt qu'une injection par vue : le service
/// aurait dû traverser trente-neuf écrans pour atteindre les cinq qui en ont
/// besoin, et chaque écran manqué serait resté silencieusement cassé.
public enum FinanceLocalization {

    /// `nonisolated(unsafe)` : écrit une fois au démarrage, lu ensuite. Ce
    /// n'est pas de l'état concurrent, et l'alternative — un acteur — rendrait
    /// asynchrone la lecture d'un libellé dans un `body` de vue.
    nonisolated(unsafe) private static var service: (any TranslationServiceProtocol)?

    /// Branché une fois, à la construction de la surface financière.
    public static func configure(_ translationService: (any TranslationServiceProtocol)?) {
        service = translationService
    }

    /// Le libellé, ou le repli fourni.
    ///
    /// - Parameter key: clé historique, pointée (`finance.hub.title`) ou déjà
    ///   au format TranslationKit (`entry_send_money`). Les deux sont admises :
    ///   normaliser ici évite de réécrire deux cents appels.
    public static func string(_ key: String, fallback: String) -> String {
        guard let service else { return fallback }
        let normalized = normalize(key)
        let value = service.resolve(
            key: normalized, module: FinanceTranslationKeys.MODULE, args: []
        ).value
        return value == normalized ? fallback : value
    }

    // MARK: - Entrées du catalogue

    /// Libellé d'une entrée du hub.
    ///
    /// Deux essais : la clé transportée par le catalogue — le backend décide de
    /// ce qui est proposable — puis une clé dérivée de la **nature** de
    /// l'entrée. La nature est un type fermé, donc toujours traduisible, là où
    /// une `titleKey` est une chaîne libre venue du réseau.
    ///
    /// Ici plutôt que dans chaque vue : le hub et la ligne le résolvaient
    /// séparément, et deux résolutions finissent toujours par diverger.
    public static func entryTitle(_ entry: FinanceCatalogEntry) -> String {
        let byKind = FinanceTranslationKeys.entryKey(for: entry.kind)
        let fallback = string(byKind, fallback: entry.titleKey)
        return string(entry.titleKey, fallback: fallback)
    }

    /// Libellé **court**, pour la rangée d'actions rapides.
    ///
    /// Le kit de référence pose des pastilles de 86 pt, taillées pour « Send »
    /// et « Swap ». Les libellés financiers français — « Envoyer de l'argent »,
    /// « Payer une facture » — n'y tiennent pas et se coupaient en plein mot.
    /// Réduire le corps du texte pour les faire entrer aurait donné quatre
    /// tailles différentes sur une même rangée.
    ///
    /// Un libellé court est donc traduit séparément : c'est un verbe, pas une
    /// troncature.
    public static func entryShortTitle(_ entry: FinanceCatalogEntry) -> String {
        let key = "entry_short_" + entry.kind.rawValue.lowercased()
        return string(key, fallback: entryTitle(entry))
    }

    /// Ce que fait l'entrée, en une ligne.
    ///
    /// Une liste de titres et de chevrons ne dit pas ce qu'on obtient en
    /// tapant : « Cash out » suppose déjà de savoir. La ligne de description est
    /// ce qui distingue un menu d'un index.
    ///
    /// Rend `nil` si la clé n'existe pas, pour qu'une entrée sans description
    /// s'affiche sur une seule ligne plutôt qu'avec un blanc réservé.
    public static func entryDescription(_ entry: FinanceCatalogEntry) -> String? {
        let key = "entry_desc_" + entry.kind.rawValue.lowercased()
        let resolved = string(key, fallback: "")
        return resolved.isEmpty ? nil : resolved
    }

    /// Motif d'indisponibilité, même chaîne de résolution.
    public static func entryReason(_ key: String) -> String {
        string(key, fallback: string(FinanceTranslationKeys.ENTRY_UNAVAILABLE, fallback: key))
    }

    /// `finance.recipient.title` → `recipient_title`.
    ///
    /// Le préfixe `finance.` est redondant : le module l'exprime déjà.
    static func normalize(_ key: String) -> String {
        var k = key
        if k.hasPrefix("finance.") { k.removeFirst("finance.".count) }
        return k.replacingOccurrences(of: ".", with: "_")
    }
}
