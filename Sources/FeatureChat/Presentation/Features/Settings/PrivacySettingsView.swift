import SwiftUI
import WaanguSharedUI
import Combine
import WaanguCoreKit

// MARK: - Privacy Settings Model

enum PrivacyVisibility: String, CaseIterable, Codable {
    case everyone = "everyone"
    case myContacts = "my_contacts"
    case nobody = "nobody"

    var translationKey: String {
        switch self {
        case .everyone: return ChatTranslationKeys.PRIVACY_EVERYONE
        case .myContacts: return ChatTranslationKeys.PRIVACY_MY_CONTACTS
        case .nobody: return ChatTranslationKeys.PRIVACY_NOBODY
        }
    }
}

final class PrivacySettingsStore: ObservableObject {

    static let shared = PrivacySettingsStore()

    @AppStorage("privacy.lastSeen") var lastSeen: PrivacyVisibility = .everyone
    @AppStorage("privacy.profilePhoto") var profilePhoto: PrivacyVisibility = .everyone
    @AppStorage("privacy.about") var about: PrivacyVisibility = .everyone
    @AppStorage("privacy.readReceipts") var readReceipts: Bool = true
    @AppStorage("privacy.groups") var groupAdd: PrivacyVisibility = .everyone
    @AppStorage("privacy.liveLocation") var liveLocation: PrivacyVisibility = .myContacts

    private init() {}
}

// MARK: - Privacy Settings View

@available(iOS 17.0, *)
struct PrivacySettingsView: View {

    @StateObject private var store = PrivacySettingsStore.shared
    let translationService: (any TranslationServiceProtocol)? = nil

    var body: some View {
        List {
            Section {
                NavigationLink {
                    PrivacyOptionPicker(
                        title: t(ChatTranslationKeys.PRIVACY_LAST_SEEN),
                        selection: $store.lastSeen,
                        translationService: translationService
                    )
                } label: {
                    LabeledContent(t(ChatTranslationKeys.PRIVACY_LAST_SEEN)) { Text(displayName(for: store.lastSeen)) }
                }

                NavigationLink {
                    PrivacyOptionPicker(
                        title: t(ChatTranslationKeys.PRIVACY_PROFILE_PHOTO),
                        selection: $store.profilePhoto,
                        translationService: translationService
                    )
                } label: {
                    LabeledContent(t(ChatTranslationKeys.PRIVACY_PROFILE_PHOTO)) { Text(displayName(for: store.profilePhoto)) }
                }

                NavigationLink {
                    PrivacyOptionPicker(
                        title: t(ChatTranslationKeys.PRIVACY_ABOUT),
                        selection: $store.about,
                        translationService: translationService
                    )
                } label: {
                    LabeledContent(t(ChatTranslationKeys.PRIVACY_ABOUT)) { Text(displayName(for: store.about)) }
                }
            } header: {
                Text(t(ChatTranslationKeys.PRIVACY_PERSONAL_INFO_HEADER))
            }

            Section {
                Toggle(t(ChatTranslationKeys.PRIVACY_READ_RECEIPTS), isOn: $store.readReceipts)
            } footer: {
                Text(t(ChatTranslationKeys.PRIVACY_READ_RECEIPTS_FOOTER))
            }

            Section {
                NavigationLink {
                    PrivacyOptionPicker(
                        title: t(ChatTranslationKeys.PRIVACY_GROUPS),
                        selection: $store.groupAdd,
                        translationService: translationService
                    )
                } label: {
                    LabeledContent(t(ChatTranslationKeys.PRIVACY_GROUPS)) { Text(displayName(for: store.groupAdd)) }
                }
            } header: {
                Text(t(ChatTranslationKeys.PRIVACY_GROUPS_HEADER))
            }

            Section {
                NavigationLink {
                    blockedContactsList
                } label: {
                    Label(t(ChatTranslationKeys.PRIVACY_BLOCKED_CONTACTS), systemImage: "hand.raised")
                }
            }
        }
        .navigationTitle(t(ChatTranslationKeys.PRIVACY_TITLE))
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var blockedContactsList: some View {
        List {
            Text(t(ChatTranslationKeys.PRIVACY_NO_BLOCKED))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
        }
        .navigationTitle(t(ChatTranslationKeys.PRIVACY_BLOCKED_TITLE))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func displayName(for visibility: PrivacyVisibility) -> String {
        t(visibility.translationKey)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Reusable Option Picker

@available(iOS 17.0, *)
struct PrivacyOptionPicker: View {

    let title: String
    @Binding var selection: PrivacyVisibility
    let translationService: (any TranslationServiceProtocol)?
    
    init(title: String, selection: Binding<PrivacyVisibility>, translationService: (any TranslationServiceProtocol)? = nil) {
        self.title = title
        self._selection = selection
        self.translationService = translationService
    }

    var body: some View {
        List {
            ForEach(PrivacyVisibility.allCases, id: \.self) { option in
                Button {
                    selection = option
                } label: {
                    HStack {
                        Text(t(option.translationKey))
                        Spacer()
                        if selection == option {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - AppStorage Extension for Codable

extension AppStorage where Value == PrivacyVisibility {
    init(wrappedValue: PrivacyVisibility, _ key: String) {
        self.init(wrappedValue: wrappedValue, key, store: .standard)
    }

    init(wrappedValue: PrivacyVisibility, _ key: String, store: UserDefaults) {
        let rawDefault = wrappedValue.rawValue
        self.init(wrappedValue: wrappedValue, key)
    }
}
