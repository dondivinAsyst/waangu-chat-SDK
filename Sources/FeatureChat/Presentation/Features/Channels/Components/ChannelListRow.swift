//
//  ChannelListRow.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// A channel in the Updates tab or the explore list.
///
/// The follow button is offered even for a channel with no conversation — the
/// subscription is Identity's business — but the row is dimmed and cannot be
/// opened, because there is nothing to open.
@available(iOS 16.0, *)
struct ChannelListRow: View {

    let channel: Channel
    let translationService: (any TranslationServiceProtocol)?
    let onToggleSubscription: () -> Void
    /// Hides a suggestion the user is not interested in. Nil in the lists where
    /// dismissing makes no sense.
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(channel.image, size: .small)

            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onToggleSubscription) {
                Text(channel.isSubscribed
                     ? t(ChatTranslationKeys.CHANNELS_FOLLOWING)
                     : t(ChatTranslationKeys.CHANNELS_FOLLOW))
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        channel.isSubscribed
                            ? Color(.systemGray5)
                            : AppColors.primary.opacity(0.15)
                    )
                    .foregroundStyle(channel.isSubscribed ? Color.secondary : AppColors.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t(ChatTranslationKeys.CHANNELS_DISMISS_SUGGESTION))
            }
        }
        .opacity(channel.isOpenable ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    private var subtitle: String {
        channel.isOpenable
            ? t(ChatTranslationKeys.CHANNELS_FOLLOWER_COUNT, args: [Self.compact(channel.subscriberCount)])
            : t(ChatTranslationKeys.CHANNELS_NOT_READY)
    }

    /// 169000 reads as 169K. A directory row has room for a magnitude, not a
    /// figure.
    static func compact(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.maximumFractionDigits = count < 10_000 ? 0 : 1

        switch count {
        case ..<1_000:
            return "\(count)"
        case ..<1_000_000:
            return (formatter.string(from: NSNumber(value: Double(count) / 1_000)) ?? "\(count)") + "K"
        default:
            return (formatter.string(from: NSNumber(value: Double(count) / 1_000_000)) ?? "\(count)") + "M"
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
