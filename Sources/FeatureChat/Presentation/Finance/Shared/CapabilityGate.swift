//
//  CapabilityGate.swift
//  FeatureChat
//
//  Les quatre portes du §16, appliquées à l'ouverture d'un parcours.
//

import SwiftUI
import WaanguCoreKit

/// N'ouvre un parcours financier que si sa capacité est ouverte.
///
/// Les quatre portes — activation, licence, conformité, partenaire — sont
/// déclarées dans `FinancialCapability` depuis le Bloc 5. Elles n'étaient
/// consultées nulle part : un parcours dont la licence n'est pas accordée
/// s'ouvrait quand même, et l'utilisateur découvrait le refus après avoir saisi
/// un montant.
///
/// Deux sources se cumulent et ne se remplacent pas : le catalogue dit ce qui
/// **existe** pour cette conversation, les portes disent ce qui est **permis**
/// dans ce pays. Un parcours peut figurer au catalogue et rester fermé.
struct CapabilityGate<Content: View>: View {

    /// `nil` ⇒ parcours gouverné ailleurs (les entrées du Bloc 3 passent par
    /// `FinanceCapabilities`, qui préexiste). On n'invente pas une seconde
    /// source de vérité pour la même décision.
    let capabilityID: String?
    /// Le type d'entrée, pour le coupe-circuit — qui suspend par produit.
    let kind: FinanceEntryKind
    let gates: any FinancialCapabilityGateProviding
    let killSwitch: any OperationalKillSwitchProviding
    @ViewBuilder let content: () -> Content

    @State private var phase: Phase = .checking

    private enum Phase: Equatable {
        case checking
        case open
        case suspended(reasonKey: String?)
        case closed(CapabilityClosure)
    }

    var body: some View {
        Group {
            switch phase {
            case .checking:
                FinanceProgress(label: FinanceStrings.capabilityChecking)
            case .open:
                content()
            case .suspended(let reasonKey):
                message(icon: "pause.circle",
                        title: FinanceStrings.killSwitchSuspendedTitle,
                        detail: FinanceStrings.killSwitchReason(reasonKey))
            case .closed(let closure):
                closedState(closure)
            }
        }
        .financePhase(phase)
        .task(id: capabilityID) { await check() }
    }

    private func check() async {
        // Le coupe-circuit d'abord, et pour **tout** parcours — y compris ceux
        // sans identifiant de capacité. Voir `FinanceEntryAdmission`.
        let suspensions = await killSwitch.activeSuspensions()
        // Une capacité absente du catalogue est fermée : le silence du backend
        // n'est pas une autorisation.
        let closure: CapabilityClosure?
        if let capabilityID {
            closure = await gates.closure(for: capabilityID)
        } else {
            closure = nil
        }
        switch FinanceEntryAdmission.decide(kind: kind, suspensions: suspensions, closure: closure) {
        case .open:                       phase = .open
        case .suspended(let reasonKey):   phase = .suspended(reasonKey: reasonKey)
        case .closed(let closure):        phase = .closed(closure)
        }
    }

    /// Fermé **et nommé**.
    ///
    /// « Indisponible dans votre pays » et « en cours de revue de conformité »
    /// appellent des gestes différents : la première invite à ne plus réessayer,
    /// la seconde à revenir. Un message unique ferait relancer le support dans
    /// les deux cas.
    private func closedState(_ closure: CapabilityClosure) -> some View {
        message(icon: icon(for: closure),
                title: FinanceStrings.capabilityClosedTitle,
                detail: FinanceStrings.capabilityClosedReason(closure))
    }

    private func message(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.subheadline.weight(.medium))

            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func icon(for closure: CapabilityClosure) -> String {
        switch closure {
        case .notLicensed:                     return "building.columns"
        case .complianceWithheld:              return "shield"
        case .partnerWithheld:                 return "link.badge.plus"
        case .notYetEffective, .expired:       return "clock"
        case .notEnabled:                      return "lock"
        }
    }
}
