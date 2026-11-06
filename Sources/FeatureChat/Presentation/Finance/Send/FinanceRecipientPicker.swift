//
//  FinanceRecipientPicker.swift
//  FeatureChat
//
//  Choix du bénéficiaire hors conversation — contact ou QR.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Désigne un bénéficiaire quand aucun fil ne le fournit.
///
/// Ouverts depuis une conversation, les parcours financiers tirent leur
/// destinataire du fil. Ouverts depuis les Réglages, il n'y a personne en face :
/// ce sélecteur comble ce trou, par les deux seuls chemins qui donnent une
/// identité vérifiable — un contact connu, ou un QR que le serveur résout.
///
/// **La saisie libre d'un numéro n'est délibérément pas proposée.** Un numéro
/// tapé à la main est la porte d'entrée classique de la fraude par usurpation :
/// l'utilisateur croit payer un proche, et paie qui a dicté le numéro. Le §17
/// veut que l'identité soit affirmée par le serveur, pas par le clavier.
struct FinanceRecipientPicker: View {

    let contacts: any ContactsUseCasesProtocol
    let qrResolver: any QRResolving
    let translationService: (any TranslationServiceProtocol)?
    /// Contact choisi, **entier** : le parcours qui suit en tire aussi
    /// l'identité de messagerie — le fil où s'annoncera l'opération.
    let onPickedContact: (UserContactProps) -> Void
    /// Bénéficiaire résolu par QR. Aucun nom local, aucune identité de
    /// messagerie : le code ne passe pas par le répertoire.
    let onPickedWalletHandle: (RecipientInput) -> Void
    let onDismiss: () -> Void

    @State private var list: [UserContactProps] = []
    @State private var search = ""
    @State private var isScanning = false
    @State private var isLoading = true

    private var filtered: [UserContactProps] {
        guard !search.isEmpty else { return list }
        let needle = search.lowercased()
        return list.filter {
            $0.name.lowercased().contains(needle) || $0.phone.contains(needle)
        }
    }

    /// `true` quand une pile de navigation existe déjà au-dessus.
    ///
    /// Présenté en feuille, le sélecteur porte sa propre pile et « Annuler ».
    /// Poussé dans une pile existante, il ne doit ni en empiler une seconde ni
    /// offrir « Annuler » : le bouton retour de la pile hôte fait déjà le
    /// travail, et deux commandes de sortie côte à côte se contredisent.
    @Environment(\.financeHasNavigationStack) private var embedded

    var body: some View {
        FinanceNavigationScope {
            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(AppColors.walletCanvas)
                } else if list.isEmpty {
                    FinanceContactsEmptyState(
                        icon: "person.crop.circle.badge.questionmark",
                        title: FinanceStrings.recipientNone,
                        hint: FinanceStrings.recipientScanHint
                    )
                } else if filtered.isEmpty {
                    // Une recherche sans résultat n'est pas un annuaire vide :
                    // proposer de scanner ici répondrait à côté.
                    FinanceContactsEmptyState(
                        icon: "magnifyingglass",
                        title: FinanceStrings.recipientNoResults
                    )
                } else {
                    contactList
                }
            }
            .navigationTitle(FinanceStrings.recipientPickTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Invite passée explicitement : sans elle, iOS écrit « Search » dans
            // la langue de l'appareil, pas dans celle choisie dans l'application.
            .searchable(text: $search, prompt: Text(FinanceStrings.recipientSearch))
            .toolbar {
                if !embedded {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(FinanceStrings.cancel, action: onDismiss)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isScanning = true
                    } label: {
                        Image(systemName: "qrcode.viewfinder")
                    }
                    .accessibilityLabel(FinanceStrings.recipientScanQR)
                }
            }
            // Variante qui reporte l'apparence choisie dans l'application : une
            // présentation n'hérite pas du `preferredColorScheme` de son hôte.
            .chatAppearanceFullScreenCover(isPresented: $isScanning) {
                QRScannerView(
                    resolver: qrResolver,
                    onConfirm: { resolved in
                        isScanning = false
                        // L'identité vient de la résolution serveur, jamais de
                        // la charge du QR : c'est exactement la distinction du
                        // §16, et la contourner ici rendrait le scan crédule.
                        // Bénéficiaire venu d'un QR : aucun nom local à
                        // signaler, le code ne passe pas par le répertoire.
                        onPickedWalletHandle(.walletHandle(resolved.counterparty.actorID))
                    },
                    onDismiss: { isScanning = false }
                )
            }
            .task { await load() }
        }
    }

    private var contactList: some View {
        FinanceContactList(contacts: filtered) { contact in
            Button {
                onPickedContact(contact)
            } label: {
                FinanceContactRow(contact: contact) { FinanceContactChevron() }
            }
            .buttonStyle(ScaleButtonStyle())
            .disabled(contact.isBlocked)
        }
    }

    private func load() async {
        // Contacts **persistés** : ceux que l'utilisateur connaît déjà dans
        // l'application. Lire l'annuaire de l'appareil ici demanderait une
        // permission pour un écran financier, ce qui se refuse à raison.
        // Le cas d'usage rend deux listes ; seuls les contacts Waangu portent
        // un compte financier, et proposer un contact de l'appareil mènerait à
        // une résolution qui échoue systématiquement.
        let result = try? await contacts.getPersistedContacts.execute()
        await MainActor.run {
            list = result?.UserContactProps ?? []
            isLoading = false
        }
    }
}
