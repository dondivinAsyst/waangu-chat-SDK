import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Read-only group summary shown in chat (empty state) and group info.
@available(iOS 17.0, *)
struct GroupChatIntroHeaderView: View {
    let name: String
    let description: String?
    let memberCount: Int
    let avatarUrl: String?
    var showsLeftGroupNotice: Bool = false
    var showsEditButton: Bool = false
    var showsCardBackground: Bool = false
    var onEditTapped: (() -> Void)?
    var translationService: (any TranslationServiceProtocol)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if showsLeftGroupNotice {
                Label(t(ChatTranslationKeys.GROUP_LEFT_NOTICE), systemImage: "info.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            groupAvatar

            Text(name)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            if let description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Text(t(ChatTranslationKeys.GROUP_PARTICIPANTS_COUNT, args: ["\(memberCount)", memberCount == 1 ? "" : "s"]))
                .font(.caption)
                .foregroundStyle(.secondary)

            if showsEditButton, let onEditTapped {
                Button(action: onEditTapped) {
                    Label(t(ChatTranslationKeys.GROUP_EDIT_INFO), systemImage: "pencil")
                        .font(.subheadline)
                        .foregroundStyle(AppColors.primary)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, showsCardBackground ? 24 : 0)
        .padding(.horizontal, showsCardBackground ? 20 : 0)
        .background {
            if showsCardBackground {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 12, y: 4)
            }
        }
    }

    @ViewBuilder
    private var groupAvatar: some View {
        if let avatarUrl, !avatarUrl.isEmpty {
            CircularProfileImageView(avatarUrl, size: .large)
                .frame(width: 80, height: 80)
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 80, height: 80)
                .overlay {
                    Image(systemName: "person.3.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
