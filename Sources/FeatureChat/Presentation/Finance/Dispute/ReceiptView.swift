//
//  ReceiptView.swift
//  FeatureChat
//
//  Consultation d'un reçu — Bloc 3, chapitre 24.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Récupère et présente un reçu émis par le backend.
///
/// **Le client ne fabrique rien.** Il demande une URL signée, l'ouvre, et
/// propose éventuellement de la partager. Aucun PDF n'est composé ici : un
/// document qui ressemble à un reçu officiel sans en être un circulerait comme
/// tel, chez un employeur ou une administration.
struct ReceiptView: View {

    let access: any ReceiptAccessProviding
    let reference: FinancialReference
    /// Le statut décide de la variante demandée : un reçu final n'existe pas
    /// avant la finalité, et en demander un renverrait une erreur là où le
    /// provisoire répond.
    let observedStatus: PaymentStatus
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case ready(SignedReceipt)
        case unavailable(String)
    }

    private var requestedVariant: ReceiptVariant {
        observedStatus.isTerminal ? .final : .provisional
    }

    private var flowIsBusy: Bool {
        false
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading:            progress
                case .ready(let receipt): content(receipt)
                case .unavailable(let m): message(m)
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.receiptTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
        }
        .financeLoadOnce { await load() }
    }

    private func load() async {
        phase = .loading
        switch await access.receipt(for: reference, variant: requestedVariant) {
        case .success(let receipt): phase = .ready(receipt)
        case .failure(let error):
            phase = .unavailable(
                error == .capabilityUnavailable
                    ? FinanceStrings.receiptUnavailable
                    : FinanceStrings.errorMessage(error)
            )
        }
    }

    private var progress: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(FinanceStrings.receiptLoading).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func content(_ receipt: SignedReceipt) -> some View {
        Form {
            // **Un provisoire se signale.** Le présenter comme définitif en
            // ferait un faux justificatif — et il circulerait comme tel.
            if receipt.variant == .provisional {
                Section {
                    Label(FinanceStrings.receiptProvisional,
                          systemImage: "clock.badge.exclamationmark")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                LabeledContent(FinanceStrings.receiptReference, value: receipt.receiptID)
                LabeledContent(FinanceStrings.receiptVersion, value: "\(receipt.version)")
            }

            if receipt.isExpired() {
                Section {
                    Label(FinanceStrings.receiptExpiredLink, systemImage: "link.badge.plus")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                    Button(FinanceStrings.receiptRefresh) {
                        Task { await load() }
                    }
                }
            }

            Section {
                Link(destination: receipt.url) {
                    Label(FinanceStrings.receiptOpen, systemImage: "doc.text")
                }
                .disabled(!receipt.isOpenable())

                if receipt.allowsSharing() {
                    ShareLink(item: receipt.url) {
                        Label(FinanceStrings.receiptShare, systemImage: "square.and.arrow.up")
                    }
                } else {
                    Label(FinanceStrings.receiptNotShareable, systemImage: "square.and.arrow.up.trianglebadge.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                // Dire que le lien est temporaire : une URL recopiée reste
                // ouvrable par quiconque la détient jusqu'à son échéance.
                Text(FinanceStrings.receiptLinkTemporary).font(.caption)
            }
        }
    }
}
