//
//  RecipientEntryView.swift
//  FeatureChat
//
//  Saisie d'un bénéficiaire — Bloc 5, chapitre 35.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Saisit un bénéficiaire qui n'est pas l'interlocuteur de la conversation.
///
/// Jusqu'ici, le seul bénéficiaire possible était le numéro du contact en face.
/// Un envoi international vers un compte bancaire était donc impossible, et
/// aucun envoi n'était possible depuis un groupe.
///
/// **Rien n'est validé au-delà de la forme.** Ce qui constitue un numéro de
/// compte valide dépend de l'institution et du pays ; un motif client trop
/// strict refuserait un compte pourtant réel. La résolution appartient au
/// backend, et c'est lui qui nomme le titulaire.
struct RecipientEntryView: View {

    /// Modes acceptés par le corridor. Le backend les fournit ; l'écran ne
    /// propose pas un virement bancaire là où le partenaire n'en fait pas.
    let allowedMethods: [RemittanceDeliveryMethod]
    let onEntered: (RecipientInput) -> Void
    let onDismiss: () -> Void

    @State private var method: Method = .phone

    // Téléphone / wallet
    @State private var phone = ""
    @State private var handle = ""

    // Mobile money
    @State private var operatorID = ""
    @State private var msisdn = ""

    // Compte bancaire
    @State private var countryCode = ""
    @State private var accountNumber = ""
    @State private var institutionCode = ""
    @State private var branchCode = ""
    @State private var holderName = ""

    // Retrait espèces
    @State private var agentNetworkID = ""

    private enum Method: String, CaseIterable, Identifiable {
        case phone, walletHandle, mobileMoney, bankAccount, cashPickup
        var id: String { rawValue }
    }

    var body: some View {
        FinanceNavigationScope {
            Form {
                Section(FinanceStrings.recipientMethod) {
                    Picker(FinanceStrings.recipientMethod, selection: $method) {
                        ForEach(availableMethods) { value in
                            Text(label(for: value)).tag(value)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                fields

                Section {
                    CustomButton(title: FinanceStrings.sendContinue) {
                        if let input { onEntered(input) }
                    }
                    .disabled(input == nil)
                    .financeActionRow()
                } footer: {
                    Text(FinanceStrings.recipientServerValidates).font(.caption)
                }
            }
            .navigationTitle(FinanceStrings.recipientTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(FinanceStrings.cancel, action: onDismiss)
                }
            }
        }
    }

    /// Les modes que le corridor rend possibles.
    ///
    /// Quand aucun mode n'est fourni, on n'ouvre pas tout : on retombe sur le
    /// téléphone et le wallet, qui ne dépendent pas d'un partenaire externe.
    private var availableMethods: [Method] {
        guard !allowedMethods.isEmpty else { return [.phone, .walletHandle] }

        var methods: [Method] = [.phone, .walletHandle]
        if allowedMethods.contains(.mobileMoney) { methods.append(.mobileMoney) }
        if allowedMethods.contains(.bankDeposit) { methods.append(.bankAccount) }
        if allowedMethods.contains(.cashPickup)  { methods.append(.cashPickup) }
        return methods
    }

    /// L'entrée composée, ou `nil` si l'essentiel manque.
    ///
    /// Seuls les champs sans lesquels le backend ne peut **rien** faire sont
    /// exigés. Le code institution et l'agence restent facultatifs : ils ne
    /// s'appliquent pas partout, et les rendre obligatoires bloquerait les
    /// corridors qui n'en ont pas.
    private var input: RecipientInput? {
        switch method {
        case .phone:
            return phone.isEmpty ? nil : .phoneNumber(phone)
        case .walletHandle:
            return handle.isEmpty ? nil : .walletHandle(handle)
        case .mobileMoney:
            guard !operatorID.isEmpty, !msisdn.isEmpty else { return nil }
            return .mobileMoney(operatorID: operatorID, msisdn: msisdn)
        case .bankAccount:
            guard !countryCode.isEmpty, !accountNumber.isEmpty, !holderName.isEmpty else { return nil }
            return .bankAccount(BankAccountInput(
                countryCode: countryCode,
                accountNumber: accountNumber.replacingOccurrences(of: " ", with: ""),
                institutionCode: institutionCode.isEmpty ? nil : institutionCode,
                branchCode: branchCode.isEmpty ? nil : branchCode,
                accountHolderName: holderName
            ))
        case .cashPickup:
            return agentNetworkID.isEmpty ? nil : .cashPickup(agentNetworkID: agentNetworkID)
        }
    }

    @ViewBuilder
    private var fields: some View {
        switch method {
        case .phone:
            Section {
                TextField(FinanceStrings.recipientPhone, text: $phone)
                    .keyboardType(.phonePad)
            }

        case .walletHandle:
            Section {
                TextField(FinanceStrings.recipientHandle, text: $handle)
                    .textInputAutocapitalization(.never)
            }

        case .mobileMoney:
            Section {
                // L'opérateur est **saisi**, jamais déduit du préfixe : la
                // portabilité des numéros rend toute déduction fausse tôt ou
                // tard, et créditer le mauvais opérateur est une perte sèche.
                TextField(FinanceStrings.recipientOperator, text: $operatorID)
                    .textInputAutocapitalization(.never)
                TextField(FinanceStrings.recipientMsisdn, text: $msisdn)
                    .keyboardType(.phonePad)
            } footer: {
                Text(FinanceStrings.recipientOperatorNote).font(.caption)
            }

        case .bankAccount:
            Section {
                TextField(FinanceStrings.recipientHolder, text: $holderName)
                TextField(FinanceStrings.recipientCountry, text: $countryCode)
                    .textInputAutocapitalization(.characters)
                TextField(FinanceStrings.recipientAccountNumber, text: $accountNumber)
                    .textInputAutocapitalization(.characters)
            }
            Section(FinanceStrings.recipientOptionalFields) {
                TextField(FinanceStrings.recipientInstitution, text: $institutionCode)
                    .textInputAutocapitalization(.characters)
                TextField(FinanceStrings.recipientBranch, text: $branchCode)
            }

        case .cashPickup:
            Section {
                TextField(FinanceStrings.recipientAgentNetwork, text: $agentNetworkID)
            }
        }
    }

    private func label(for method: Method) -> String {
        switch method {
        case .phone:        return FinanceStrings.recipientPhone
        case .walletHandle: return FinanceStrings.recipientHandle
        case .mobileMoney:  return FinanceStrings.recipientMobileMoney
        case .bankAccount:  return FinanceStrings.recipientBankAccount
        case .cashPickup:   return FinanceStrings.recipientCashPickup
        }
    }
}
