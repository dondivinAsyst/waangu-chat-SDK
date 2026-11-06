//
//  MessageMenuView.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit

struct MessageMenuView: View {

    private var message: MessageDataItem?
    private var media: [MessageDataItem]?
    private let translator: (any TranslationServiceProtocol)?

    @State private var animateBackgroundView = false
    let onTapHandler: ((_ action: MessageMenuAction) -> Void)

    init(
        row: MessageRow,
        translator: (any TranslationServiceProtocol)? = nil,
        onTapHandler: @escaping ((_ action: MessageMenuAction) -> Void)
    ) {
        switch row {
        case .mediaGroup(_, let msg):
            self.media = msg
        case .message(let msg):
            self.message = msg
        case .checkpoint, .encryptionBanner, .groupIntro:
            self.message = nil
            self.media = nil
        }
        self.translator = translator
        self.onTapHandler = onTapHandler
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(MessageMenuAction.menuActions(for: message)) { action in
                buttonBody(action)
                    .frame(height: 45)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(action == .delete ? .red : .primary)

                if action != .delete {
                    Divider()
                }
            }
        }
        .frame(width: message?.imageWidth ?? 200)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .scaleEffect(animateBackgroundView ? 1 : 0, anchor: message?.menuAnchor ?? .center)
        .opacity(animateBackgroundView ? 1 : 0)
        .shadow(color: .gray.opacity(0.2), radius: 4, x: 0, y: 2)
        .onAppear {
            withAnimation(.easeIn(duration: 0.2)) {
                animateBackgroundView = true
            }
        }
    }

    private func buttonBody(_ action: MessageMenuAction) -> some View {
        Button {
            onTapHandler(action)
        } label: {
            HStack {
                // Use translator if available, otherwise fall back to capitalised rawValue
                let label: String = {
                    if let t = translator {
                        return t.resolve(key: action.translationKey, module: ChatTranslationKeys.MODULE).value
                    }
                    return action.translationKey.replacingOccurrences(of: "_", with: " ").capitalized
                }()
                Text(label)
                Spacer()
                Image(systemName: action.systemImage)
            }
            .padding()
        }
    }
}
