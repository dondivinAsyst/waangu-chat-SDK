//
//  CallRedialSheet.swift
//  FeatureChat
//
//  Tapping a call in a conversation opens this: who was on that call, and a
//  choice of voice or video to place it again.
//
//  It exists because a group call is otherwise unrepeatable — the user would
//  have to remember and re-pick everyone. The roster comes from the call message
//  itself, so it is whoever was actually on that call, not whoever is in the
//  conversation now.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallRedialSheet: View {

    let participants: [CallInvitee]
    let avatars: [String?]
    let translationService: (any TranslationServiceProtocol)?
    let onCall: (_ hasVideo: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    private var names: String {
        participants.map(\.name).joined(separator: ", ")
    }

    var body: some View {
        VStack(spacing: 20) {
            Capsule()
                .fill(Color.secondary.opacity(0.4))
                .frame(width: 40, height: 5)
                .padding(.top, 8)

            participantRow

            HStack(spacing: 12) {
                callButton(
                    icon: "phone.fill",
                    label: t(ChatTranslationKeys.CALLS_VOICE),
                    isPrimary: false,
                    action: { place(hasVideo: false) }
                )

                callButton(
                    icon: "video.fill",
                    label: t(ChatTranslationKeys.CALLS_VIDEO),
                    isPrimary: true,
                    action: { place(hasVideo: true) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .presentationDetents([.height(230)])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Roster

    private var participantRow: some View {
        HStack(spacing: 12) {
            avatarCluster

            VStack(alignment: .leading, spacing: 2) {
                Text(names)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(2)

                // Omitted when it would only repeat the line above: with no
                // name to show, the title is already this number.
                if let subtitle, subtitle != names {
                    Text(subtitle)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
        )
        .padding(.horizontal, 16)
    }

    private var subtitle: String? {
        guard participants.count == 1 else {
            return t(ChatTranslationKeys.CALLS_PARTICIPANT_COUNT, args: ["\(participants.count)"])
        }
        guard let phone = participants.first?.phone, !phone.isEmpty else { return nil }
        return PhoneNumberFormatter.format(phone)
    }

    /// Up to three faces, overlapped — enough to recognise the group without
    /// turning the row into a list.
    private var avatarCluster: some View {
        HStack(spacing: -14) {
            ForEach(Array(avatars.prefix(3).enumerated()), id: \.offset) { _, avatar in
                CircularProfileImageView(avatar, size: .custom(38))
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
        }
        .frame(width: 48, alignment: .leading)
    }

    // MARK: - Actions

    private func place(hasVideo: Bool) {
        dismiss()
        onCall(hasVideo)
    }

    private func callButton(
        icon: String,
        label: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.system(size: 17, weight: .semibold))
            }
            .foregroundColor(isPrimary ? .white : .primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    // The app's primary, not the in-call accept green: that
                    // green means "answer the call ringing at you", and this
                    // button places a new one.
                    .fill(isPrimary
                          ? AppColors.primary
                          : Color.secondary.opacity(0.15))
            )
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
