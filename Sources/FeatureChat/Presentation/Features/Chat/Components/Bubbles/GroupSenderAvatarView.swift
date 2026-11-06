//
//  GroupSenderAvatarView.swift
//  FeatureChat
//

import SwiftUI

/// The face at the foot of a run of group messages.
///
/// Sized to the gutter every received bubble in a group thread is indented by,
/// so bubbles stay aligned whether or not this row is the one that draws it.
struct GroupSenderAvatarView: View {
    let imageUrl: String?
    let fallbackName: String

    static let diameter: CGFloat = 32

    /// Width of the gutter reserved on the leading edge of received group rows.
    ///
    /// Exactly the avatar, no slack: every bubble already sets its own leading
    /// padding, and that is the only gap wanted between the face and the bubble.
    static let gutterWidth: CGFloat = Self.diameter

    var body: some View {
        Group {
            if let imageUrl, !imageUrl.isEmpty {
                CircularProfileImageView(imageUrl, size: .custom(Self.diameter))
            } else {
                initialsAvatar
            }
        }
        .frame(width: Self.diameter, height: Self.diameter)
    }

    /// Shown when the sender has no picture, and when they have left the group —
    /// they are off the roster by then, but their messages are still in the thread.
    private var initialsAvatar: some View {
        Circle()
            .fill(Color(.systemGray4))
            .overlay {
                Text(initial)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
            }
    }

    private var initial: String {
        let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }
}
