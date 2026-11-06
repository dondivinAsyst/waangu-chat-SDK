import SwiftUI
import WaanguCoreKit

// MARK: - Timestamp + delivery status overlay (WhatsApp-style)

struct BubbleMetaOverlay: View {
    enum Style {
        case bubble(colorScheme: ColorScheme)
        case media
    }

    let createdAt: Date
    let messageStatus: MessageStatus?
    let isEdited: Bool
    let style: Style
    let translationService: (any TranslationServiceProtocol)?

    @State private var timeFormatToken = 0

    init(
        message: MessageDataItem,
        style: Style,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        createdAt = message.createdAt
        // Call records carry no send lifecycle — never show ticks for them.
        let carriesDeliveryState = message.direction == .sent && !message.typeMessage.isSystemRecord
        messageStatus = carriesDeliveryState ? message.status : nil
        isEdited = message.isEdited
        self.style = style
        self.translationService = translationService
    }

    var body: some View {
        HStack(spacing: 2) {
            if isEdited {
                Text(editedLabel)
                    .font(.caption2)
                    .fontWeight(isMediaStyle ? .bold : .regular)
            }
            Text(ChatTimeFormatting.formatTime(createdAt))
                .font(.caption2)
                .fontWeight(isMediaStyle ? .bold : .regular)
            if let messageStatus {
                MessageStatusIcon(messageStatus: messageStatus)
            }
        }
        .foregroundColor(foregroundColor)
        .padding(.horizontal, isMediaStyle ? 6 : 0)
        .padding(.vertical, isMediaStyle ? 4 : 0)
        .background {
            if isMediaStyle {
                Color.black.opacity(0.4)
                    .clipShape(Capsule())
            }
        }
        .padding(isMediaStyle ? 4 : 0)
        .id(timeFormatToken)
        .onReceive(
            NotificationCenter.default.publisher(for: ChatTimeFormatting.didChangeNotification)
        ) { _ in
            timeFormatToken += 1
        }
    }

    private var isMediaStyle: Bool {
        if case .media = style { return true }
        return false
    }

    private var foregroundColor: Color {
        switch style {
        case .bubble(let colorScheme):
            return ChatBubbleStyle.secondaryForeground(for: colorScheme)
        case .media:
            return .white
        }
    }

    private var editedLabel: String {
        translationService?
            .resolve(
                key: ChatTranslationKeys.MESSAGE_EDITED,
                module: ChatTranslationKeys.MODULE
            )
            .value ?? "Edited"
    }
}

// MARK: - Caption text with bottom-trailing meta (no extra layout row)

struct BubbleCaptionWithMeta: View {
    let text: String
    let message: MessageDataItem
    let colorScheme: ColorScheme
    var horizontalPadding: CGFloat = 5
    var verticalPadding: CGFloat = 0
    var trailingReserve: CGFloat = 72

    var body: some View {
        Text(text)
            .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
            .padding(.trailing, trailingReserve)
            .padding(.bottom, 2)
            .overlay(alignment: .bottomTrailing) {
                BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme))
                    .padding(.trailing, 4)
                    .padding(.bottom, 2)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
    }
}
