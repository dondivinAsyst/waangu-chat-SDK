//
//  ChatAppearancePickerView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ChatAppearancePickerView: View {

    let translationService: (any TranslationServiceProtocol)?

    @ObservedObject private var store = ChatAppearanceStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var localeToken = 0

    var body: some View {
        List {
            ForEach(ChatAppearancePreference.allCases) { pref in
                Button {
                    store.apply(pref)
                    dismiss()
                } label: {
                    HStack {
                        Text(pref.displayName(translationService: translationService))
                            .foregroundStyle(.primary)
                        Spacer()
                        if store.defaultAppearance == pref {
                            Image(systemName: "checkmark")
                                .foregroundStyle(AppColors.primary)
                        }
                    }
                }
            }
        }
        .id(localeToken)
        .navigationTitle(t(ChatTranslationKeys.CONTACT_INFO_CHAT_APPEARANCE))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(common("done")) {
                    dismiss()
                }
            }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("TranslationKit.localeDidChange")
            )
        ) { _ in
            localeToken += 1
        }
        .onAppear {
            store.reloadFromPersistence()
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
