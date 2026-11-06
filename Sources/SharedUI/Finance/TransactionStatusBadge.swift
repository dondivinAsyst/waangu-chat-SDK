//
//  TransactionStatusBadge.swift
//  SharedUI
//
//  Bloc 10, chapitres 79 et 81 — un statut financier se lit en texte, icône et
//  couleur, jamais par la couleur seule.
//

import SwiftUI

/// Jetons de couleur du design system financier.
///
/// Chaque jeton se résout par `AppColors` : aucune couleur n'est déclarée ici,
/// pour qu'un changement de palette — ou de mode sombre — passe par un seul fichier.
public enum FinanceColorToken: CaseIterable, Sendable {
    case primary
    case secondary
    case success
    case warning
    case danger
    case pending
    case blocked
    case surface
    case elevatedSurface

    public var color: Color {
        switch self {
        case .primary:         return AppColors.primary
        case .secondary:       return AppColors.statusNeutral
        case .success:         return AppColors.statusSuccess
        case .warning:         return AppColors.statusWarning
        case .danger:          return AppColors.statusDanger
        case .pending:         return AppColors.statusWarning
        case .blocked:         return AppColors.statusDanger
        case .surface:         return AppColors.walletCanvas
        case .elevatedSurface: return AppColors.cardBackground
        }
    }
}

/// Les états visuels que tout composant financier sait représenter.
///
/// Ce n'est **pas** un statut de paiement : un paiement « terminé » mais non
/// vérifié ne doit jamais devenir `.confirmed`. La correspondance se fait dans la
/// feature, à partir du traitement d'affichage qui a déjà tranché la vérification.
public enum FinanceVisualState: String, CaseIterable, Sendable {
    case normal
    case disabled
    case loading
    case pending
    case confirmed
    case failed
    case rejected
    case reversed
    case refunded
    case blocked
    case expired
    case offline

    public var tone: FinanceColorToken {
        switch self {
        case .normal:                        return .primary
        case .disabled:                      return .secondary
        case .loading, .pending:             return .pending
        case .confirmed:                     return .success
        case .failed, .rejected:             return .danger
        case .blocked:                       return .blocked
        case .reversed, .refunded:           return .secondary
        case .expired, .offline:             return .warning
        }
    }

    /// Symbole SF associé. `nil` pour `loading`, qui montre un indicateur.
    public var symbol: String? {
        switch self {
        case .normal:    return "circle"
        case .disabled:  return "minus.circle"
        case .loading:   return nil
        case .pending:   return "clock"
        case .confirmed: return "checkmark.circle.fill"
        case .failed:    return "xmark.circle.fill"
        case .rejected:  return "hand.raised.fill"
        case .reversed:  return "arrow.uturn.backward.circle"
        case .refunded:  return "arrow.counterclockwise.circle"
        case .blocked:   return "lock.fill"
        case .expired:   return "hourglass"
        case .offline:   return "wifi.slash"
        }
    }

    /// Seul état qui annonce une réussite. Tout le reste est au mieux neutre.
    public var announcesSuccess: Bool { self == .confirmed }
}

/// Pastille de statut : **texte + icône + couleur**.
///
/// - Le libellé est obligatoire : la couleur ne dit rien à un daltonien, ni à
///   VoiceOver.
/// - Aucune taille de police fixe : le texte suit Dynamic Type jusqu'aux tailles
///   d'accessibilité, et la pastille passe à la ligne plutôt que de tronquer.
/// - Aucune animation : un statut n'a pas à clignoter, et « réduire les
///   animations » n'a donc rien à neutraliser.
public struct TransactionStatusBadge: View {

    private let state: FinanceVisualState
    private let label: String
    /// Remplace le symbole par défaut de l'état, quand la feature en a un plus précis.
    private let symbol: String?
    /// Remplace le ton par défaut — pour un état volontairement neutre, comme
    /// une vérification dont on ne connaît pas encore l'issue.
    private let tone: FinanceColorToken?

    public init(state: FinanceVisualState, label: String,
                symbol: String? = nil, tone: FinanceColorToken? = nil) {
        self.state = state
        self.label = label
        self.symbol = symbol
        self.tone = tone
    }

    private var color: Color { (tone ?? state.tone).color }

    public var body: some View {
        HStack(spacing: 4) {
            if state == .loading {
                ProgressView().controlSize(.mini)
            } else if let name = symbol ?? state.symbol {
                Image(systemName: name).imageScale(.small)
            }
            Text(label)
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        // Un seul élément pour VoiceOver : « Effectué », pas « coche, Effectué ».
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
    }
}

// MARK: - Aperçus

#Preview("États — clair") {
    FinanceStatusBadgePreview()
}

#Preview("États — sombre, texte XXL") {
    FinanceStatusBadgePreview()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility3)
}

private struct FinanceStatusBadgePreview: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(FinanceVisualState.allCases, id: \.self) { state in
                    TransactionStatusBadge(state: state, label: state.rawValue.capitalized)
                }
            }
            .padding()
        }
    }
}
