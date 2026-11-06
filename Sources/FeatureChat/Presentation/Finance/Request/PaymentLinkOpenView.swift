//
//  PaymentLinkOpenView.swift
//  FeatureChat
//
//  Phase 4 — ouvrir un lien de paiement reçu.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// L'adresse d'un lien de paiement : `waangu://chat/pay-link?token=…&nonce=…`.
///
/// Le contrat rend un `token` et un `nonce`, pas d'URL. Celle-ci est celle de
/// l'app — le schéma `waangu` qu'elle déclare déjà, lu par `DeepLinkParser`.
/// Elle ne porte rien d'autre : ni montant, ni bénéficiaire. Tout se relit au
/// serveur.
enum PaymentLinkURL {

    /// Le jeton et le nonce d'une adresse de lien, ou `nil` si ce n'en est pas
    /// une. Sert au scanner : un QR de lien n'est pas un QR marchand, il
    /// n'a rien à demander à `/qr/parse`.
    static func read(_ payload: String) -> (token: String, nonce: String)? {
        guard let components = URLComponents(string: payload),
              components.scheme?.lowercased() == "waangu",
              components.host?.lowercased() == "chat",
              components.path.hasSuffix("/pay-link"),
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              let nonce = components.queryItems?.first(where: { $0.name == "nonce" })?.value,
              !token.isEmpty, !nonce.isEmpty
        else { return nil }
        return (token, nonce)
    }

    static func make(token: String, nonce: String) -> URL? {
        var components = URLComponents()
        components.scheme = "waangu"
        components.host = "chat"
        components.path = "/pay-link"
        components.queryItems = [URLQueryItem(name: "token", value: token),
                                 URLQueryItem(name: "nonce", value: nonce)]
        return components.url
    }
}

/// Un lien reçu : inspecté au serveur (`/request-money/payment-link/inspect`), puis — si la
/// demande est payable par cette personne — le parcours de paiement habituel.
///
/// Le lien ne paie rien (`executable=false`). Il ne sert qu'à retrouver la
/// demande ; le débit n'a lieu qu'après devis et confirmation explicite, dans
/// `PayMoneyRequestView`.
struct PaymentLinkOpenView: View {

    let token: String
    let nonce: String
    let surface: ChatFinanceSurface
    /// `nil` ⇒ la carte ne se relit pas ici ; la conversation le fera.
    let objectReader: (any FinancialObjectUseCasesProtocol)?
    let onDismiss: () -> Void

    @State private var phase: Phase = .checking

    private enum Phase: Equatable {
        case checking
        case payable(MoneyRequestOverlay)
        /// Lu, mais pas payable par cette personne — dit pourquoi.
        case notPayable(String)
        case invalid(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                FinanceNavigationScope {
                    FinanceProgress(label: FinanceStrings.linkOpenChecking, animation: .searching)
                        .toolbar { closeButton }
                }
            case .payable(let request):
                PayMoneyRequestView(request: request,
                                    conversationID: request.conversationID ?? "",
                                    onDismiss: onDismiss)
                    .environment(\.financeFlowSurface, surface)
                    .environment(\.financeOperationKeys, surface.operationKeys)
                    .environment(\.financeObjectReader, objectReader)
                    // La carte de la demande, dans sa conversation, change seule.
                    .environment(\.financePublishReference, nil)
            case .notPayable(let message):
                FinanceNavigationScope {
                    FinanceMessage(icon: "link", text: message)
                        .toolbar { closeButton }
                }
            case .invalid(let message):
                FinanceFailureView(
                    title: FinanceStrings.linkOpenInvalidTitle,
                    message: message,
                    onRetry: { Task { await inspect() } },
                    onDismiss: onDismiss
                )
            }
        }
        .financePhase(phase)
        .task { await inspect() }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(FinanceStrings.close, action: onDismiss)
        }
    }

    @MainActor
    private func inspect() async {
        guard let responder = surface.requestResponder else {
            phase = .invalid(FinanceStrings.errorMessage(.capabilityUnavailable))
            return
        }
        phase = .checking
        switch await responder.inspectLink(token: token, nonce: nonce) {
        case .failure(let error):
            // `CF_036` : lien invalide, expiré ou déjà consommé.
            phase = .invalid(FinanceStrings.errorMessage(error))
        case .success(let request):
            phase = Self.phase(for: request)
        }
    }

    /// Payable seulement si le serveur le propose **à cette personne**.
    private static func phase(for request: MoneyRequestOverlay) -> Phase {
        if request.canPay { return .payable(request) }
        if request.isRequester { return .notPayable(FinanceStrings.linkOpenOwn) }
        switch request.myShare {
        case .paymentSent?: return .notPayable(FinanceStrings.requestCardPaymentSent)
        case .paid?:        return .notPayable(FinanceStrings.requestCardPaid)
        case .declined?:    return .notPayable(FinanceStrings.requestCardDeclined)
        case nil:           return .notPayable(FinanceStrings.linkOpenNotPayable)
        }
    }
}
