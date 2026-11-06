//
//  ChatRoomTimelineBuilder.swift
//  FeatureChat
//

import Foundation

/// Builds grouped timeline sections (messages, media groups, checkpoints, group intro).
struct ChatRoomTimelineBuilder {

    private(set) var photoCodeToGroupId: [String: String] = [:]

    private static let sectionIdFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Header formatters, built once instead of per rebuild.
    ///
    /// `DateFormatter()` costs on the order of a millisecond to construct, and the
    /// timeline is rebuilt on every database tick — building two of them (plus one
    /// more per week-old section) inside the grouping loop put that cost on the main
    /// actor in the middle of scrolling.
    ///
    /// They are rebuilt when the locale changes so a language switch still reformats
    /// the headers, which is the only reason they were being made fresh each time.
    private static var cachedHeaderFormatters: (locale: Locale, day: DateFormatter, weekday: DateFormatter)?

    private static func headerFormatters() -> (day: DateFormatter, weekday: DateFormatter) {
        let locale = Locale.current
        if let cached = cachedHeaderFormatters, cached.locale == locale {
            return (cached.day, cached.weekday)
        }

        let day = DateFormatter()
        day.dateStyle = .medium
        day.timeStyle = .none
        day.locale = locale

        let weekday = DateFormatter()
        weekday.dateFormat = "EEEE"
        weekday.locale = locale

        cachedHeaderFormatters = (locale, day, weekday)
        return (day, weekday)
    }

    /// How far apart a locally recorded action and the server event describing the
    /// same change can be and still be treated as one. Generous because the gap is
    /// a round trip plus whatever the broker adds, not a clock difference.
    private static let localActionEchoWindow: TimeInterval = 120

    mutating func build(_ input: ChatRoomTimelineInput) -> [MessageSection] {
        let timelineActions = Self.filteredTimelineActions(
            from: Self.droppingLocalEchoes(of: input.messages, from: input.chatActions),
            shouldShowGroupIntroHeader: input.shouldShowGroupIntroHeader,
            isGroupAdmin: input.isGroupAdmin
        )
        let sections = groupMessagesByDay(
            messages: input.messages,
            chatActions: timelineActions
        )
        return prependGroupIntroRows(
            to: sections,
            shouldShow: input.shouldShowGroupIntroHeader,
            introContent: input.groupIntroContent
        )
    }

    // MARK: - Chat action filtering

    static func filteredTimelineActions(
        from actions: [ChatActionItem],
        shouldShowGroupIntroHeader: Bool,
        isGroupAdmin: Bool
    ) -> [ChatActionItem] {
        actions.filter { action in
            switch action.actionType {
            case .groupCreated where shouldShowGroupIntroHeader:
                return false
            case .messageDeleted:
                return false
            case .joinRequestReceived where !isGroupAdmin:
                return false
            default:
                return true
            }
        }
    }

    /// Drops the locally recorded copy of an action the server has now sent back.
    ///
    /// Acting on a group writes a `ChatActionItem` straight away so the person who
    /// did it sees it immediately, and the backend then projects the same change
    /// into the thread as a message. Both reach this builder, so without this the
    /// actor — and only the actor — sees every group change twice.
    ///
    /// The server copy wins: it is the one every other member sees, and it carries
    /// the id the timeline is keyed on.
    static func droppingLocalEchoes(
        of messages: [MessageDataItem],
        from actions: [ChatActionItem]
    ) -> [ChatActionItem] {
        let serverEvents: [(type: ChatActionType, targetId: String?, at: Date)] = messages.compactMap {
            guard let type = ChatActionType(groupEvent: $0.typeMessage) else { return nil }
            return (type, $0.message.groupEvent?.targetUserId, $0.createdAt)
        }
        guard !serverEvents.isEmpty else { return actions }

        return actions.filter { action in
            !serverEvents.contains { event in
                event.type == action.actionType
                    && event.targetId == action.targetId
                    && abs(event.at.timeIntervalSince(action.timestamp)) <= localActionEchoWindow
            }
        }
    }

    // MARK: - Section grouping

    private mutating func groupMessagesByDay(
        messages: [MessageDataItem],
        chatActions: [ChatActionItem]
    ) -> [MessageSection] {
        let calendar = Calendar.current
        let now = Date()
        let formatters = Self.headerFormatters()

        var combinedItems: [(date: Date, item: Any)] = []

        for message in messages where message.typeMessage != .GROUP_CREATED {
            combinedItems.append((date: message.createdAt, item: message))
        }

        for action in chatActions {
            combinedItems.append((date: action.timestamp, item: action))
        }

        combinedItems.sort { $0.date < $1.date }

        let groupedDict = Dictionary(grouping: combinedItems) { item in
            calendar.startOfDay(for: item.date)
        }

        let sortedKeys = groupedDict.keys.sorted(by: <)

        return sortedKeys.map { date in
            let title: String
            if calendar.isDateInToday(date) {
                title = NSLocalizedString("Today", comment: "")
            } else if calendar.isDateInYesterday(date) {
                title = NSLocalizedString("Yesterday", comment: "")
            } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
                title = formatters.weekday.string(from: date)
            } else {
                title = formatters.day.string(from: date)
            }

            let sectionId = Self.sectionIdFormatter.string(from: date)
            let sortedItems = groupedDict[date]?.sorted(by: { $0.date < $1.date }) ?? []

            return MessageSection(
                id: sectionId,
                date: title,
                rows: buildRows(from: sortedItems)
            )
        }
    }

    private mutating func buildRows(from items: [(date: Date, item: Any)]) -> [MessageRow] {
        var rows: [MessageRow] = []

        // Collect media messages keyed by their batchId, preserving insertion order of batches.
        // Messages with no batchId (single sends) get a unique per-message key so they never merge.
        var batchOrder: [String] = []                            // ordered list of batchIds seen
        var batchBuckets: [String: [MessageDataItem]] = [:]      // batchId → messages

        func flushBatches() {
            for batchId in batchOrder {
                guard let msgs = batchBuckets[batchId], !msgs.isEmpty else { continue }
                if msgs.count == 1 {
                    // Single image/video — render as a plain message bubble
                    rows.append(.message(msgs[0]))
                } else {
                    // Multi-select batch — render as a grouped media grid
                    let groupId = "group_\(batchId)"
                    for msg in msgs {
                        photoCodeToGroupId[msg.codeMessage] = groupId
                    }
                    rows.append(.mediaGroup(idGroup: groupId, messages: msgs))
                }
            }
            batchOrder.removeAll()
            batchBuckets.removeAll()
        }

        photoCodeToGroupId.removeAll()

        for item in items {
            if let message = item.item as? MessageDataItem {
                // System records are decided first and unconditionally: a group
                // event is a checkpoint whatever else is true of it, including
                // being deleted — nobody sent it, so it is not a message that
                // could have been taken back.
                if message.typeMessage == .GROUP_CREATED {
                    // The intro header already says the group was created.
                    flushBatches()
                } else if let action = ChatActionItem(
                    groupEvent: message,
                    conversationId: message.groupId ?? ""
                ) {
                    flushBatches()
                    rows.append(.checkpoint(action))
                } else if message.isDeleted {
                    flushBatches()
                    rows.append(.message(message))
                } else if (message.typeMessage == .IMAGE || message.typeMessage == .VIDEO),
                          // Drawn on its own, as its placeholder — never inside an album.
                          !message.isViewOnce,
                          let batchId = message.message.mediaBatchId, !batchId.isEmpty {
                    // This message belongs to an explicit batch
                    if batchBuckets[batchId] == nil {
                        batchOrder.append(batchId)
                        batchBuckets[batchId] = []
                    }
                    batchBuckets[batchId]?.append(message)
                } else if message.typeMessage == .IMAGE || message.typeMessage == .VIDEO {
                    // Single media send (no batchId) — flush any pending batch first, then render solo
                    flushBatches()
                    rows.append(.message(message))
                } else {
                    flushBatches()
                    rows.append(.message(message))
                }
            } else if let action = item.item as? ChatActionItem {
                flushBatches()
                rows.append(.checkpoint(action))
            }
        }

        flushBatches()
        return rows
    }

    private func prependGroupIntroRows(
        to sections: [MessageSection],
        shouldShow: Bool,
        introContent: GroupChatIntroContent?
    ) -> [MessageSection] {
        guard shouldShow, let introContent else { return sections }

        // B61 — l'avis « chiffré de bout en bout » seulement si c'est vrai.
        let introRows: [MessageRow] = ChatEncryptionClaim.messagesAreEndToEndEncrypted
            ? [.encryptionBanner, .groupIntro(introContent)]
            : [.groupIntro(introContent)]

        if sections.isEmpty {
            let todayId = Self.sectionIdFormatter.string(from: Calendar.current.startOfDay(for: Date()))
            return [
                MessageSection(
                    id: todayId,
                    date: NSLocalizedString("Today", comment: ""),
                    rows: introRows
                )
            ]
        }

        var updated = sections
        updated[0].rows = introRows + updated[0].rows
        return updated
    }
}
