//
//  ChannelCreationTextView.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 19.01.2025.
//

import SwiftUI
import WaanguCoreKit

struct ChannelCreationTextView: View {
    @Environment(\.colorScheme) private var colorScheme
    let translationService: (any TranslationServiceProtocol)? = nil
    
    private var backgroundColor: Color {
        colorScheme == .dark ? Color(.secondarySystemBackground) : Color.yellow.opacity(0.35)
    }
    
    var body: some View {
        ZStack(alignment: .top) {
            (
                Text(Image(systemName: "lock.fill"))
                    +
                Text(" " + (translationService?.resolve(key: ChatTranslationKeys.E2EE_BANNER, module: ChatTranslationKeys.MODULE).value ?? "Messages and calls are end-to-end encrypted."))
                    +
                Text(" " + (translationService?.resolve(key: ChatTranslationKeys.COMMON_LEARN_MORE, module: ChatTranslationKeys.COMMON_MODULE).value ?? "Learn more"))
                    .bold()
            )
        }
        .font(.footnote)
        .foregroundStyle(.primary)
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(backgroundColor.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .padding(.horizontal, 30)
    }
}

#Preview {
    ChannelCreationTextView()
}
