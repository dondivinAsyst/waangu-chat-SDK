import SwiftUI
import WaanguCoreKit

@available(iOS 17.0, *)
struct ChatInAppSearchView: View {
    @ObservedObject var viewModel: ChatRoomViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [MessageDataItem] {
        viewModel.messagesMatchingSearch(query)
    }

    var body: some View {
        NavigationStack {
            Group {
                if trimmedQuery.isEmpty {
                    ContentUnavailableView(
                        t(ChatTranslationKeys.CHAT_SEARCH_MESSAGES),
                        systemImage: "magnifyingglass",
                        description: Text(t(ChatTranslationKeys.CHAT_SEARCH_MESSAGES_DESC))
                    )
                } else if results.isEmpty {
                    ContentUnavailableView(
                        t(ChatTranslationKeys.CHAT_SEARCH_NO_RESULTS),
                        systemImage: "text.magnifyingglass",
                        description: Text(t(ChatTranslationKeys.CHAT_SEARCH_TRY_ANOTHER))
                    )
                } else {
                    List {
                        ForEach(results) { msg in
                            Button {
                                viewModel.scrollToMessage = msg.id
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(msg.message.text)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                        .lineLimit(3)
                                    Text(msg.displayTime)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(t(ChatTranslationKeys.CHAT_SEARCH_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: t(ChatTranslationKeys.CHAT_SEARCH_IN_CONVERSATION))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("done")) { dismiss() }
                }
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
