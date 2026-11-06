import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Composes a poll: a question, between two and twelve options, and whether
/// more than one answer is allowed.
///
/// Owns nothing but its draft. Whether the poll can be sent at all — and what
/// happens to it afterwards — belongs to the room, so this view only reports a
/// finished draft through its callback.
struct PollComposerView: View {

    private enum Limits {
        static let minOptions = 2
        static let maxOptions = 12
    }

    let translationService: (any TranslationServiceProtocol)?
    let onSendPoll: ((_ question: String, _ options: [String], _ allowsMultipleAnswers: Bool) -> Void)?
    let onDismiss: (() -> Void)?

    @State private var question: String = ""
    @State private var options: [PollDraftOption] = [PollDraftOption(), PollDraftOption()]
    @State private var allowsMultipleAnswers: Bool = false
    @FocusState private var focusedOption: UUID?
    @Environment(\.colorScheme) private var colorScheme

    private var trimmedQuestion: String {
        question.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filledOptions: [String] {
        options
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var canSend: Bool {
        !trimmedQuestion.isEmpty && filledOptions.count >= Limits.minOptions
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            List {
                Section(t(ChatTranslationKeys.POLL_SECTION_QUESTION)) {
                    TextField(
                        t(ChatTranslationKeys.POLL_QUESTION_PLACEHOLDER),
                        text: $question,
                        axis: .vertical
                    )
                    .lineLimit(1...3)
                }

                Section(t(ChatTranslationKeys.POLL_SECTION_OPTIONS)) {
                    ForEach($options) { $option in
                        TextField(
                            t(ChatTranslationKeys.POLL_OPTION_PLACEHOLDER),
                            text: $option.text
                        )
                        .focused($focusedOption, equals: option.id)
                        .submitLabel(.next)
                        .onSubmit { appendOption() }
                    }
                    .onMove { source, destination in
                        options.move(fromOffsets: source, toOffset: destination)
                    }
                    // Below the minimum there is nothing to delete — those rows
                    // are what makes it a poll rather than a statement.
                    .onDelete { indexSet in
                        guard options.count - indexSet.count >= Limits.minOptions else { return }
                        options.remove(atOffsets: indexSet)
                    }

                    if options.count < Limits.maxOptions {
                        Button {
                            appendOption()
                        } label: {
                            Text(t(ChatTranslationKeys.POLL_ADD_OPTION))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Toggle(
                        t(ChatTranslationKeys.POLL_ALLOW_MULTIPLE),
                        isOn: $allowsMultipleAnswers
                    )
                    .tint(ChatBubbleStyle.accent(for: colorScheme))
                }
            }
            .listStyle(.insetGrouped)
            .environment(\.editMode, .constant(.active))
        }
        .background(Color(.systemBackground))
    }

    private var header: some View {
        HStack {
            Button(common("cancel")) {
                onDismiss?()
            }
            .foregroundStyle(.primary)

            Spacer()

            Text(t(ChatTranslationKeys.POLL_CREATE_TITLE))
                .font(.headline)

            Spacer()

            Button(t(ChatTranslationKeys.POLL_SEND)) {
                onSendPoll?(trimmedQuestion, filledOptions, allowsMultipleAnswers)
                onDismiss?()
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(canSend ? ChatBubbleStyle.accent(for: colorScheme) : Color.appDisabled)
            .disabled(!canSend)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func appendOption() {
        guard options.count < Limits.maxOptions else { return }
        let option = PollDraftOption()
        options.append(option)
        focusedOption = option.id
    }

    /// The same resolver the rest of this folder uses: the key itself is the
    /// fallback, so a key the translation backend does not carry yet still
    /// renders something rather than nothing.
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

/// A draft option carries its own identity so reordering moves the row rather
/// than the text: keyed by index, a drag would leave the focus and the value on
/// whichever row inherited the position.
private struct PollDraftOption: Identifiable {
    let id = UUID()
    var text: String = ""
}
