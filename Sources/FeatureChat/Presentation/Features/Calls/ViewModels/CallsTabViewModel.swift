import Foundation
import Combine
import SwiftUI

struct CallHistoryItem: Identifiable, Equatable {
    let id: String
    let contactName: String
    let contactPhone: String
    let contactImage: String?
    let callType: CallType
    let isMissed: Bool
    /// The call never reached the other side — a server refusal, not a call
    /// anyone declined or missed. Kept apart from `isMissed` so it neither
    /// shows in the Missed filter nor reads as the user's own doing.
    let didFail: Bool
    /// The contact's account id, when the log recorded one. Redialling by phone
    /// alone would put a phone number in the offer's `userId`.
    let userId: String?
    let isOutgoing: Bool
    let isVideo: Bool
    let timestamp: Date
    let duration: Int?
    /// Carried through so redialling reuses the original thread.
    let conversationId: String?
    
    var displayTime: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        
        if calendar.isDateInToday(timestamp) {
            formatter.dateFormat = "h:mm a"
            return "Today, \(formatter.string(from: timestamp))"
        } else if calendar.isDateInYesterday(timestamp) {
            formatter.dateFormat = "h:mm a"
            return "Yesterday, \(formatter.string(from: timestamp))"
        } else {
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: timestamp)
        }
    }
    
    var shortTime: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(timestamp) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: timestamp)
        } else if calendar.isDateInYesterday(timestamp) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            return formatter.string(from: timestamp)
        }
    }
    
    var callDirectionIcon: String {
        // A call that never left the device gets its own mark: neither the
        // inbound arrow of a missed call nor the plain outbound one, both of
        // which would claim it reached somebody.
        if didFail {
            return "exclamationmark.triangle.fill"
        }
        if isMissed {
            return "phone.arrow.down.left.fill"
        }
        return isOutgoing ? "phone.arrow.up.right.fill" : "phone.arrow.down.left.fill"
    }
    
    var callDirectionColor: Color {
        if didFail { return .orange }
        return isMissed ? .red : .secondary
    }
}

struct GroupedCallItem: Identifiable, Equatable {
    let id: String
    let contactName: String
    let contactPhone: String
    let contactImage: String?
    let calls: [CallHistoryItem]
    
    var count: Int { calls.count }
    var latestCall: CallHistoryItem { calls[0] }
    var isMissed: Bool { latestCall.isMissed }
    var didFail: Bool { latestCall.didFail }
    var isVideo: Bool { latestCall.isVideo }
    
    var shortTime: String { latestCall.shortTime }
    
    var callDirectionIcon: String { latestCall.callDirectionIcon }
    var callDirectionColor: Color { latestCall.callDirectionColor }
    
    var callTypeLabel: String {
        let type = latestCall.isVideo ? "video" : "audio"
        // "Outgoing audio" would describe a call that never went out.
        let direction = latestCall.didFail
            ? "Failed"
            : (latestCall.isOutgoing ? "Outgoing" : "Incoming")
        if count > 1 {
            return "(\(count)) \(direction) \(type)"
        }
        return "\(direction) \(type)"
    }
}

@MainActor
public final class CallsTabViewModel: ObservableObject {
    @Published var callHistory: [CallHistoryItem] = []
    @Published var groupedCalls: [GroupedCallItem] = []
    @Published var isLoading = false

    private let callUseCases: CallUseCasesProtocol
    private var cancellables = Set<AnyCancellable>()

    init(callUseCases: CallUseCasesProtocol) {
        self.callUseCases = callUseCases
        observeCallHistory()
    }

    private func observeCallHistory() {
        NotificationCenter.default.publisher(for: .callHistoryPersisted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadCallHistory()
            }
            .store(in: &cancellables)
    }
    
    /// Shows what is already stored, then pulls what the server has.
    ///
    /// Local first and unconditionally: the tab must render instantly and offline,
    /// and the sync is a delta that usually writes nothing. When it does write,
    /// it posts `.callHistoryPersisted` and the observer above reloads the list —
    /// so there is no second load to sequence here.
    func onAppear() {
        loadCallHistory()

        Task { @MainActor in
            do {
                try await callUseCases.syncCalls.execute(limit: 50)
            } catch {
                // History already on screen — a failed sync is not worth an alert.
                #if DEBUG
                print("[CallsSync] Failed: \(error)")
                #endif
            }
        }
    }

    /// Reads the call log directly. The previous implementation reconstructed
    /// history by loading every discussion and every message in it and filtering
    /// for call types — the log is both cheaper and the actual source of truth,
    /// since it records outcomes the message thread cannot express.
    func loadCallHistory() {
        isLoading = true

        Task { @MainActor in
            defer { isLoading = false }
            do {
                let logs = try await callUseCases.getCallLogs.execute(filter: .all, limit: nil)
                callHistory = logs.map(Self.makeHistoryItem)
                groupedCalls = groupCallsByContact(callHistory)
            } catch {
                #if DEBUG
                print("Failed to load call history: \(error)")
                #endif
            }
        }
    }

    private static func makeHistoryItem(_ log: CallLogEntity) -> CallHistoryItem {
        CallHistoryItem(
            id: log.id,
            contactName: log.contactName.isEmpty ? log.contactPhone : log.contactName,
            contactPhone: log.contactPhone,
            contactImage: log.contactAvatarURL,
            callType: log.media == .video ? .video : .audio,
            isMissed: log.outcome.isMissed,
            didFail: log.outcome == .failed,
            userId: log.userId ?? log.participants.first?.userId,
            isOutgoing: log.direction == .outgoing,
            isVideo: log.media == .video,
            timestamp: log.startedAt,
            duration: log.outcome.didConnect ? log.durationSeconds : nil,
            conversationId: log.conversationId
        )
    }
    
    func filteredGroupedCalls(missed: Bool) -> [GroupedCallItem] {
        if missed {
            return groupedCalls.filter { $0.isMissed }
        }
        return groupedCalls
    }
    
    func startCall(
        to phone: String,
        isVideo: Bool,
        name: String? = nil,
        image: String? = nil,
        conversationId: String? = nil,
        userId: String? = nil
    ) {
        VoipManager.shared.startOutgoingCall(
            to: phone,
            hasVideo: isVideo,
            name: name,
            image: image,
            conversationId: conversationId,
            userId: userId
        )
    }
    
    /// Groups consecutive calls from the same contact into a single row
    private func groupCallsByContact(_ calls: [CallHistoryItem]) -> [GroupedCallItem] {
        guard !calls.isEmpty else { return [] }
        
        var groups: [GroupedCallItem] = []
        var currentGroup: [CallHistoryItem] = [calls[0]]
        
        for i in 1..<calls.count {
            let prev = calls[i - 1]
            let curr = calls[i]
            
            let sameContact = prev.contactPhone == curr.contactPhone
            let sameDay = Calendar.current.isDate(prev.timestamp, inSameDayAs: curr.timestamp)
            let sameDirection = prev.isOutgoing == curr.isOutgoing
            let sameType = prev.isMissed == curr.isMissed
            
            if sameContact && sameDay && sameDirection && sameType {
                currentGroup.append(curr)
            } else {
                groups.append(makeGroup(from: currentGroup))
                currentGroup = [curr]
            }
        }
        
        if !currentGroup.isEmpty {
            groups.append(makeGroup(from: currentGroup))
        }
        
        return groups
    }
    
    private func makeGroup(from calls: [CallHistoryItem]) -> GroupedCallItem {
        let first = calls[0]
        return GroupedCallItem(
            id: first.id,
            contactName: first.contactName,
            contactPhone: first.contactPhone,
            contactImage: first.contactImage,
            calls: calls
        )
    }
}
