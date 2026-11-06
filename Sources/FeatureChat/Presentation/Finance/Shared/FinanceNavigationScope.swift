import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct FinanceActivityBusyKey: PreferenceKey {
    static let defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = value || nextValue() }
}

private struct FinanceStackKey: EnvironmentKey {
    static let defaultValue = false
}

private struct FinancePublicationKey: EnvironmentKey {
    static let defaultValue: (@MainActor (FinancialReference, String?) async -> Bool)? = nil
}

private struct FinanceObjectReaderKey: EnvironmentKey {
    static let defaultValue: (any FinancialObjectUseCasesProtocol)? = nil
}

private struct FinanceSurfaceKey: EnvironmentKey {
    static let defaultValue: ChatFinanceSurface? = nil
}

/// Registre des clés d'idempotence des écrans financiers.
///
/// Défaut **en mémoire seulement** : un écran monté hors d'un hôte financier —
/// aperçu, test — garde la protection du processus. Les hôtes réels injectent
/// celui de la surface, adossé au trousseau.
private struct FinanceOperationKeysKey: EnvironmentKey {
    static let defaultValue = FinanceOperationKeys.processLocal
}

extension EnvironmentValues {
    var financeObjectReader: (any FinancialObjectUseCasesProtocol)? {
        get { self[FinanceObjectReaderKey.self] }
        set { self[FinanceObjectReaderKey.self] = newValue }
    }

    var financePublishReference: (@MainActor (FinancialReference, String?) async -> Bool)? {
        get { self[FinancePublicationKey.self] }
        set { self[FinancePublicationKey.self] = newValue }
    }

    var financeHasNavigationStack: Bool {
        get { self[FinanceStackKey.self] }
        set { self[FinanceStackKey.self] = newValue }
    }
    var financeOperationKeys: FinanceOperationKeys {
        get { self[FinanceOperationKeysKey.self] }
        set { self[FinanceOperationKeysKey.self] = newValue }
    }

    var financeFlowSurface: ChatFinanceSurface? {
        get { self[FinanceSurfaceKey.self] }
        set { self[FinanceSurfaceKey.self] = newValue }
    }
}

/// Owns a stack only at a finance entry boundary. Child screens reuse the stack,
/// while existing standalone callers still receive a complete navigation view.
struct FinanceNavigationScope<Content: View>: View {
    @Environment(\.financeHasNavigationStack) private var embedded
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            if embedded {
                content()
            } else {
                NavigationStack {
                    content().environment(\.financeHasNavigationStack, true)
                }
            }
        }
        .tint(AppColors.primary)
        .scrollContentBackground(.hidden)
        .background(AppColors.backgroundGradient.opacity(0.4))
    }
}

extension View {
    /// - Parameter onDarkSurface: l'écran couvre le sien d'un fond sombre — un
    ///   flux caméra, par exemple. La commande de fermeture passe alors en
    ///   pastille blanche : sur ce fond, celle que le système dessine est un
    ///   gris sombre qui disparaît dans l'image.
    func financeTaskControls(
        isBusy: Bool = false,
        isDirty: Bool = false,
        back: (() -> Void)? = nil,
        discardDetail: FinanceDiscardDetail = .generic,
        onDarkSurface: Bool = false,
        onClose: @escaping () -> Void
    ) -> some View {
        modifier(FinanceTaskControls(isBusy: isBusy, isDirty: isDirty, back: back,
                                     discardDetail: discardDetail,
                                     onDarkSurface: onDarkSurface, onClose: onClose))
    }
    /// The existing selection remains the source of truth, including clearing it
    /// on Back. No domain entity needs Hashable conformance or a new route case.
    func financeDestination<Item: Identifiable, Destination: View>(
        item: Binding<Item?>,
        @ViewBuilder destination: @escaping (Item) -> Destination
    ) -> some View {
        navigationDestination(isPresented: Binding(
            get: { item.wrappedValue != nil },
            set: { if !$0 { item.wrappedValue = nil } }
        )) {
            if let selected = item.wrappedValue { destination(selected) }
        }
    }

    func financeDestination<Destination: View>(
        isPresented: Binding<Bool>,
        @ViewBuilder destination: @escaping () -> Destination
    ) -> some View {
        navigationDestination(isPresented: isPresented, destination: destination)
    }

    /// Popping a child must not reinitialize its parent's draft or list selection.
    func financeLoadOnce(_ action: @escaping () async -> Void) -> some View {
        modifier(FinanceInitialLoad(action: action))
    }
}

/// Ce que l'alerte d'abandon dit avoir perdu.
///
/// Deux textes seulement : « Aucun argent n'a été envoyé » rassure sur un écran
/// où l'on saisit un montant, et sonne faux sur un formulaire de litige ou de
/// règles de change, où il n'était question d'aucun envoi.
enum FinanceDiscardDetail {
    /// Écran où l'on saisit un montant à envoyer ou à recevoir.
    case moneyEntry
    /// Tout autre formulaire.
    case generic

    var text: String {
        switch self {
        case .moneyEntry: return FinanceStrings.flowDiscardDetail
        case .generic:    return FinanceStrings.flowDiscardDetailGeneric
        }
    }
}

extension DialogConfiguration {

    /// « Abandonner ce brouillon ? », identique sur tous les parcours.
    ///
    /// « Continuer la saisie » en premier et en bouton plein : l'abandon ne doit
    /// pas être le geste le plus facile.
    /// Un refus, dans le dialogue de l'application.
    ///
    /// Le message s'affichait en rouge sous le montant : sur un écran dont le
    /// bas est occupé par le pavé numérique, il passait sous les doigts, et un
    /// texte rouge ne dit pas si l'opération est partie. Le dialogue arrête le
    /// geste et demande un acquittement.
    static func financeError(message: String) -> DialogConfiguration {
        DialogConfiguration(
            title: FinanceStrings.errorDialogTitle,
            message: message,
            style: .warning,
            buttons: [DialogButton(title: FinanceStrings.close, role: .primary) {}]
        )
    }

    static func financeDiscard(
        detail: FinanceDiscardDetail,
        onDiscard: @escaping () -> Void
    ) -> DialogConfiguration {
        DialogConfiguration(
            title: FinanceStrings.flowDiscard,
            message: detail.text,
            style: .destructive,
            buttons: [
                DialogButton(title: FinanceStrings.flowKeepEditing, role: .primary) {},
                DialogButton(title: FinanceStrings.flowDiscardAction, role: .destructive, action: onDiscard),
            ]
        )
    }
}

private struct FinanceTaskControls: ViewModifier {
    let isBusy: Bool
    let isDirty: Bool
    let back: (() -> Void)?
    let discardDetail: FinanceDiscardDetail
    let onDarkSurface: Bool
    let onClose: () -> Void
    @State private var showsDiscard = false
    @State private var authenticationBusy = false
    private var busy: Bool { isBusy || authenticationBusy }

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(FinanceActivityBusyKey.self) { authenticationBusy = $0 }
            .disabled(busy)
            .navigationBarBackButtonHidden(busy || back != nil || isDirty)
            .interactiveDismissDisabled(busy || isDirty)
            .toolbar {
                if let back, !busy {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: back) {
                            Label(FinanceStrings.flowBack, systemImage: "chevron.left")
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    // Deux boutons distincts plutôt qu'un style choisi à
                    // l'exécution : `buttonStyle(_:)` est générique sur le
                    // style, et les deux branches n'ont pas le même type.
                    //
                    // `.plain` n'est posé que sur fond sombre, sinon la barre
                    // dessinerait son propre fond derrière la pastille blanche
                    // et l'on verrait deux capsules imbriquées.
                    if onDarkSurface {
                        Button {
                            if isDirty { showsDiscard = true } else { onClose() }
                        } label: {
                            Text(FinanceStrings.close)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 7)
                                .background(Color.white, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(busy)
                    } else {
                        Button(FinanceStrings.close) {
                            if isDirty { showsDiscard = true } else { onClose() }
                        }
                        .disabled(busy)
                    }
                }
            }
            // Le dialogue de l'application, et non une alerte système : celle-ci
            // suit le réglage de l'appareil et restait claire sur un écran
            // affiché en sombre. Même dialogue que l'envoi d'argent.
            .chatAppearanceDialog(
                isPresented: $showsDiscard,
                configuration: .financeDiscard(detail: discardDetail, onDiscard: onClose)
            )
    }
}

private struct FinanceInitialLoad: ViewModifier {
    let action: () async -> Void
    @State private var loaded = false

    func body(content: Content) -> some View {
        content.task {
            guard !loaded else { return }
            loaded = true
            await action()
            if Task.isCancelled { loaded = false }
        }
    }
}


