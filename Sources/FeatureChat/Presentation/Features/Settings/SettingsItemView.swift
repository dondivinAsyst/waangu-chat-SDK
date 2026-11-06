//
//  SettingsItemView.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 8.01.2025.
//

import SwiftUI
import WaanguCoreKit

struct SettingsItemView: View {
    let item: SettingsItem
    let translationService: (any TranslationServiceProtocol)?

    init(
        item: SettingsItem,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.item = item
        self.translationService = translationService
    }
    
    var body: some View {
        HStack {
            iconImageView()
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)
                .background(item.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            
            Text(t(item.titleKey))
                .font(.system(size: 18))
            
            Spacer()
            
            if item.isArrow {
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func iconImageView() -> some View {
        switch item.imageType {
        case .systemImage:
            Image(systemName: item.imageName)
                .font(.callout)
                .foregroundColor(item.imageColor)
        case .assetImage:
            Image(item.imageName)
                .renderingMode(.template)
                .padding(3)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

#Preview {
    SettingsItemView(item: .chats)
}
