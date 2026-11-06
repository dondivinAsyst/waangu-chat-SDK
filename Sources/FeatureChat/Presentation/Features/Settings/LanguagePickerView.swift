//
//  LanguagePickerView.swift
//  FeatureChat
//
//  Mirrors WhatsApp's Settings → Chats → App Language screen exactly:
//  - Large title "App Language"
//  - Each row: flag  |  display name + locale code  |  checkmark on selected
//  - Selection applies immediately on tap (no confirm button needed)
//  - The screen stays open afterwards, redrawn in the language just chosen
//

import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct LanguagePickerView: View {

    // MARK: - State

    @State private var selected: AppLanguage
    /// Bumped on locale change so this screen's own strings re-resolve.
    ///
    /// It stays on screen after a selection, so its title and footer have to
    /// follow the language just picked — otherwise the one screen showing the
    /// change is the one that doesn't reflect it.
    @State private var localeToken = 0
    let translationService: (any TranslationServiceProtocol)?

    // MARK: - Callback

    /// Called the instant the user taps a language row.
    let onLanguageSelected: (AppLanguage) -> Void

    // MARK: - Init

    init(
        currentLanguage: AppLanguage,
        translationService: (any TranslationServiceProtocol)? = nil,
        onLanguageSelected: @escaping (AppLanguage) -> Void
    ) {
        self._selected = State(initialValue: currentLanguage)
        self.translationService = translationService
        self.onLanguageSelected = onLanguageSelected
    }

    // MARK: - Body

    var body: some View {
        List {
            Section {
                ForEach(AppLanguage.allCases, id: \.rawValue) { language in
                    languageRow(language)
                }
            } footer: {
                Text(t(ChatTranslationKeys.SETTINGS_LANGUAGE_FOOTER))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .id(localeToken)
        .navigationTitle(t(ChatTranslationKeys.SETTINGS_LANGUAGE_TITLE))
        .navigationBarTitleDisplayMode(.large)
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("TranslationKit.localeDidChange")
            )
        ) { _ in
            localeToken += 1
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func languageRow(_ language: AppLanguage) -> some View {
        Button {
            guard selected != language else { return }
            selected = language
            // Applies and stays. Leaving is the back button's job — which is
            // what was actually broken: the list that pushed this screen was
            // rebuilt by the language change, and the push went with it.
            onLanguageSelected(language)
        } label: {
            HStack(spacing: 14) {
                // Flag
                Text(language.flagEmoji)
                    .font(.title2)

                // Language name + locale code
                VStack(alignment: .leading, spacing: 2) {
                    Text(language.displayName)
                        .foregroundStyle(.primary)
                        .font(.system(size: 17))
                    Text(language.rawValue.uppercased())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Checkmark — visible on the currently selected language
                if selected == language {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
