//
//  ProfileQuickAction.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


import SwiftUI
import SDWebImageSwiftUI
import WaanguCoreKit

public enum ProfileQuickAction {
    case message, audioCall, videoCall
}

@available(iOS 16.0, *)
public struct ContactQuickProfileSheet: View {
    /// The parts of chat the host turned on: the call buttons exist only with calls.
    @Environment(\.chatEnabledModules) private var enabledModules
    let contact: ContactChannel
    let translationService: (any TranslationServiceProtocol)?
    var onAction: (ProfileQuickAction) -> Void
    public init(
        contact: ContactChannel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAction: @escaping (ProfileQuickAction) -> Void
    ) {
        self.contact = contact
        self.translationService = translationService
        self.onAction = onAction
    }
    public var body: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 8)

            profileImage

            VStack(spacing: 6) {
                Text(
                    ChatDisplayName.text(
                        name: contact.userName,
                        phone: contact.isGroup ? nil : contact.phone,
                        identifiers: [contact.userId, contact.id],
                        translator: translationService
                    )
                )
                .font(.title2.weight(.semibold))
                .lineLimit(1)

                // A group has no phone number of its own, so this line was an
                // empty gap under every group's name.
                if !contact.isGroup {
                    Text(contact.phone)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 36) {
                actionButton(icon: "message.fill", label: common("message", fallback: "Message")) {
                    onAction(.message)
                }
                if enabledModules.contains(.calls) {
                    actionButton(icon: "phone.fill", label: t(ChatTranslationKeys.CALL_AUDIO, fallback: "Audio")) {
                        onAction(.audioCall)
                    }
                    actionButton(icon: "video.fill", label: t(ChatTranslationKeys.CALL_VIDEO, fallback: "Video")) {
                        onAction(.videoCall)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var profileImage: some View {
        if let urlString = contact.image, let url = URL(string: urlString) {
            WebImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                placeholderCircle
            }
            .frame(width: 100, height: 100)
            .clipShape(Circle())
        } else {
            placeholderCircle
        }
    }

    private var placeholderCircle: some View {
        if contact.isGroup {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "person.3.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                }
        }else{
            
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 100, height: 100)
                .overlay {
                    Image(systemName: "person.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.gray)
                }
        }
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .frame(width: 48, height: 48)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
                Text(label)
                    .font(.caption)
            }
            .foregroundStyle(.primary)
        }
    }

    private func t(_ key: String, fallback: String) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE
        ).value ?? fallback
    }

    private func common(_ key: String, fallback: String) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? fallback
    }
}
