//
//  FinancialOutcomeRoute.swift
//  FeatureChat
//
//  Ce que l'écran a le droit de montrer après une soumission — Bloc 10, §78 et §80.
//

import Foundation
import WaanguCoreKit

/// L'issue d'une soumission, telle qu'un écran peut la présenter.
///
/// **Une décision, pas un affichage.** Chaque parcours traduisait lui-même
/// l'issue de son cas d'usage en étape d'écran, et l'envoi d'argent traduisait
/// `timeoutUnknown` en `.failed` : l'utilisateur voyait une page d'échec, le
/// transfert ambigu n'entrait dans aucun magasin, et le planificateur de
/// réconciliation — qui ne balaie que le magasin — ne le reprenait jamais.
///
/// Extraite ici pour que la règle soit **testable sans vue** et identique pour
/// tous les parcours qui soumettent de l'argent.
public enum FinancialOutcomeRoute: Equatable, Sendable {

    /// Soumis. Référence connue ; l'état réel se lit dans le magasin.
    case submitted(FinancialReference)

    /// Issue inconnue. **Jamais un échec** : l'argent est peut-être parti.
    ///
    /// L'écran doit afficher une vérification en cours, et l'objet doit être
    /// inscrit comme ambigu pour que la réconciliation le reprenne.
    case verifying(FinancialReference)

    /// Les conditions ont changé ; nouveau consentement requis.
    case needsNewAgreement

    /// Échec établi. Rien n'a été débité, ou le backend l'a refusé explicitement.
    case failed(FinanceError)
}

public extension FinancialOutcomeRoute {

    /// Erreurs dont l'issue financière est **inconnue** après soumission.
    ///
    /// Ce sont les seules pour lesquelles l'argent a pu partir sans que le client
    /// le sache. Elles ne deviennent jamais `failed` : un échec affiché invite à
    /// repayer, et un second paiement sur une opération déjà exécutée est le
    /// pire résultat possible.
    ///
    /// `networkUnavailable` en fait partie **après** soumission : la requête a pu
    /// atteindre le serveur avant la coupure. `providerUnavailable` aussi : le
    /// fournisseur peut avoir exécuté puis cessé de répondre.
    static func isFinalityUnknown(_ error: FinanceError) -> Bool {
        switch error {
        case .timeoutUnknown, .networkUnavailable, .providerUnavailable:
            return true
        case .server(let statusCode):
            // 5xx après soumission : le serveur a pu exécuter avant de tomber.
            // 4xx : refus établi, rien n'est parti.
            return (statusCode ?? 500) >= 500
        default:
            return false
        }
    }

    /// Route l'issue d'une soumission d'envoi.
    ///
    /// - Parameter submittedReference: la référence de l'objet soumis. Sans elle,
    ///   une issue inconnue ne peut pas être réconciliée ; elle reste alors un
    ///   échec **affiché sans invitation à repayer** — c'est le message de
    ///   l'erreur qui porte cette consigne.
    static func route(_ outcome: SendMoneyUseCase.Outcome,
                      submittedReference: FinancialReference?) -> FinancialOutcomeRoute {
        switch outcome {
        case .executed(let reference):
            return .submitted(reference)
        case .needsNewAgreement:
            return .needsNewAgreement
        case .refused(let error):
            // Le serveur a répondu et refusé : aucune ambiguïté à lever, donc
            // aucune carte à publier ni objet à réconcilier. C'est ce qui
            // laissait une carte « issue inconnue » dans la conversation pour
            // un paiement que le serveur venait d'écarter.
            return .failed(error)
        case .failed(let error):
            if isFinalityUnknown(error), let submittedReference {
                return .verifying(submittedReference)
            }
            return .failed(error)
        }
    }

    /// L'objet provisoire à inscrire pour une issue inconnue.
    ///
    /// Statut `unknown` et vérification `unverified` : les deux font entrer
    /// l'objet dans `pendingReconciliation()`, que le planificateur balaie au
    /// retour du réseau, au retour au premier plan et toutes les minutes. La
    /// carte, elle, présente l'incertitude — elle ne dit ni envoyé, ni échoué.
    static func ambiguousPayload(reference: FinancialReference,
                                 amount: Decimal,
                                 currency: String,
                                 counterpartyName: String?) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: reference,
            status: .unknown,
            amount: amount,
            currency: currency,
            counterpartyName: counterpartyName,
            verification: .unverified
        )
    }
}
