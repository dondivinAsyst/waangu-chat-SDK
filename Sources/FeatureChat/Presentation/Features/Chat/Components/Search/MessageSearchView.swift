import SwiftUI
import WaanguCoreKit
import Combine

// MARK: - Search Result

struct MessageSearchResult: Identifiable, Equatable {
    let id: String
    let message: MessageDataItem
    let conversationId: String
    let contactName: String?
    let matchedText: String

    static func == (lhs: MessageSearchResult, rhs: MessageSearchResult) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Search ViewModel

@MainActor
final class MessageSearchViewModel: ObservableObject {

    @Published var searchText = ""
    @Published var results: [MessageSearchResult] = []
    @Published var isSearching = false
    @Published var currentInChatIndex = 0
    @Published var inChatResults: [MessageDataItem] = []

    private let searchableStore: any SearchableDatabaseProtocol
    private let fieldCrypto: any FieldEncryptionServiceProtocol

    init(searchableStore: any SearchableDatabaseProtocol, fieldCrypto: any FieldEncryptionServiceProtocol) {
        self.searchableStore = searchableStore
        self.fieldCrypto = fieldCrypto
    }

    // MARK: - Global Search (across all chats)

    func searchAllChats() {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            results = []
            return
        }

        isSearching = true

        Task { @MainActor in
            let matched = await performGRDBSearch(query: query)
            results = matched
            isSearching = false
        }
    }

    private func performGRDBSearch(query: String) async -> [MessageSearchResult] {
        do {
            // Un message supprimé — pour tous ou pour moi — ne revient pas par la
            // recherche : la suppression garde `content`, seul `searchText` est vidé (B44).
            let messagesQuery = QuerySpec(
                filter: FilterSpec("is_deleted == %@", .bool(false)),
                sort: [SortSpec("timestamp", ascending: false)],
                limit: 500
            )
            let messages = try await searchableStore.fetch(
                MessageModel.self,
                query: messagesQuery
            )

            return messages.compactMap { msg -> MessageSearchResult? in
                let rawText = msg.content.text ?? ""
                let decryptedText = fieldCrypto.decrypt(rawText)
                guard decryptedText.localizedCaseInsensitiveContains(query) else { return nil }

                let conversationId = msg.conversationId
                let messageItem = MessageDataItem(
                    codeMessage: msg.id,
                    senderId: msg.senderId,
                    senderAvatar: nil,
                    senderPhone: "",
                    senderName: fieldCrypto.decrypt(msg.senderName),
                    receiverId: "",
                    groupId: conversationId,
                    typeMessage: mapType(msg.type),
                    message: MessageContent(text: decryptedText),
                    status: mapStatus(msg.deliveryStatus),
                    createdAt: msg.timestamp
                )

                return MessageSearchResult(
                    id: msg.id,
                    message: messageItem,
                    conversationId: conversationId,
                    contactName: fieldCrypto.decrypt(msg.senderName),
                    matchedText: decryptedText
                )
            }
            .prefix(100)
            .map { $0 }
        } catch {
            return []
        }
    }

    private func mapType(_ type: MessageTypeModel) -> MessageTypeProps {
        switch type {
        case .text:       return .TEXT
        case .image:      return .IMAGE
        case .video:      return .VIDEO
        case .videoNote:  return .VIDEO_NOTE
        case .audio:      return .AUDIO
        case .voice:      return .VOICE
        case .document:   return .DOCUMENT
        case .location:   return .LOCATION
        case .contact:    return .CONTACT
        case .payment:    return .ISMONEY
        case .status:     return .STATUS
        case .missedCall: return .MISSING_CALL_AUDIO
        default:          return .TEXT
        }
    }

    private func mapStatus(_ status: MessageDeliveryStatusModel) -> MessageStatus {
        switch status {
        case .pending:   return .PENDING
        case .sent:      return .SENT
        case .delivered: return .DELIVERED
        case .read:      return .SEEN
        case .failed:    return .FAILED
        }
    }

    // MARK: - In-Chat Search

    func searchInChat(messages: [MessageDataItem]) {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            inChatResults = []
            currentInChatIndex = 0
            return
        }

        inChatResults = messages.filter {
            ($0.message.text ?? "").localizedCaseInsensitiveContains(query)
        }
        currentInChatIndex = inChatResults.isEmpty ? 0 : inChatResults.count - 1
    }

    func nextResult() {
        guard !inChatResults.isEmpty else { return }
        currentInChatIndex = (currentInChatIndex + 1) % inChatResults.count
    }

    func previousResult() {
        guard !inChatResults.isEmpty else { return }
        currentInChatIndex = (currentInChatIndex - 1 + inChatResults.count) % inChatResults.count
    }

    var currentResultMessage: MessageDataItem? {
        guard !inChatResults.isEmpty,
              currentInChatIndex < inChatResults.count else { return nil }
        return inChatResults[currentInChatIndex]
    }

    func clearSearch() {
        searchText = ""
        results = []
        inChatResults = []
        currentInChatIndex = 0
        isSearching = false
    }
}

// MARK: - Global Search View

@available(iOS 17.0, *)
struct MessageSearchView: View {

    @StateObject private var viewModel: MessageSearchViewModel
    let translationService: (any TranslationServiceProtocol)?
    let onSelectResult: (MessageSearchResult) -> Void

    init(
        viewModel: MessageSearchViewModel,
        onSelectResult: @escaping (MessageSearchResult) -> Void,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.onSelectResult = onSelectResult
        self.translationService = translationService
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            resultsList
        }
        .navigationTitle(t(ChatTranslationKeys.MESSAGE_SEARCH_TITLE))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(t(ChatTranslationKeys.CHAT_SEARCH_MESSAGES), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onSubmit { viewModel.searchAllChats() }
                .onChange(of: viewModel.searchText) { _ in
                    viewModel.searchAllChats()
                }
            if !viewModel.searchText.isEmpty {
                Button { viewModel.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.ultraThinMaterial)
    }

    private var resultsList: some View {
        Group {
            if viewModel.isSearching {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.results.isEmpty && !viewModel.searchText.isEmpty {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                List(viewModel.results) { result in
                    Button {
                        onSelectResult(result)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(result.contactName ?? t(ChatTranslationKeys.REPLY_FALLBACK_MESSAGE))
                                    .font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(result.message.displayTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(highlightedText(result.matchedText, query: viewModel.searchText))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }

    private func highlightedText(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = .accentColor
            attributed[range].font = .subheadline.weight(.bold)
        }
        return attributed
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - In-Chat Search Bar

@available(iOS 17.0, *)
struct InChatSearchBar: View {

    @ObservedObject var viewModel: MessageSearchViewModel
    let translationService: (any TranslationServiceProtocol)?
    let messages: [MessageDataItem]
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            TextField(t(ChatTranslationKeys.MESSAGE_SEARCH_PLACEHOLDER), text: $viewModel.searchText)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onChange(of: viewModel.searchText) { _ in
                    viewModel.searchInChat(messages: messages)
                }

            if !viewModel.inChatResults.isEmpty {
                Text("\(viewModel.currentInChatIndex + 1)/\(viewModel.inChatResults.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 36)

                Button { viewModel.previousResult() } label: {
                    Image(systemName: "chevron.up")
                }
                Button { viewModel.nextResult() } label: {
                    Image(systemName: "chevron.down")
                }
            }

            Button { onDismiss() } label: {
                Text(common("cancel"))
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
