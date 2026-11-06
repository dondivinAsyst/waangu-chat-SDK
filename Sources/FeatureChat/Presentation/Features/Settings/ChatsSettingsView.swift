//
//  ChatsSettingsView.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ChatsSettingsView: View {

    let translationService: (any TranslationServiceProtocol)?

    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @State private var localeToken = 0
    @State private var preferredTimeFormat = ChatTimeFormatting.preferredFormat

    var body: some View {
        List {
            Section {
                Picker(
                    t(ChatTranslationKeys.SETTINGS_TIME_FORMAT),
                    selection: $preferredTimeFormat
                ) {
                    ForEach(ChatTimeFormat.allCases, id: \.self) { format in
                        Text(format.displayName(translationService: translationService))
                            .tag(format)
                    }
                }
                .onChange(of: preferredTimeFormat) { newValue in
                    ChatTimeFormatting.preferredFormat = newValue
                }
            } footer: {
                Text(t(ChatTranslationKeys.SETTINGS_TIME_FORMAT_FOOTER))
            }

            Section {
                NavigationLink {
                    ChatAppearancePickerView(
                        translationService: translationService
                    )
                } label: {
                    LabeledContent(
                        t(ChatTranslationKeys.SETTINGS_CHAT_APPEARANCE),
                        value: appearanceStore.defaultAppearance.displayName(translationService: translationService)
                    )
                }
            } footer: {
                Text(t(ChatTranslationKeys.SETTINGS_CHAT_APPEARANCE_FOOTER))
            }

            if #available(iOS 17.0, *) {
                Section {
                    NavigationLink {
                        MediaAutoDownloadSettingsView(translationService: translationService)
                    } label: {
                        Text(t(ChatTranslationKeys.MEDIA_AUTO_DOWNLOAD_TITLE))
                    }
                }
            }
        }
        .id(localeToken)
        .navigationTitle(t(ChatTranslationKeys.SETTINGS_CHATS_MENU))
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("TranslationKit.localeDidChange")
            )
        ) { _ in
            localeToken += 1
        }
        .onReceive(appearanceStore.objectWillChange) { _ in
            localeToken += 1
        }
        .onAppear {
            appearanceStore.reloadFromPersistence()
            preferredTimeFormat = ChatTimeFormatting.preferredFormat
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ChatTimeFormatting.didChangeNotification)
        ) { _ in
            preferredTimeFormat = ChatTimeFormatting.preferredFormat
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
