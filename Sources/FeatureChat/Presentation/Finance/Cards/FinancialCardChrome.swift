//
//  FinancialCardChrome.swift
//  FeatureChat
//
//  Habillage commun des cartes financières.

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Cadre partagé par toutes les cartes financières.
///
/// Centralise ce qui ne doit jamais varier d'une carte à l'autre : la manière de
/// présenter un statut, l'aveu d'incertitude, et l'horodatage de dernière lecture.
/// Une carte qui déciderait seule comment afficher `unknown` finirait par le
/// présenter comme un échec.
///
/// **Ne lit jamais `payload.status`.** Le statut brut ignore le verdict de
/// vérification ; le rendu passe exclusivement par `payload.presentation`, qui
/// les combine. Libellés, symboles et tons sont déclarés sur
/// `FinancialCardPresentation`, jamais sur `PaymentStatus` : aucune vue ne peut
/// retrouver un chemin vers l'affichage d'un statut non vérifié.
struct FinancialCardChrome<Content: View>: View {

    let payload: FinancialCardPayload
    let title: String
    @ViewBuilder let content: () -> Content

    private var presentation: FinancialCardPresentation { payload.presentation }

    private var accessibilitySummary: String {
        var parts = [title]
        if !payload.isRepudiated {
            parts.append(payload.formattedAmount)
            if let name = payload.counterpartyName, !name.isEmpty { parts.append(name) }
        }
        parts.append(presentation.label)
        return parts.joined(separator: ", ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Titre et statut passent l'un sous l'autre quand le texte est très
            // grand : côte à côte, le libellé traduit était tronqué.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    presentation.badge
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    presentation.badge
                }
            }

            content()

            // Le signal principal dit déjà « vérification » quand il le faut ;
            // le doubler d'une sous-ligne était précisément ce qui permettait à
            // une coche verte et à « vérification en cours » de coexister.
            // Seule la répudiation mérite une mention supplémentaire : elle dit
            // quelque chose que le bandeau ne dit pas — que le contenu affiché
            // n'est pas celui que le backend a signé.
            if presentation == .repudiated {
                Label(FinanceStrings.cardUnauthenticated, systemImage: "exclamationmark.shield.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.statusDanger)
            }

            // Bandeau de fraîcheur — §7 de la spec. Hors ligne, l'utilisateur doit
            // savoir qu'il regarde un état daté plutôt qu'un état courant.
            if let stamp = payload.freshnessLabel {
                Text(stamp)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(4)
        .frame(maxWidth: 280, alignment: .leading)
        // Plus de fond propre : la carte vit désormais **dans** une bulle, qui
        // porte la couleur. Deux fonds superposés produisaient un encart gris
        // sur la bulle, visible comme un défaut de rendu.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(
                    presentation == .repudiated ? AppColors.statusDanger.opacity(0.6) : Color.clear,
                    lineWidth: 1
                )
        )
        .accessibilityElement(children: .combine)
        // Ordre du chapitre 81 : nature → montant et devise → participant → statut.
        .accessibilityLabel(accessibilitySummary)
    }
}

/// Full-page summary using the same verified presentation as timeline cards.
/// Keep this beside the private presentation mapping instead of copying status rules.
struct FinancialObjectSummary: View {
    let payload: FinancialCardPayload

    var body: some View {
        VStack(spacing: DesignTokens.spacingM) {
            // Sans pastille teintée : l'icône annonce l'état, le texte le dit.
            // Succès prouvé (terminé **et** vérifié) : l'animation « réglé »,
            // une fois. Tout autre état garde son symbole — dont « transmis »
            // et « vérification », qui ne sont pas des succès.
            Group {
                if let animation = payload.presentation.statusAnimation {
                    FinanceStatusAnimation(animation).frame(width: 112, height: 112)
                } else {
                    Image(systemName: payload.presentation.symbol)
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(payload.presentation.toneColor)
                }
            }
            .accessibilityHidden(true)
            Text(payload.presentation.label).font(.title2.bold())
            if !payload.isRepudiated {
                Text(payload.formattedAmount).font(.largeTitle.weight(.semibold)).monospacedDigit()
                if let name = payload.counterpartyName { Text(name).font(.headline) }
            } else {
                Text(FinanceStrings.cardUnauthenticated).font(.subheadline)
            }
            if let freshness = payload.freshnessLabel {
                Text(freshness).font(.footnote).foregroundStyle(AppColors.subtitleGray)
            }
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Présentation du traitement

/// Libellé, symbole et ton — déclarés sur le **traitement**, jamais sur le statut.
///
/// Le traitement a déjà tranché la vérification : un paiement « terminé » mais non
/// vérifié y est `verifying`, pas `settled`. C'est pourquoi le design system est
/// branché ici et nulle part ailleurs.
///
/// Les libellés étaient écrits en français dans le code : un utilisateur
/// anglophone lisait « Effectué » sur chaque carte. Ils passent par
/// `FinanceStrings`, traduits dans les quatre langues livrées.
extension FinancialCardPresentation {

    /// État du design system. Seul `settled` devient `.confirmed`.
    var visualState: FinanceVisualState {
        switch self {
        case .settled:                                  return .confirmed
        case .verifying, .inFlight, .atProvider, .settling,
             .complianceReview, .reconciling, .disputed,
             .refundInProgress:                         return .pending
        case .failed:                                   return .failed
        case .refused, .repudiated:                     return .rejected
        case .cancelled, .expired:                      return .expired
        case .refunded, .partiallyRefunded:             return .refunded
        case .reversed:                                 return .reversed
        }
    }

    var label: String { FinanceStrings.objectStatus(self) }

    var symbol: String {
        switch self {
        case .verifying:                   return "questionmark.circle"
        case .cancelled:                   return "slash.circle"
        case .disputed:                    return "exclamationmark.bubble"
        case .repudiated:                  return "exclamationmark.shield.fill"
        case .refundInProgress:            return "arrow.uturn.backward.circle"
        default:                           return visualState.symbol ?? "circle"
        }
    }

    /// `verifying` reste neutre, délibérément : ni rassurant, ni alarmant. On ne
    /// sait pas, et la couleur ne doit pas trancher à notre place.
    var tone: FinanceColorToken { self == .verifying ? .secondary : visualState.tone }

    var toneColor: Color { tone.color }

    /// L'animation d'en-tête de cet état, `nil` ⇒ le symbole.
    ///
    /// Seules les attentes et le succès prouvé s'animent ; un refus, une
    /// annulation ou un litige gardent leur symbole fixe.
    var statusAnimation: FinanceStatusAnimationKind? {
        switch self {
        case .settled:                                return .settled
        case .inFlight, .atProvider, .settling:       return .submitted
        case .verifying, .reconciling, .complianceReview: return .verifying
        default:                                      return nil
        }
    }

    var badge: TransactionStatusBadge {
        TransactionStatusBadge(state: visualState, label: label, symbol: symbol, tone: tone)
    }
}

// MARK: - Fraîcheur

extension FinancialCardPayload {

    /// Étiquette de dernière mise à jour, ou `nil` quand l'état vient d'être lu.
    ///
    /// Seuil à cinq minutes : en dessous, l'horodatage est du bruit ; au-delà, il
    /// devient l'information qui distingue un état courant d'un état daté.
    var freshnessLabel: String? {
        guard lastRefreshedAt > .distantPast else { return FinanceStrings.objectNeverSynced }
        let age = Date().timeIntervalSince(lastRefreshedAt)
        guard age > 300 else { return nil }

        let time = lastRefreshedAt.formatted(date: .omitted, time: .shortened)
        return String(format: FinanceStrings.objectUpdatedAt, time)
    }

    /// Montant formaté selon la locale, avec son code devise.
    ///
    /// Par le formateur unique du dépôt : deux décimales pour toutes les devises
    /// affichaient « 1 000,5 BIF » — le franc burundais n'en a pas.
    var formattedAmount: String {
        AmountEntry.format(amount, currency)
    }
}
