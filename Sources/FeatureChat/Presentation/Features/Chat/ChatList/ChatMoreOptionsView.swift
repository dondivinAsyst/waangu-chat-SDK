//
//  ChatMoreOptionsView.swift
//  Pods
//
//  Created by Asyst on 8/5/25.
//


import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

enum ChatMenuActions: String, CaseIterable, Identifiable {
    case mute, contactInfo, lockChat, clearChat, deleteChat, blockChat

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .mute: return "arrowshape.turn.up.left"
        case .contactInfo: return "paperplane"
        case .lockChat: return "doc.on.doc"
        case .clearChat: return "trash"
        case .deleteChat: return "xmark"
        case .blockChat: return "person.fill"
        }
    }

    func label(using translationService: (any TranslationServiceProtocol)?) -> String {
        switch self {
        case .mute:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_MUTE, module: ChatTranslationKeys.MODULE).value ?? "Mute"
        case .contactInfo:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_CONTACT_INFO, module: ChatTranslationKeys.MODULE).value ?? "Contact info"
        case .lockChat:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_LOCK_CHAT, module: ChatTranslationKeys.MODULE).value ?? "Lock chat"
        case .clearChat:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_CLEAR_CHAT, module: ChatTranslationKeys.MODULE).value ?? "Clear chat"
        case .deleteChat:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_DELETE_CHAT, module: ChatTranslationKeys.MODULE).value ?? "Delete chat"
        case .blockChat:
            return translationService?.resolve(key: ChatTranslationKeys.CHAT_MORE_BLOCK_USER, module: ChatTranslationKeys.MODULE).value ?? "Block user"
        }
    }
}

struct ChatMoreOptionsView: View {
    var item: DiscussionChatItem
    var onDelete: () -> Void
    var onCancel: () -> Void
    let translationService: (any TranslationServiceProtocol)? = nil

    private let normalActions: [ChatMenuActions] = [.mute, .contactInfo, .lockChat, .clearChat]
    private let destructiveActions: [ChatMenuActions] = [.deleteChat, .blockChat]

    var body: some View {
        VStack(spacing: 16) {

            // Header utilisateur
            HStack {
                RemoteImageView(urlString: item.contact?.image ?? "", fallBack: "")
                    .clipShape(Circle())
                Text(item.contact?.userName ?? "")
                    .font(.headline)
                Spacer()
            }
            .padding(.vertical, 8)

            // Section normale
            actionGroupView(actions: normalActions, backgroundColor: Color(.systemBackground))

            // Section destructive
            actionGroupView(actions: destructiveActions, backgroundColor: Color(.systemGray6))
        }
        .padding(.horizontal, 16)
        .background(Color(.systemGroupedBackground))
    }

    private func actionGroupView(actions: [ChatMenuActions], backgroundColor: Color) -> some View {
        VStack(spacing: 0) {
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                buttonBody(action)

                if index != actions.count - 1 {
                    Divider()
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(backgroundColor)
                .shadow(color: Color(.label).opacity(0.08), radius: 5, x: 0, y: 2)
        )
    }

    private func buttonBody(_ action: ChatMenuActions) -> some View {
        Button(role: action == .blockChat || action == .deleteChat ? .destructive : nil) {
            if action == .deleteChat {
                onDelete()
            } else if action == .blockChat {
                // logique blocage
            }
        } label: {
            HStack {
                Text(action.label(using: translationService))
                Spacer()
                Image(systemName: action.systemImage)
            }
            .padding()
        }
        .frame(height: 45)
    }
}






