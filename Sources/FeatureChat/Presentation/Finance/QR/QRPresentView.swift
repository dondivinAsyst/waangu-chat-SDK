//
//  QRPresentView.swift
//  FeatureChat
//
//  Présenter son QR pour être payé — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Affiche le QR que l'utilisateur présente pour encaisser.
///
/// Émission, rotation et révocation vivent dans ``PresentedQRCodeViewModel``,
/// partagé avec le QR d'identité : cet écran n'apporte que la présentation
/// d'un encaissement — montant, référence à dicter, compte à rebours.
struct QRPresentView: View {

    let amount: Money?
    let onDismiss: () -> Void

    @StateObject private var model: PresentedQRCodeViewModel
    @State private var now = Date()
    @Environment(\.dismiss) private var pop
    @Environment(\.scenePhase) private var scenePhase

    init(
        presenter: any QRPresenting,
        kind: QRKind,
        /// Montant exact attendu. `nil` ⇒ le payeur saisit le montant.
        amount: Money?,
        conversationID: String?,
        onDismiss: @escaping () -> Void
    ) {
        self.amount = amount
        self.onDismiss = onDismiss
        _model = StateObject(wrappedValue: PresentedQRCodeViewModel(
            presenter: presenter,
            request: QRPresentationRequest(kind: kind, amount: amount, conversationID: conversationID)
        ))
    }

    /// Rafraîchit l'affichage à la seconde : sans cela, l'expiration et la
    /// rotation ne se déclencheraient qu'au prochain geste de l'utilisateur,
    /// et un QR périmé resterait à l'écran.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch model.phase {
                case .issuing:
                    FinanceProgress(label: FinanceStrings.qrPresentIssuing)
                case .showing(let qr):
                    code(qr)
                case .expired:
                    expired
                case .failed(let message):
                    FinanceMessage(icon: "exclamationmark.triangle", text: message)
                }
            }
            .financePhase(model.phase)
            .navigationTitle(FinanceStrings.qrPresentTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: model.isWorking,
                                 back: { Task { await dismiss(returningToParent: true) } },
                                 onClose: { Task { await dismiss() } })
        }
        .financeLoadOnce { await model.issue() }
        .onReceive(tick) { date in
            now = date
            Task { await model.refreshIfNeeded(now: date) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // En arrière-plan, le QR n'est plus regardé mais reste payable.
            // On le révoque : c'est exactement la fenêtre qu'une photo exploite.
            if newPhase != .active { Task { await model.revokeCurrent() } }
        }
    }

    private func dismiss(returningToParent: Bool = false) async {
        guard await model.prepareToClose() else { return }
        if returningToParent { pop() } else { onDismiss() }
    }

    // MARK: - Vues

    private func code(_ qr: PresentableQR) -> some View {
        VStack(spacing: 20) {
            if let image = QRCodeImageRenderer.render(qr.payload) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 260, maxHeight: 260)
                    .padding(16)
                    .background(.white, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel(FinanceStrings.qrPresentAccessibility)
            } else {
                // L'encodage a échoué : afficher un carré vide laisserait croire
                // qu'il y a un code à scanner.
                FinanceMessage(icon: "qrcode", text: FinanceStrings.qrPresentRenderFailed)
            }

            if let amount = qr.amount {
                Text(AmountEntry.format(amount.majorUnitsForDisplay, amount.currency.code))
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
            } else {
                Text(FinanceStrings.qrPresentOpenAmount)
                    .font(.subheadline).foregroundStyle(.secondary)
            }

            // Le repli quand le scan ne passe pas — mauvaise lumière, écran
            // rayé, caméra capricieuse. Sans lui, l'encaissement s'arrête là.
            if let reference = qr.humanReference {
                VStack(spacing: 4) {
                    Text(FinanceStrings.qrPresentReference)
                        .font(.caption).foregroundStyle(.secondary)
                    Text(reference)
                        .font(.body.monospaced().weight(.medium))
                        .textSelection(.enabled)
                }
            }

            Label(remaining(qr), systemImage: "clock")
                .font(.caption).foregroundStyle(.secondary)
                .monospacedDigit()

            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity)
        // Un QR mal contrasté ne se scanne pas ; on remonte la luminosité
        // le temps de l'affichage.
        .onAppear { UIScreen.main.brightness = 1.0 }
    }

    private var expired: some View {
        VStack(spacing: 16) {
            FinanceMessage(icon: "clock.badge.xmark", text: FinanceStrings.qrPresentExpired)
            Button(FinanceStrings.qrPresentRenew) { Task { await model.issue() } }
                .buttonStyle(.borderedProminent)
        }
    }

    private func remaining(_ qr: PresentableQR) -> String {
        let seconds = max(0, Int(qr.expiresAt.timeIntervalSince(now)))
        return String(format: FinanceStrings.qrPresentExpiresIn, seconds / 60, seconds % 60)
    }
}
