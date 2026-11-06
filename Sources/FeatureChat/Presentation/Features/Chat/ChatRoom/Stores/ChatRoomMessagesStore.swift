import Foundation
import UIKit

@MainActor
public final class ChatRoomMessagesStore: ObservableObject {

    static var defaultPageSize: Int {
        let screenHeight = UIScreen.main.bounds.height
        let averageCellHeight: CGFloat = 72
        let buffer = 2
        return Int(screenHeight / averageCellHeight) + buffer
    }

    @Published private(set) var messages: [MessageDataItem] = []
    @Published private(set) var typingUsers: [TypingUser] = []
    @Published private(set) var allMediaMessages: [MessageDataItem] = []

    private(set) var oldestLoadedDate: Date?
    private(set) var hasMore: Bool = true

    /// Incremented once per older page actually spliced in above the window.
    ///
    /// The room list uses it to tell a pagination splice apart from every other
    /// timeline change. Counting messages could not: a read receipt or a
    /// reaction rebuilds the timeline without changing the count, and an
    /// inbound message changes the count without being a page.
    private(set) var prependGeneration: Int = 0

    private var observedSnapshot: [MessageDataItem] = []
    private var decryptHandler: (([MessageDataItem]) async -> [MessageDataItem])?

    init() {}

    func setDecryptHandler(_ handler: @escaping ([MessageDataItem]) async -> [MessageDataItem]) {
        decryptHandler = handler
    }

    public func applyInitialPage(_ page: ChatRoomPaginationResult) async {
        let decrypted = await decryptIfNeeded(page.messages)
        messages = decrypted
        allMediaMessages = page.allMediaMessages
        oldestLoadedDate = page.oldestLoadedDate
        hasMore = page.hasMore
    }

    public func applyPagination(_ page: ChatRoomPaginationResult) async {
        let decrypted = await decryptIfNeeded(page.messages)
        let existingIds = Set(messages.map(\.codeMessage))
        let older = decrypted.filter { !existingIds.contains($0.codeMessage) }
        // Bumped before the publish, so the generation is already current by the
        // time the room's subscriber reads it on the next main-queue turn.
        if !older.isEmpty { prependGeneration += 1 }
        publish(Self.sorted(older + messages))
        oldestLoadedDate = page.oldestLoadedDate ?? oldestLoadedDate
        hasMore = page.hasMore
    }

    public func applyObservation(_ items: [MessageDataItem]) async {
        let decrypted = await decryptIfNeeded(items)
        observedSnapshot = decrypted
        mergeObservedWithPaginatedWindow()
    }

    /// Optimistic local delete so UI updates before the next DB observation tick.
    public func applyLocalDelete(codeMessage: String, forEveryone: Bool) {
        if forEveryone {
            if let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) {
                messages[index].isDeleted = true
                messages[index].status = .PENDING
            }
        } else {
            messages.removeAll { $0.codeMessage == codeMessage }
        }
        allMediaMessages = messages.filter { ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce }
    }

    public func applyTyping(_ users: [TypingUser]) {
        typingUsers = users
    }

    public func resetTyping() {
        typingUsers = []
    }

    public func replaceMessages(_ items: [MessageDataItem]) async {
        publish(Self.sorted(await decryptIfNeeded(items)))
    }

    public func mergeIncoming(_ incoming: [MessageDataItem]) async {
        let decrypted = await decryptIfNeeded(incoming)
        publish(Self.merged(existing: messages, incoming: decrypted))
    }

    /// Replaces an existing message in the active room (e.g. after a reaction change).
    public func upsertMessage(_ item: MessageDataItem) async {
        let decrypted = await decryptIfNeeded([item])
        guard let updated = decrypted.first else { return }
        if let index = messages.firstIndex(where: { $0.codeMessage == updated.codeMessage }) {
            var next = messages
            next[index] = updated
            publish(next)
        } else {
            publish(Self.sorted(messages + [updated]))
        }
    }

    /// Publishes a new window only when it differs from the one already on screen.
    ///
    /// The database observation re-emits the whole conversation on every write —
    /// including writes this room makes itself, such as read receipts — so most
    /// ticks carry a snapshot identical to what is already displayed. Assigning it
    /// anyway still fired `objectWillChange`, which rebuilt the entire timeline and
    /// re-laid out every visible row for no visible difference.
    private func publish(_ next: [MessageDataItem]) {
        guard next != messages else { return }
        messages = next
        allMediaMessages = next.filter { ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce }
    }

    /// Merges without ever holding the same message twice.
    ///
    /// A plain append duplicated anything that arrived by two routes at once —
    /// a call message merged in when the call ends *and* reloaded from the
    /// database, for instance. That showed the bubble twice and crashed anything
    /// keying messages by `codeMessage`.
    ///
    /// The incoming copy wins: it is the fresher one, which is what
    /// `upsertMessage` already assumes.
    nonisolated static func merged(existing: [MessageDataItem], incoming: [MessageDataItem]) -> [MessageDataItem] {
        guard !incoming.isEmpty else { return sorted(existing) }

        var indexByCode: [String: Int] = [:]
        var combined: [MessageDataItem] = []
        combined.reserveCapacity(existing.count + incoming.count)

        for message in existing + incoming {
            // A message with no code has no identity to de-duplicate on, so it
            // is kept as-is rather than collapsed with every other empty one.
            guard !message.codeMessage.isEmpty else {
                combined.append(message)
                continue
            }

            if let index = indexByCode[message.codeMessage] {
                combined[index] = message
            } else {
                indexByCode[message.codeMessage] = combined.count
                combined.append(message)
            }
        }

        return sorted(combined)
    }

    private func decryptIfNeeded(_ items: [MessageDataItem]) async -> [MessageDataItem] {
        guard let decryptHandler else { return items }
        return await decryptHandler(items)
    }

    private func mergeObservedWithPaginatedWindow() {
        // Tolerates a repeated code rather than trapping: a duplicate in the
        // snapshot is a reason to prefer the later row, not to crash the app.
        let observedById = Dictionary(
            observedSnapshot.map { ($0.codeMessage, $0) },
            uniquingKeysWith: { _, latest in latest }
        )

        // Observation is visibility source of truth (hides delete-for-me).
        // Do not keep local rows that disappeared from the DB snapshot.
        guard let cutoff = oldestLoadedDate else {
            publish(Self.sorted(observedSnapshot))
            return
        }

        var next: [MessageDataItem] = []
        var seenCodes = Set<String>()
        for msg in messages {
            if let updated = observedById[msg.codeMessage] {
                next.append(updated)
                seenCodes.insert(updated.codeMessage)
            }
        }
        for item in observedSnapshot where item.createdAt >= cutoff {
            if seenCodes.insert(item.codeMessage).inserted {
                next.append(item)
            }
        }
        publish(Self.sorted(next))
    }

    nonisolated private static func sorted(_ items: [MessageDataItem]) -> [MessageDataItem] {
        items.sorted { $0.createdAt < $1.createdAt }
    }
}
