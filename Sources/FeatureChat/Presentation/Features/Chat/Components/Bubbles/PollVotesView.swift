//
//  PollVotesView.swift
//  FeatureChat
//
//  Who voted for what. One section per option, each listing its voters.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

struct PollVotesView: View {

    let poll: PollContent
    /// Resolves a voter id to something printable. Injected rather than reached
    /// for, because the answer comes from the group roster in a group thread and
    /// from the room's other party in a direct one — neither of which this view
    /// should know about.
    let voterDisplay: (String) -> (name: String, avatar: String?)
    let translationService: (any TranslationServiceProtocol)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    /// The most-voted options, marked with a star. A tie stars every option that
    /// shares the lead, since none of them is more the winner than the others.
    private var leadingOptionIds: Set<String> {
        let top = poll.options.map(\.voterIds.count).max() ?? 0
        guard top > 0 else { return [] }
        return Set(poll.options.filter { $0.voterIds.count == top }.map(\.id))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    questionCard

                    ForEach(poll.options) { option in
                        if !option.voterIds.isEmpty {
                            optionSection(option)
                        }
                    }
                }
                .padding(16)
            }
        }
        .background(Color.appGroupedBackground)
    }

    private var header: some View {
        ZStack {
            Text(t(ChatTranslationKeys.POLL_VOTES_TITLE))
                .font(.headline)

            HStack {
                Button(common("close")) {
                    dismiss()
                }
                .foregroundStyle(.primary)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var questionCard: some View {
        Text(poll.question)
            .font(.system(size: 16, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func optionSection(_ option: PollOption) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text(option.text)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text(t(
                    ChatTranslationKeys.POLL_VOTES_FOR_OPTION,
                    args: ["\(option.voterIds.count)"]
                ))
                .font(.system(size: 14))
                .foregroundStyle(.secondary)

                if leadingOptionIds.contains(option.id) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(ChatBubbleStyle.accent(for: colorScheme))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            ForEach(option.voterIds, id: \.self) { voterId in
                Divider().padding(.leading, 60)
                voterRow(voterId)
            }
        }
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func voterRow(_ voterId: String) -> some View {
        let display = voterDisplay(voterId)
        return HStack(spacing: 12) {
            PollVoterAvatar(name: display.name, avatar: display.avatar, size: 32)

            Text(display.name)
                .font(.system(size: 16))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
