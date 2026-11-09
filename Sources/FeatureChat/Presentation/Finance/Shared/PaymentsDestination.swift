//
//  PaymentsDestination.swift
//  FeatureChat
//
//  L'écran ouvert par une entrée du catalogue — un seul, pour toutes les surfaces.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// La table des destinations financières.
///
/// **Une seule, partagée par la conversation et les Réglages.** Il y en avait
/// deux : celle de la conversation couvrait les vingt-trois natures, celle des
/// Réglages sept, et les seize autres y répondaient « ce service s'ouvre depuis
/// une conversation » — ce qui était faux pour la plupart. Deux tables pour une
/// même question finissent toujours par répondre différemment.
///
/// Ce qui change entre les deux surfaces n'est pas l'écran mais **la manière de
/// le présenter** : poussé depuis les Réglages, en feuille depuis une
/// conversation. La présentation appartient donc à l'appelant, et cette vue n'en
/// sait rien.
///
/// Elle ne connaît ni `ChatRoomViewModel` ni les Réglages : seulement des
/// valeurs. C'est ce qui lui permet de servir les deux.
struct PaymentsDestination: View {

    let entry: FinanceCatalogEntry
    let surface: ChatFinanceSurface

    /// Fil où l'opération s'annoncera. Vide hors conversation — l'opération
    /// existe alors sans avoir nulle part où s'annoncer, ce qui est correct.
    let conversationID: String

    /// Dossier personnel du serveur, résolu quand l'écran s'ouvre hors fil.
    ///
    /// Ouverts depuis les Réglages, facture, recharge et espèces n'avaient
    /// aucune conversation à donner au prepare, que Chat Core refusait alors
    /// (`SYS_002`, « conversationId must not be blank »). Le serveur tient pour
    /// ça un dossier à un membre (§5.1.1) ; il se demande **une fois**, ici, au
    /// point par lequel passent tous ces parcours, plutôt que dans chacun.
    @State private var personalFolderID: String?

    /// Bénéficiaire déjà désigné : l'interlocuteur dans une conversation, le
    /// contact choisi depuis les Réglages.
    var recipientInput: RecipientInput?

    /// Numéro suggéré pour une recharge — celui d'en face, quand il y en a un.
    var peerPhoneNumber: String?

    /// Nom sous lequel l'émetteur connaît le bénéficiaire — le contact choisi,
    /// ou le titre de la conversation. Transmis au résolveur, jamais affiché
    /// à la place du nom que celui-ci rend.
    var recipientName: String?

    /// Utilisateur Chat de l'interlocuteur, en conversation directe. `nil`
    /// depuis les Réglages ou dans un groupe.
    var peerChatUserID: String?

    /// Publie la référence produite dans le fil. `nil` hors conversation : il
    /// n'y a alors pas de fil, et non « une publication qui échoue ».
    var publishReference: (@MainActor (FinancialReference, String?) async -> Bool)?

    let onDismiss: () -> Void

    /// Cible résolue par le scanner, propre à cette table.
    ///
    /// Portée ici plutôt que par l'hôte : le scan et le paiement qui le suit
    /// sont deux étapes d'un même parcours, et les faire tenir par la
    /// conversation obligeait les Réglages à en tenir une copie.
    @State private var scanned: ScannedQR?
    /// Lien de paiement lu au scanner.
    @State private var scannedLink: PresentedPaymentLink?

    /// Montant du brouillon du Hub (§2.2), pris à l'ouverture du parcours.
    @State private var draftAmount: Decimal?

    /// Contexte relu par le serveur pour un parcours ouvert depuis une
    /// conversation (§2.3).
    @State private var handoffCheck: HandoffCheck = .checking

    private enum HandoffCheck: Equatable {
        case checking
        case admitted
        case refused(String)
    }

    private struct ScannedQR: Identifiable {
        let resolved: ResolvedQR
        var id: String { resolved.reference.id }
    }

    /// Un code lu, payé par le devis du serveur.
    private struct ScannedPayload: Identifiable {
        let payload: String
        var id: String { payload }
    }
    @State private var scannedPayload: ScannedPayload?

    @Environment(\.financeObjectReader) private var inheritedObjectReader

    /// Devise imposée par Chat Core (§0.3.8). `BIF` n'est qu'un repli tant que la
    /// session n'a pas répondu — et le seul comportement du mode simulé.
    @State private var serverCurrency: String?
    private var currency: String { serverCurrency ?? "BIF" }

    var body: some View {
        // Les quatre portes du §16 — activation, licence, conformité, partenaire —
        // appliquées **ici**, au seul point par lequel passe tout parcours.
        //
        // Elles étaient appliquées dans l'hôte, et dans un seul : le plein écran de
        // la conversation. Les deux chemins ajoutés ensuite — le parcours ouvert
        // dans la feuille de conversation, et le portefeuille des Réglages —
        // construisaient la destination directement. Un envoi à l'étranger dont la
        // licence est retirée ou la conformité suspendue s'y ouvrait donc quand
        // même : contournement de navigation, Bloc 13 P0.
        //
        // Posé dans la destination, le contrôle ne dépend plus de l'hôte : un
        // nouveau chemin d'accès ne peut pas l'oublier.
        CapabilityGate(capabilityID: entry.kind.capabilityID, kind: entry.kind,
                       gates: surface.capabilityGates, killSwitch: surface.killSwitch) {
            admittedBody
        }
        // Chaque parcours financier passe par ici : c'est le point unique où
        // brancher le registre persistant, quel que soit l'hôte.
        .environment(\.financeOperationKeys, surface.operationKeys)
        // Même raison pour le magasin : sans lui, depuis les Réglages, aucune
        // opération n'était inscrite avant soumission ni reprise après un kill.
        // Le lecteur hérité reste le repli, pour ne jamais en retirer un.
        .environment(\.financeObjectReader, surface.objectReader ?? inheritedObjectReader)
        .task {
            guard let session = surface.financeSession,
                  case .success(let status) = await session.status() else { return }
            serverCurrency = status.currency
        }
        .task(id: entry.id) {
            // Ouvrir un parcours vide la boîte, qu'il prenne le brouillon ou non.
            draftAmount = await surface.textDrafts.take(for: entry.kind)?.amount
            guard needsHandoff else { return }
            handoffCheck = await checkHandoff()
        }
        .task(id: entry.kind) {
            guard conversationID.isEmpty, entry.kind.usesPersonalFolder,
                  personalFolderID == nil else { return }
            personalFolderID = await surface.catalog.personalFolder()?.conversationID
        }
    }

    /// La conversation que portent les parcours de cette destination : le fil
    /// d'où l'écran a été ouvert, ou le dossier personnel quand il n'y en a pas.
    ///
    /// L'exécution ne la choisit pas de son côté : elle reprend celle que le
    /// prepare a rendue — le contrat exige la même pour les deux appels.
    private var operatingConversationID: String {
        conversationID.isEmpty ? (personalFolderID ?? "") : conversationID
    }

    // MARK: - Handoff (§2.3)

    /// Ouvert depuis une conversation, sur le serveur réel : le contexte —
    /// conversation, action — est relu par le serveur avant d'ouvrir. Hors
    /// conversation, il n'y a rien à relire.
    private var needsHandoff: Bool {
        !conversationID.isEmpty && surface.catalog.providesHandoff
    }

    @ViewBuilder
    private var admittedBody: some View {
        if !needsHandoff {
            destinationBody
        } else {
            switch handoffCheck {
            case .checking:             FinanceProgress(label: FinanceStrings.hubLoading)
            case .admitted:             destinationBody
            case .refused(let message): FinanceEntryUnavailableView(message: message)
            }
        }
    }

    /// Les entrées du Hub portent le code de leur action (`id`, en minuscules).
    ///
    /// Un refus **du serveur** — action hors contexte (`CF_026`), non-membre,
    /// session refusée — ferme le parcours. Un réseau ou un serveur muet ne le
    /// ferme pas : le prepare relit de toute façon chaque garde, et un handoff
    /// injoignable n'est pas une raison d'interdire ce que le serveur permettra.
    private func checkHandoff() async -> HandoffCheck {
        switch await surface.catalog.handoff(conversationID: conversationID,
                                             actionCode: entry.id.uppercased()) {
        case .success(let context):
            if let returned = context.conversationID, !returned.isEmpty, returned != conversationID {
                return .refused(FinanceStrings.handoffContextMismatch)
            }
            return .admitted
        case .failure(let error):
            switch error {
            case .forbidden, .unauthorized, .capabilityUnavailable, .conflict:
                return .refused(FinanceStrings.errorMessage(error))
            default:
                #if DEBUG
                print("[FinanceHandoff] check unavailable, opening anyway: \(error)")
                #endif
                return .admitted
            }
        }
    }

    @ViewBuilder
    private var destinationBody: some View {
        Group {
            switch entry.kind {
            case .requestMoney:
                if let input = recipientInput {
                    RequestMoneyView(
                        recipientResolver: surface.recipientResolver,
                        recipientName: recipientName,
                        peerChatUserID: peerChatUserID,
                        requests: surface.moneyRequests,
                        recipientInput: input,
                        conversationID: conversationID,
                        currency: currency,
                        deviceID: surface.deviceID,
                        initialAmount: draftAmount,
                        onDismiss: { onDismiss() }
                    )
                    .environment(\.financePublishReference, publishReference)
                } else {
                    FinanceEntryUnavailableView(
                        message: "Les demandes de groupe ne sont pas encore disponibles."
                    )
                }
            case .sendMoney:
                if let input = recipientInput {
                    SendMoneyView(
                        recipientResolver: surface.recipientResolver,
                        recipientName: recipientName,
                        quoting: surface.transferQuoting,
                        sendMoney: surface.sendMoney,
                        recipientInput: input,
                        conversationID: conversationID,
                        currency: currency,
                        deviceID: surface.deviceID,
                        fundingSources: surface.fundingSources,
                        initialAmount: draftAmount,
                        onDismiss: { onDismiss() }
                    )
                    .environment(\.financePublishReference, publishReference)
                } else {
                    FinanceEntryUnavailableView(
                        message: "Les envois de groupe ne sont pas encore disponibles."
                    )
                }
            case .cashIn:
                CashInView(
                    initiating: surface.cashIn,
                    conversationID: operatingConversationID,
                    currency: currency,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .cashOut:
                CashOutView(
                    issuing: surface.cashOut,
                    stepUp: surface.stepUp,
                    conversationID: operatingConversationID,
                    currency: currency,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .payBill:
                PayBillView(
                    billing: surface.bills,
                    validateField: surface.billFieldValidator,
                    conversationID: operatingConversationID,
                    deviceID: surface.deviceID,
                    mandates: surface.mandates,
                    onDismiss: { onDismiss() }
                )

            case .topUp:
                TopUpView(
                    ordering: surface.topUp,
                    conversationID: operatingConversationID,
                    deviceID: surface.deviceID,
                    suggestedNumber: peerPhoneNumber,
                    onDismiss: { onDismiss() }
                )

            // ── Bloc 5 ───────────────────────────────────────
            case .remittance:
                // Plus de blocage en groupe : le bénéficiaire d'un envoi
                // international n'est pas forcément l'interlocuteur, et il se
                // saisit dans l'écran.
                RemittanceView(
                    sending: surface.remittance,
                    recipientResolver: surface.recipientResolver,
                    stepUp: surface.stepUp,
                    recipientInput: recipientInput,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )
            case .fxConversion:
                FXConversionView(
                    fx: surface.fx, deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )
            case .credit:
                CreditView(
                    lending: surface.credit, stepUp: surface.stepUp,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )
            case .savings:
                SavingsView(
                    savings: surface.savings, stepUp: surface.stepUp,
                    deviceID: surface.deviceID, currency: serverCurrency,
                    onDismiss: { onDismiss() }
                )
            case .investment:
                InvestmentView(
                    trading: surface.investment, stepUp: surface.stepUp,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )
            case .pfm:
                PFMView(pfm: surface.pfm, deviceID: surface.deviceID,
                        onDismiss: { onDismiss() })

            case .qrPay:
                QRScannerView(
                    resolver: surface.qrResolver,
                    onPaymentLink: { token, nonce in
                        scannedLink = PresentedPaymentLink(token: token, nonce: nonce)
                    },
                    onPayload: surface.qrResolver.providesQuotes
                        ? { scannedPayload = ScannedPayload(payload: $0) } : nil,
                    onConfirm: { scanned = ScannedQR(resolved: $0) },
                    onDismiss: onDismiss
                )
                .financeDestination(item: $scannedPayload) { target in
                    QRQuotePaymentView(
                        payload: target.payload,
                        resolver: surface.qrResolver,
                        deviceID: surface.deviceID,
                        conversationID: operatingConversationID,
                        onDismiss: onDismiss
                    )
                }
                .financeDestination(item: $scannedLink) { link in
                    PaymentLinkOpenView(
                        token: link.token, nonce: link.nonce,
                        surface: surface,
                        objectReader: surface.objectReader ?? inheritedObjectReader,
                        onDismiss: onDismiss
                    )
                }
                .financeDestination(item: $scanned) { target in
                    QRPaymentView(
                        resolved: target.resolved,
                        quoting: surface.transferQuoting,
                        sendMoney: surface.sendMoney,
                        stepUp: surface.stepUp,
                        conversationID: conversationID,
                        deviceID: surface.deviceID,
                        onDismiss: onDismiss
                    )
                }

            case .qrPresent:
                // Aucun montant fixé : le catalogue ouvre l'encaissement, pas
                // une demande chiffrée. Le payeur saisit ce qu'il doit, ou le
                // backend le déduit de la référence.
                QRPresentView(
                    presenter: surface.qrPresenter,
                    kind: .user,
                    amount: nil,
                    conversationID: conversationID,
                    onDismiss: { onDismiss() }
                )

            case .merchant:
                // Le marchand est nommé par le catalogue. Sans identifiant,
                // rien ne s'ouvre : deviner le marchand depuis l'interlocuteur
                // donnerait à la conversation un pouvoir financier.
                if let merchantID = entry.targetID {
                    MerchantProfileView(
                        merchantID: merchantID,
                        profiles: surface.merchantProfiles,
                        commerce: surface.commerce,
                        conversationID: conversationID,
                        deviceID: surface.deviceID,
                        onDismiss: { onDismiss() }
                    )
                } else {
                    FinanceEntryUnavailableView(
                        message: FinanceStrings.merchantNotIdentified
                    )
                }

            case .orders:
                OrdersView(
                    commerce: surface.commerce,
                    stepUp: surface.stepUp,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .invoice:
                // La facture est nommée par le catalogue, comme le marchand.
                if let invoiceID = entry.targetID {
                    InvoiceView(
                        invoiceID: invoiceID,
                        invoices: surface.merchantInvoices,
                        stepUp: surface.stepUp,
                        deviceID: surface.deviceID,
                        conversationID: operatingConversationID,
                        onDismiss: { onDismiss() }
                    )
                } else {
                    FinanceEntryUnavailableView(message: FinanceStrings.invoiceNotIdentified)
                }

            case .reconciliation:
                ReconciliationListView(
                    reconciliation: surface.reconciliation,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .campaign:
                CampaignListView(
                    campaigns: surface.campaigns,
                    stepUp: surface.stepUp,
                    conversationID: conversationID,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .splitBill:
                SplitBillListView(
                    splits: surface.splitBills,
                    sharing: surface.splitSharing,
                    currentUserID: surface.currentUserID,
                    stepUp: surface.stepUp,
                    conversationID: conversationID,
                    deviceID: surface.deviceID,
                    currency: serverCurrency,
                    onDismiss: { onDismiss() }
                )

            case .cards:
                CardsView(
                    cards: surface.cards,
                    transactions: surface.cardTransactions,
                    stepUp: surface.stepUp,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .paymentLinks:
                IssuedPaymentLinksView(
                    links: surface.paymentLinks,
                    deviceID: surface.deviceID,
                    onDismiss: { onDismiss() }
                )

            case .remoteForm:
                // Le formulaire est nommé par le catalogue, comme le marchand.
                if let formID = entry.targetID {
                    RemoteFormView(
                        formID: formID,
                        context: ["conversationID": conversationID],
                        forms: surface.remoteForms,
                        deviceID: surface.deviceID,
                        onCompleted: { _ in onDismiss() },
                        onDismiss: { onDismiss() }
                    )
                } else {
                    FinanceEntryUnavailableView(message: FinanceStrings.formNotIdentified)
                }
            }
        }
    }
}
