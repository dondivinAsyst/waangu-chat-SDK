//
//  MyQRCodeScreen.swift
//  FeatureChat
//
//  Mon QR : se faire ajouter, écrire ou payer — et scanner celui des autres.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Le QR d'identité de l'utilisateur, et le scanner qui lit celui des autres.
///
/// Un seul code pour les deux usages d'une rencontre : la personne qui le scanne
/// peut payer, et — quand le backend rend l'identité de messagerie — écrire ou
/// ajouter le contact. Le code est un QR `user` **émis et signé par le
/// backend**, avec le même cycle de vie que le QR d'encaissement : rotation,
/// révocation à la fermeture et en arrière-plan.
struct MyQRCodeScreen: View {

    let surface: ChatFinanceSurface
    let userName: String
    let avatarURL: String?
    /// Ouvre la conversation individuelle d'une personne scannée.
    let onOpenConversation: (ConversationType) -> Void
    let onBack: () -> Void

    @StateObject private var model: PresentedQRCodeViewModel
    @State private var now = Date()
    @State private var isScanning = false
    @State private var scanned: ScannedCode?
    @Environment(\.scenePhase) private var scenePhase

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    struct ScannedCode: Identifiable {
        let resolved: ResolvedQR
        var id: String { resolved.reference.id }
    }

    init(
        surface: ChatFinanceSurface,
        userName: String,
        avatarURL: String?,
        onOpenConversation: @escaping (ConversationType) -> Void,
        onBack: @escaping () -> Void
    ) {
        self.surface = surface
        self.userName = userName
        self.avatarURL = avatarURL
        self.onOpenConversation = onOpenConversation
        self.onBack = onBack
        _model = StateObject(wrappedValue: PresentedQRCodeViewModel(
            presenter: surface.qrPresenter,
            request: QRPresentationRequest(kind: .user)
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            WalletNavigationBar(title: FinanceStrings.myQRTitle, onBack: close) { EmptyView() }

            ScrollView {
                VStack(spacing: DesignTokens.spacingL) {
                    card
                    Text(FinanceStrings.myQRPrivacy)
                        .font(.footnote)
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DesignTokens.spacingL)
                }
                .padding(.top, DesignTokens.spacingXL)
                .padding(.horizontal, DesignTokens.spacingL)
            }

            actions
        }
        .background(AppColors.walletCanvas)
        .navigationBarHidden(true)
        .task { await model.issue() }
        .onReceive(tick) { date in
            now = date
            Task { await model.refreshIfNeeded(now: date) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Hors de l'écran, le code n'est plus regardé mais reste valide.
            if newPhase != .active { Task { await model.revokeCurrent() } }
        }
        .chatAppearanceFullScreenCover(isPresented: $isScanning) {
            QRScannerView(
                resolver: surface.qrResolver,
                onConfirm: { resolved in
                    isScanning = false
                    scanned = ScannedCode(resolved: resolved)
                },
                onDismiss: { isScanning = false }
            )
        }
        .chatAppearanceSheet(item: $scanned) { code in
            ScannedQRActionsView(
                resolved: code.resolved,
                surface: surface,
                onMessage: { identity in
                    scanned = nil
                    onOpenConversation(.direct(
                        phoneNumber: identity.phoneNumber,
                        conversationId: nil,
                        peer: DirectChatPeer(
                            userId: identity.userID,
                            name: identity.displayName,
                            avatar: identity.avatarURL ?? ""
                        )
                    ))
                },
                onDismiss: { scanned = nil }
            )
        }
    }

    // MARK: - Carte

    private var card: some View {
        VStack(spacing: DesignTokens.spacingM) {
            avatar
                .offset(y: -44)
                .padding(.bottom, -44)

            VStack(spacing: 2) {
                Text(userName)
                    .font(.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text(FinanceStrings.myQRSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtitleGray)
            }

            code
                .frame(width: 240, height: 240)
        }
        .padding(DesignTokens.spacingL)
        .frame(maxWidth: .infinity)
        .background(AppColors.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.top, 44)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(AppColors.primary.opacity(0.12))
            if let avatarURL, let url = URL(string: avatarURL), !avatarURL.isEmpty {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
                .clipShape(Circle())
            } else {
                initial
            }
        }
        .frame(width: 72, height: 72)
        .overlay(Circle().stroke(AppColors.walletCanvas, lineWidth: 4))
    }

    private var initial: some View {
        Text(String(userName.prefix(1)).uppercased())
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(AppColors.primary)
    }

    @ViewBuilder
    private var code: some View {
        switch model.phase {
        case .issuing:
            ProgressView()
        case .showing(let qr):
            if let image = QRCodeImageRenderer.render(qr.payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(DesignTokens.spacingM)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .accessibilityLabel(FinanceStrings.qrPresentAccessibility)
                    // Un QR mal contrasté ne se scanne pas.
                    .onAppear { UIScreen.main.brightness = 1.0 }
            } else {
                FinanceMessage(icon: "qrcode", text: FinanceStrings.qrPresentRenderFailed)
            }
        case .expired:
            VStack(spacing: DesignTokens.spacingS) {
                FinanceMessage(icon: "clock.badge.xmark", text: FinanceStrings.qrPresentExpired)
                Button(FinanceStrings.qrPresentRenew) { Task { await model.issue() } }
                    .tint(AppColors.primary)
            }
        case .failed(let message):
            // Tant que le backend n'émet pas de QR d'identité, c'est ici qu'on
            // arrive — un message clair, jamais un faux code.
            FinanceMessage(icon: "qrcode", text: message)
        }
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: DesignTokens.spacingS) {
            CustomButton(title: FinanceStrings.myQRScan, icon: "qrcode.viewfinder") {
                isScanning = true
            }
            Button(FinanceStrings.myQRReset) {
                Task { await model.reset() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.primary)
            .disabled(model.isWorking)
        }
        .padding(DesignTokens.spacingL)
    }

    private func close() {
        Task {
            guard await model.prepareToClose() else { return }
            onBack()
        }
    }
}

// MARK: - Après un scan

/// Ce qu'on peut faire avec le QR de quelqu'un : payer, écrire.
///
/// Chaque action n'apparaît que si la résolution serveur l'autorise. « Payer »
/// suit `allowsPayment` ; « Écrire » exige l'identité de messagerie, que le
/// client ne reconstruit jamais depuis la charge utile.
struct ScannedQRActionsView: View {

    let resolved: ResolvedQR
    let surface: ChatFinanceSurface
    let onMessage: (QRMessagingIdentity) -> Void
    let onDismiss: () -> Void

    @State private var isPaying = false

    var body: some View {
        if isPaying {
            QRPaymentView(
                resolved: resolved,
                quoting: surface.transferQuoting,
                sendMoney: surface.sendMoney,
                stepUp: surface.stepUp,
                conversationID: "",
                deviceID: surface.deviceID,
                onDismiss: onDismiss
            )
        } else {
            FinanceNavigationScope {
                FinancePage {
                    VStack(spacing: DesignTokens.spacingS) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 44))
                            .foregroundStyle(AppColors.primary)
                        Text(resolved.messagingIdentity?.displayName ?? resolved.counterparty.displayName)
                            .font(.title3.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)

                    if resolved.messagingIdentity == nil {
                        Text(FinanceStrings.myQRMessageUnavailable)
                            .font(.footnote)
                            .foregroundStyle(AppColors.subtitleGray)
                            .frame(maxWidth: .infinity)
                            .multilineTextAlignment(.center)
                    }
                } actions: {
                    VStack(spacing: DesignTokens.spacingS) {
                        if let identity = resolved.messagingIdentity {
                            CustomButton(title: FinanceStrings.myQRMessage, icon: "bubble.left") {
                                onMessage(identity)
                            }
                        }
                        if resolved.allowsPayment() {
                            CustomButton(title: FinanceStrings.myQRPay, icon: "arrow.up.right",
                                         style: resolved.messagingIdentity == nil ? .primary : .secondary) {
                                isPaying = true
                            }
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(FinanceLocalization.string("common_cancel", fallback: "Annuler"), action: onDismiss)
                    }
                }
            }
        }
    }
}
