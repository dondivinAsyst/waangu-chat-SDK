
import SwiftUI
import WaanguSharedUI
import WaanguCoreKit


@available(iOS 16.0, *)
struct SettingsTabScreen: View {

    // MARK: - State

    @State private var searchText = ""
    @State private var isSignOutAlertPresented = false
    /// Drives the language row display. Updated immediately when user picks a language
    /// so the row text re-renders without needing any observable object.
    @State private var selectedLanguage: AppLanguage = .en
    /// Bumped on locale change so List rows re-resolve translated strings.
    @State private var localeToken: Int = 0
    /// Owned here rather than by a `NavigationLink` inside the list.
    ///
    /// Changing the language rebuilds that list — see `.id(localeToken)` — and a
    /// link inside it is destroyed mid-push, stranding the screen it pushed:
    /// the language applied, and then Back did nothing. Held outside the
    /// rebuilt subtree, the push survives the change and can still be undone by
    /// the back button.
    @State private var isLanguagePickerPresented = false

    // MARK: - Props

    private let currentUser: UserItem
    private let onExitToMainApp: (() -> Void)?
    private let onSignOut: (() -> Void)?
    private let onNavigate: (SettingsTabRoute) -> Void
    private var appSettings: (any AppSettingsProtocol)?
    private let translationService: (any TranslationServiceProtocol)?

    // MARK: - Init

    init(
        _ currentUser: UserItem,
        appSettings: (any AppSettingsProtocol)? = nil,
        translationService: (any TranslationServiceProtocol)? = nil,
        onNavigate: @escaping (SettingsTabRoute) -> Void = { _ in },
        onExitToMainApp: (() -> Void)? = nil,
        onSignOut: (() -> Void)? = nil
    ) {
        self.currentUser = currentUser
        self.onExitToMainApp = onExitToMainApp
        self.onSignOut = onSignOut
        self.onNavigate = onNavigate
        self.appSettings = appSettings
        self.translationService = translationService
        // Seed the @State from persisted settings.
        // _selectedLanguage must be set before body is evaluated.
        self._selectedLanguage = State(initialValue: appSettings?.languageCode ?? .en)
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            List {

                // ── Profile header ────────────────────────────────────────
                SettingsHeaderView(
                    currentUser,
                    translationService: translationService,
                    onTap: { onNavigate(.profile) }
                )

                // ── Back to main app (shown only inside the mini chat window)
                if let onExitToMainApp {
                    Section {
                        Button(action: onExitToMainApp) {
                            HStack(spacing: 12) {
                                Image(systemName: "house.fill")
                                    .foregroundStyle(.green)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t(ChatTranslationKeys.SETTINGS_BACK_TO_WAANGU))
                                    Text(t(ChatTranslationKeys.SETTINGS_RETURN_TO_APP))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                // ── Broadcast / Starred / Linked Devices ──────────────────
                // ── Finance ───────────────────────────────────────────────
                //
                // Section à part, au-dessus des listes de diffusion : la
                // surface financière n'est pas un réglage de messagerie, et la
                // glisser parmi eux la rendrait invisible.
                Section {
                    Button {
                        onNavigate(.finance)
                    } label: {
                        SettingsItemView(item: .finance, translationService: translationService)
                            // Sans forme de contact, seuls l'icône et le libellé
                            // répondent : le `Spacer` qui les sépare du chevron
                            // ne dessine rien, donc ne reçoit aucun appui. La
                            // ligne paraissait morte sur les deux tiers de sa
                            // largeur.
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        onNavigate(.myQRCode)
                    } label: {
                        SettingsItemView(item: .myQRCode, translationService: translationService)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    SettingsItemView(item: .broadcastLists, translationService: translationService)
                    SettingsItemView(item: .starredMessages, translationService: translationService)
                    SettingsItemView(item: .linkedDevices, translationService: translationService)
                }

                // ── Account / Privacy / Chats / … / App Language ──────────
                Section {
                    SettingsItemView(item: .account, translationService: translationService)
                    SettingsItemView(item: .privacy, translationService: translationService)
                    NavigationLink {
                        ChatsSettingsView(translationService: translationService)
                    } label: {
                        SettingsItemView(item: .chats, translationService: translationService)
                    }
                    SettingsItemView(item: .notifications, translationService: translationService)
                    SettingsItemView(item: .storage, translationService: translationService)

                    Button {
                        isLanguagePickerPresented = true
                    } label: {
                        HStack {
                            SettingsItemView(item: .appLanguage, translationService: translationService)
                            Spacer()
                            // This reads @State so SwiftUI re-renders immediately
                            Text(selectedLanguage.displayName)
                                .font(.system(size: 17))
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }

                // ── Help / Tell a Friend ──────────────────────────────────
                Section {
                    SettingsItemView(item: .help, translationService: translationService)
                    SettingsItemView(item: .tellFriend, translationService: translationService)
                }

                // ── Log Out ───────────────────────────────────────────────
                Section {
                    Button {
                        isSignOutAlertPresented = true
                    } label: {
                        SettingsItemView(item: .logout, translationService: translationService)
                    }
                }
            }
            .id(localeToken)
            // Attached outside the identified list on purpose: a destination
            // registered inside it goes away when the locale change rebuilds it.
            .navigationDestination(isPresented: $isLanguagePickerPresented) {
                LanguagePickerView(
                    currentLanguage: selectedLanguage,
                    translationService: translationService,
                    onLanguageSelected: applyLanguageChange
                )
            }
            .navigationTitle(t(ChatTranslationKeys.SETTINGS_TITLE))
            .searchable(text: $searchText)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("TranslationKit.localeDidChange")
                )
            ) { notification in
                guard let code = notification.userInfo?["locale"] as? String,
                      let language = AppLanguage(rawValue: code),
                      // `applyLanguageChange` already rebuilt for this one.
                      // Bumping again rebuilt the whole list a second time and
                      // flickered it.
                      language != selectedLanguage
                else { return }

                selectedLanguage = language
                localeToken += 1
            }
            .alert(t(ChatTranslationKeys.SETTINGS_SIGN_OUT_CONFIRM), isPresented: $isSignOutAlertPresented) {
                Button(common("cancel"), role: .cancel) { }
                Button(t(ChatTranslationKeys.SETTINGS_SIGN_OUT), role: .destructive) {
                    onSignOut?()
                }
            }
        }
    }

    // MARK: - Language

    /// Persists to UserDefaults, reloads TranslationKit, and updates the @State
    /// so the row re-renders immediately — no observable object needed.
    private func applyLanguageChange(_ language: AppLanguage) {
        // The picker stays open. Picking a language is not the end of the task:
        // the user sees the checkmark move and the screen redraw in the new
        // language, and leaves when they choose to.
        selectedLanguage = language
        appSettings?.languageCode = language
        translationService?.reloadPayload(for: language.rawValue)
        localeToken += 1
    }

}

@available(iOS 16.0, *)
extension SettingsTabScreen {
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Header

/// Profile row at the top of settings. Read-only here — tapping it opens the
/// profile screen, which is the one place editing happens.
@available(iOS 16.0, *)
private struct SettingsHeaderView: View {
    private let currentUser: UserItem
    private let translationService: (any TranslationServiceProtocol)?
    private let onTap: () -> Void

    init(
        _ currentUser: UserItem,
        translationService: (any TranslationServiceProtocol)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.currentUser = currentUser
        self.translationService = translationService
        self.onTap = onTap
    }

    var body: some View {
        Section {
            Button(action: onTap) {
                HStack {
                    profileImageView()
                    userInfoTextView()
                }
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func profileImageView() -> some View {
        CircularProfileImageView(currentUser.profileImageURL, size: .custom(55))
    }

    private func userInfoTextView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(currentUser.username)
                    .font(.title2)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Text(currentUser.bioUnwrapped)
                .foregroundStyle(.gray)
                .font(.callout)
        }
        .lineLimit(1)
    }
}
