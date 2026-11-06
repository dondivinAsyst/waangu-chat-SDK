//
//  MessageStickyHeaderSwiftUIView.swift
//  Pods
//
//  Created by Don divin on 2/6/26.
//


import SwiftUI
import WaanguCoreKit

// MARK: - Message Sticky Header

@available(iOS 16.0, *)
struct MessageStickyHeaderSwiftUIView: View {
    let date: String
    
    var body: some View {
        Text(date)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.systemBackground).opacity(0.92))
            .cornerRadius(12)
//            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }
    
//    private var formattedDate: String {
//        let formatter = DateFormatter()
//        
//        if Calendar.current.isDateInToday(date) {
//            return "Today"
//        } else if Calendar.current.isDateInYesterday(date) {
//            return "Yesterday"
//        } else {
//            formatter.dateStyle = .medium
//            return formatter.string(from: date)
//        }
//    }
}


// MARK: - Text Input Toolbar

@available(iOS 16.0, *)
struct TextInputToolbarSwiftUIView: View {
    @State private var messageText: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    var onSendMessage: ((String) -> Void)?
    var onPresentSheet: (() -> Void)?
    var onTextChanged: ((String) -> Void)?
    let translationService: (any TranslationServiceProtocol)? = nil
    
    var body: some View {
        HStack(spacing: 12) {
            // Attach button
            Button(action: {
                onPresentSheet?()
            }) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            
            // Text field
            HStack(spacing: 8) {
                TextField(t(ChatTranslationKeys.CALLS_MESSAGE), text: $messageText, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.plain)
                    .focused($isTextFieldFocused)
                    .onChange(of: messageText) { newValue in
                        onTextChanged?(newValue)
                    }
                
                if !messageText.isEmpty {
                    Button(action: clearText) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(20)
            
            // Send button
            Button(action: sendMessage) {
                Image(systemName: messageText.isEmpty ? "mic.fill" : "arrow.up.circle.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func sendMessage() {
        guard !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        onSendMessage?(messageText)
        messageText = ""
    }
    
    private func clearText() {
        messageText = ""
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Reaction Picker

@available(iOS 16.0, *)
struct ReactionPickerSwiftUIView: View {
    let message: MessageDataItem
    let onReactionSelected: (String) -> Void
    
    private let reactions = ["❤️", "👍", "😂", "😮", "😢", "🙏"]
    
    var body: some View {
        HStack(spacing: 16) {
            ForEach(reactions, id: \.self) { emoji in
                Button(action: {
                    Haptic.impact(.light)
                    onReactionSelected(emoji)
                }) {
                    Text(emoji)
                        .font(.title)
                        .scaleEffect(1.0)
                }
                .buttonStyle(ReactionButtonStyle())
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Material.regular)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
}

struct ReactionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.3 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Message Menu

@available(iOS 16.0, *)
struct MessageMenuSwiftUIView: View {
    let message: MessageDataItem
    let onActionSelected: (MessageMenuAction) -> Void
    let translationService: (any TranslationServiceProtocol)?

    init(
        message: MessageDataItem,
        translationService: (any TranslationServiceProtocol)? = nil,
        onActionSelected: @escaping (MessageMenuAction) -> Void
    ) {
        self.message = message
        self.translationService = translationService
        self.onActionSelected = onActionSelected
    }
    
    var body: some View {
        VStack(spacing: 0) {
            menuButton(title: t(ChatTranslationKeys.MENU_REPLY), icon: "arrowshape.turn.up.left", action: .reply)
            Divider()
            menuButton(title: t(ChatTranslationKeys.MENU_FORWARD), icon: "arrowshape.turn.up.right", action: .forward)
            Divider()
            menuButton(title: t(ChatTranslationKeys.MENU_COPY), icon: "doc.on.doc", action: .copy)
            Divider()
            menuButton(title: t(ChatTranslationKeys.MENU_DELETE), icon: "trash", action: .delete, isDestructive: true)
        }
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Material.regular)
                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
    }
    
    private func menuButton(
        title: String,
        icon: String,
        action: MessageMenuAction,
        isDestructive: Bool = false
    ) -> some View {
        Button(action: {
            Haptic.impact(.light)
            onActionSelected(action)
        }) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundColor(isDestructive ? .red : .blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(isDestructive ? .red : .primary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Message Action Enum




