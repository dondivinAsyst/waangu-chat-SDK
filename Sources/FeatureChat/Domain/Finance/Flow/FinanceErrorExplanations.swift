//
//  FinanceErrorExplanations.swift
//  FeatureChat
//
//  Ce qu'il faut dire à l'utilisateur d'un échec, gardé à côté de sa décision.
//

import Foundation
import WaanguCoreKit

/// L'explication d'un échec, pour l'affichage uniquement.
///
/// **Pourquoi à côté, et pas dans l'erreur.** Tous les contrats rendent
/// `Result<…, FinanceError>`, et c'est sur `FinanceError` que la logique
/// décide : renouveler un devis sur `.expired`, ne jamais réexécuter sur
/// `.timeoutUnknown`. Y ajouter du texte changerait chacun de ces tests — au
/// cœur du chemin de paiement. L'explication voyage donc ici, et **n'est lue
/// que par l'affichage** : aucune décision n'en dépend.
///
/// Deux sources :
/// - le **serveur**, qui rédige un message avec son code `CF_xxx` ;
/// - l'**app**, quand elle refuse avant tout appel et sait pourquoi — session à
///   revalider, pays fermé, droit de confirmation absent.
///
/// Une explication est attachée à la dernière erreur de même nature et expire
/// vite : elle répond à l'échec qui vient d'arriver, pas à un échec semblable
/// plus tard.
final class FinanceErrorExplanations: @unchecked Sendable {

    enum Explanation: Equatable, Sendable {
        /// Rédigé par le serveur, déjà dans la langue envoyée en `Accept-Language`.
        case server(String)
        /// Refus décidé par l'app ; l'affichage le traduit.
        case refusal(FinanceWriteRefusal)
    }

    static let shared = FinanceErrorExplanations()

    /// Au-delà, l'explication n'est plus celle de l'échec affiché.
    static let lifetime: TimeInterval = 30
    /// Longueur maximale d'un message serveur : ce n'est pas une page.
    static let maxLength = 240
    private static let capacity = 16

    private struct Entry {
        let error: FinanceError
        let explanation: Explanation
        let recordedAt: Date
    }

    private let lock = NSLock()
    private var entries: [Entry] = []
    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = Date.init) {
        self.now = now
    }

    // MARK: - Enregistrer

    /// Garde le message du serveur pour cette erreur. Un message vide, qui ne
    /// fait que répéter un code, ou qui accompagne un doute est ignoré.
    func record(serverMessage message: String?, for error: FinanceError) {
        guard let text = Self.sanitized(message) else { return }
        store(.server(text), for: error)
    }

    /// Refus décidé par l'app : garde la raison, et rend l'erreur à renvoyer.
    ///
    /// Une seule écriture aux trois portes — préparer, exécuter, retirer — pour
    /// que la raison ne puisse pas être oubliée à l'une d'elles.
    func refuse(_ refusal: FinanceWriteRefusal) -> FinanceError {
        let error = FinanceError.capabilityUnavailable
        store(.refusal(refusal), for: error)
        return error
    }

    // MARK: - Lire

    /// L'explication de cette erreur, si elle est encore fraîche.
    func explanation(for error: FinanceError) -> Explanation? {
        guard Self.acceptsExplanation(for: error) else { return nil }
        lock.lock(); defer { lock.unlock() }
        let cutoff = now().addingTimeInterval(-Self.lifetime)
        entries.removeAll { $0.recordedAt < cutoff }
        return entries.last { $0.error == error }?.explanation
    }

    /// Déconnexion, changement de compte : les explications du précédent disparaissent.
    func clear() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }

    // MARK: - Règles

    private func store(_ explanation: Explanation, for error: FinanceError) {
        guard Self.acceptsExplanation(for: error) else { return }
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.error == error }
        entries.append(Entry(error: error, explanation: explanation, recordedAt: now()))
        if entries.count > Self.capacity { entries.removeFirst(entries.count - Self.capacity) }
    }

    /// Une issue incertaine garde **notre** phrase : « nous vérifions, ne
    /// relancez pas ». Un texte disant « échec » inviterait à payer deux fois.
    static func acceptsExplanation(for error: FinanceError) -> Bool {
        error != .timeoutUnknown
    }

    /// Texte serveur affichable, ou `nil`. Espaces resserrés, longueur bornée ;
    /// un message vide ou réduit à un code (`CF_029`) n'apprend rien.
    static func sanitized(_ message: String?) -> String? {
        guard let message else { return nil }
        let collapsed = message
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty,
              collapsed.range(of: #"^CF_\d+$"#, options: .regularExpression) == nil else { return nil }
        guard collapsed.count > maxLength else { return collapsed }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
