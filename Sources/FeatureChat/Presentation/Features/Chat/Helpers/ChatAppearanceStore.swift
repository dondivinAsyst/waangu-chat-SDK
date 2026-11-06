//
//  ChatAppearanceStore.swift
//  FeatureChat
//

import Foundation
import SwiftUI
import WaanguSharedUI
import UIKit
import WaanguCoreKit

enum ChatAppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var translationKey: String {
        switch self {
        case .system: return ChatTranslationKeys.CHAT_APPEARANCE_DEFAULT
        case .light: return ChatTranslationKeys.CHAT_APPEARANCE_LIGHT
        case .dark: return ChatTranslationKeys.CHAT_APPEARANCE_DARK
        }
    }

    var fallbackDisplayName: String {
        switch self {
        case .system: return "Default"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    func displayName(translationService: (any TranslationServiceProtocol)?) -> String {
        translationService?
            .resolve(key: translationKey, module: ChatTranslationKeys.MODULE)
            .value ?? fallbackDisplayName
    }

    var preferredColorScheme: ColorScheme? {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    /// Chat-forced light/dark, otherwise the ambient system scheme.
    func resolvedColorScheme(system: ColorScheme) -> ColorScheme {
        preferredColorScheme ?? system
    }

    var userInterfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .light: return .light
        case .dark: return .dark
        case .system: return .unspecified
        }
    }
}

@MainActor
protocol ChatAppearanceStoreDelegate: AnyObject {
    func chatAppearanceDidChange()
}

@MainActor
final class ChatAppearanceStore: ObservableObject {

    static let shared = ChatAppearanceStore()

    static let didChangeNotification = Notification.Name("ChatAppearanceStore.didChange")

    private static let defaultKey = "chatAppearance.default"
    private static let legacyPrefix = "chatAppearance."

    @Published private(set) var defaultAppearance: ChatAppearancePreference = .system
    @Published private(set) var changeToken: Int = 0

    weak var delegate: ChatAppearanceStoreDelegate?

    private init() {
        migrateLegacyPerChatOverrides()
        reloadFromPersistence()
    }

    /// Applies and always persists to UserDefaults (even when re-selecting the same value).
    func apply(_ pref: ChatAppearancePreference) {
        persist(pref)
        defaultAppearance = pref
        bumpChangeToken()
        delegate?.chatAppearanceDidChange()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }

    /// Re-reads the saved value from disk into memory (e.g. when opening Settings).
    func reloadFromPersistence() {
        let pref = readPersistedPreference()
        guard defaultAppearance != pref else { return }
        defaultAppearance = pref
        bumpChangeToken()
    }

    private func readPersistedPreference() -> ChatAppearancePreference {
        guard let raw = UserDefaults.standard.string(forKey: Self.defaultKey),
              let pref = ChatAppearancePreference(rawValue: raw) else {
            return .system
        }
        return pref
    }

    private func persist(_ pref: ChatAppearancePreference) {
        UserDefaults.standard.set(pref.rawValue, forKey: Self.defaultKey)
    }

    /// Promote any legacy per-chat value to the global key, then remove stale keys.
    private func migrateLegacyPerChatOverrides() {
        if UserDefaults.standard.string(forKey: Self.defaultKey) == nil {
            for (key, value) in UserDefaults.standard.dictionaryRepresentation() {
                guard key.hasPrefix(Self.legacyPrefix), key != Self.defaultKey else { continue }
                if let raw = value as? String,
                   ChatAppearancePreference(rawValue: raw) != nil {
                    UserDefaults.standard.set(raw, forKey: Self.defaultKey)
                    break
                }
            }
        }

        for key in UserDefaults.standard.dictionaryRepresentation().keys {
            guard key.hasPrefix(Self.legacyPrefix), key != Self.defaultKey else { continue }
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private func bumpChangeToken() {
        changeToken += 1
        objectWillChange.send()
    }
}

extension View {
    func chatConversationAppearance(_ viewModel: ChatRoomViewModel) -> some View {
        preferredColorScheme(viewModel.preferredColorScheme)
    }

    /// Applies the global chat light/dark preference (Settings + profile use the same store).
    func globalChatAppearance() -> some View {
        modifier(GlobalChatAppearanceModifier())
    }

    func chatAppearanceSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .globalChatAppearance()
        }
    }

    func chatAppearanceSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item)
                .globalChatAppearance()
        }
    }

    func chatAppearanceFullScreenCover<CoverContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> CoverContent
    ) -> some View {
        fullScreenCover(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .globalChatAppearance()
        }
    }
}

// MARK: - Dialogue

extension View {

    /// Le dialogue de l'application, **par-dessus tout l'écran** et dans
    /// l'apparence choisie dans l'application.
    ///
    /// À préférer à `.alert` : une alerte système suit le réglage de
    /// l'appareil, et restait claire sur un écran que l'application affichait
    /// en sombre. À préférer aussi à `customDialog` sur un écran à barre de
    /// navigation ou dans une feuille : celui-ci se superpose à la seule vue qui
    /// le porte, et laissait la barre — et son bouton Fermer — hors du voile.
    ///
    /// L'action d'un bouton s'exécute **une fois le dialogue fermé**. Fermer la
    /// feuille pendant que le dialogue la recouvre encore ferait se croiser deux
    /// fermetures.
    func chatAppearanceDialog(
        isPresented: Binding<Bool>,
        configuration: DialogConfiguration
    ) -> some View {
        modifier(ChatAppearanceDialogModifier(isPresented: isPresented, configuration: configuration))
    }
}

private struct ChatAppearanceDialogModifier: ViewModifier {
    @Binding var isPresented: Bool
    let configuration: DialogConfiguration

    /// Présentation effective, découplée de la demande pour la poser sans
    /// l'animation de glissement d'un plein écran : le dialogue a la sienne.
    @State private var isCovering = false
    /// Action choisie, jouée à la fermeture du plein écran.
    @State private var pendingAction: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onChange(of: isPresented) { _, requested in
                setCovering(requested)
            }
            .chatAppearanceFullScreenCover(isPresented: coverBinding, onDismiss: runPendingAction) {
                CustomDialog(configuration: deferredConfiguration, isPresented: coverBinding)
                    .presentationBackground(.clear)
            }
    }

    private var coverBinding: Binding<Bool> {
        Binding(
            get: { isCovering },
            set: { visible in
                setCovering(visible)
                if !visible { isPresented = false }
            }
        )
    }

    /// Les mêmes boutons, dont l'action est retenue au lieu d'être jouée.
    private var deferredConfiguration: DialogConfiguration {
        DialogConfiguration(
            title: configuration.title,
            message: configuration.message,
            style: configuration.style,
            buttons: configuration.buttons.map { button in
                DialogButton(title: button.title, role: button.role) {
                    pendingAction = button.action
                }
            },
            animation: configuration.animation
        )
    }

    private func setCovering(_ visible: Bool) {
        guard visible != isCovering else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isCovering = visible }
    }

    private func runPendingAction() {
        let action = pendingAction
        pendingAction = nil
        action?()
    }
}

private struct GlobalChatAppearanceModifier: ViewModifier {
    @ObservedObject private var store = ChatAppearanceStore.shared

    func body(content: Content) -> some View {
        content.preferredColorScheme(store.defaultAppearance.preferredColorScheme)
    }
}
