//
//  RealtimeMonitorView.swift
//  FeatureChat
//
//  Live diagnostics screen for realtime subscriptions. Opened from the chat room
//  header heartbeat indicator. Shows which topics are currently subscribed, how
//  many subscribers share each topic (subscriberCount > 1 → duplicate payloads),
//  and which declared topics are missing.
//

import SwiftUI
import WaanguCoreKit

// MARK: - ViewModel

@MainActor
final class RealtimeMonitorViewModel: ObservableObject {

    @Published private(set) var connectionState: RealtimeConnectionState = .disconnected(reason: .initial)
    @Published private(set) var diagnostics: [RealtimeSubscriptionDiagnostic] = []
    @Published private(set) var lastUpdated: Date = .now
    @Published private(set) var syncHealthMetrics: [SyncHealthMetric] = []
    @Published private(set) var syncSubscriptions: Set<String> = []
    @Published private(set) var outbox: ChatOutboxSnapshot = .empty
    @Published private(set) var outboxError: String?

    let expectedTopics: [String]
    let inboxTopicPath: String

    private let useCases: ConversationRoomUseCasesProtocol
    private let syncHealthMonitor: SyncHealthMonitor
    private var pollTask: Task<Void, Never>?
    private var observeTask: Task<Void, Never>?
    private let pollInterval: UInt64 = 1_000_000_000

    init(
        useCases: ConversationRoomUseCasesProtocol,
        expectedTopics: [String],
        inboxTopicPath: String,
        syncHealthMonitor: SyncHealthMonitor
    ) {
        self.useCases = useCases
        self.expectedTopics = expectedTopics
        self.inboxTopicPath = inboxTopicPath
        self.syncHealthMonitor = syncHealthMonitor
    }

    func start() {
        stop()

        observeTask = Task { [weak self] in
            guard let self else { return }
            for await state in self.useCases.observeRealtimeConnectionState() {
                guard !Task.isCancelled else { break }
                self.connectionState = state
                await self.refresh()
            }
        }

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(nanoseconds: self.pollInterval)
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
        observeTask?.cancel()
        observeTask = nil
    }

    func refresh() async {
        let state = await useCases.realtimeConnectionState()
        let diag = await useCases.subscriptionDiagnostics()
        connectionState = state
        diagnostics = diag
        lastUpdated = .now
        
        // Load sync health data
        syncHealthMetrics = await syncHealthMonitor.getAllMetrics()
        syncSubscriptions = await syncHealthMonitor.getActiveSubscriptions()

        // Load both outbound queues. A read failure must not read as "empty",
        // so the previous snapshot is kept and the error is surfaced instead.
        do {
            outbox = try await useCases.outboxDiagnostics()
            outboxError = nil
        } catch {
            outboxError = error.localizedDescription
        }
    }

    /// `true` if a declared topic is currently covered by an active subscription
    /// (exact path or wildcard match).
    func isExpectedSubscribed(_ expected: String) -> Bool {
        let pattern = RealtimeTopic(expected)
        return diagnostics.contains { diag in
            diag.topicPath == expected
                || RealtimeTopic(diag.topicPath).matches(pattern: pattern)
        }
    }

    var hasDuplicateSubscriptions: Bool {
        diagnostics.contains { $0.subscriberCount > 1 }
    }
    
    /// Get the heart indicator emoji for sync health status
    func heartIndicator(for status: SyncHealthStatus) -> String {
        switch status {
        case .healthy: return "💚"
        case .stale: return "💛"
        case .degraded: return "🧡"
        case .offline: return "❤️"
        }
    }
    
    /// Format relative time since last sync
    func timeSinceSync(_ date: Date?) -> String {
        guard let date else { return "Never" }
        let interval = Date.now.timeIntervalSince(date)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let mins = Int(interval / 60)
            return "\(mins)m ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)h ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
    }

    /// Age of a queued item — same relative formatting as the sync timestamps.
    func age(_ date: Date) -> String {
        timeSinceSync(date)
    }

    func label(for status: OutboxSyncStatus) -> String {
        switch status {
        case .pending: return "pending"
        case .syncing: return "syncing"
        case .synced:  return "cleared"
        case .failed:  return "failed"
        }
    }
}

// MARK: - View

struct RealtimeMonitorView: View {

    @StateObject private var vm: RealtimeMonitorViewModel
    @Environment(\.dismiss) private var dismiss

    init(chatViewModel: ChatRoomViewModel) {
        _vm = StateObject(wrappedValue: chatViewModel.makeRealtimeMonitorViewModel())
    }

    var body: some View {
        NavigationStack {
            List {
                connectionSection
                
                syncHealthSection

                outboxSection
                realtimeQueueSection

                if vm.hasDuplicateSubscriptions {
                    duplicateWarningSection
                }

                activeSubscriptionsSection
                declaredTopicsSection
            }
            .navigationTitle("Realtime Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        Task { await vm.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    // MARK: Sections

    private var connectionSection: some View {
        Section {
            HStack {
                Circle()
                    .fill(connectionColor)
                    .frame(width: 10, height: 10)
                Text(connectionLabel)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(vm.lastUpdated, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Connection")
        } footer: {
            Text("Updates live on connection changes and refreshes every second.")
        }
    }

    private var duplicateWarningSection: some View {
        Section {
            Label {
                Text("One or more topics have more than one subscriber. Each inbound message on those topics is delivered once per subscriber — this is why a payload can be received twice.")
                    .font(.footnote)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
    
    private var syncHealthSection: some View {
        Section {
            if vm.syncHealthMetrics.isEmpty {
                Text("No sync data available")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.syncHealthMetrics) { metric in
                    syncHealthRow(metric)
                }
                
                // Show sync subscriptions count
                HStack {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(.blue)
                    Text("Tracked subscriptions")
                    Spacer()
                    Text("\(vm.syncSubscriptions.count)")
                        .foregroundStyle(.secondary)
                }
                .font(.footnote)
            }
        } header: {
            Text("Sync Health")
        } footer: {
            Text("💚 Healthy • 💛 Stale (>30m) • 🧡 Degraded (1-2 fails) • ❤️ Offline (3+ fails or never)")
        }
    }

    private var outboxSection: some View {
        Section {
            if let error = vm.outboxError {
                Label {
                    Text("Outbox unreadable — \(error)")
                        .font(.footnote)
                } icon: {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                }
            }

            if vm.outbox.entries.isEmpty {
                Text("No stored outbox actions")
                    .foregroundStyle(.secondary)
            } else {
                outboxSummaryRow

                ForEach(vm.outbox.uncleared) { entry in
                    outboxRow(entry)
                }

                let cleared = vm.outbox.count(of: .synced)
                if cleared > 0 {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Text("\(cleared) cleared, awaiting cleanup")
                        Spacer()
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Outbox — not yet cleared (\(vm.outbox.uncleared.count))")
        } footer: {
            Text("Actions persisted for the HTTP flush: messages, edits, deletes, reactions, poll votes, delivery and read receipts, story events. A row leaves this list only when a flush is acknowledged by the server — this screen never sends anything.")
        }
    }

    private var outboxSummaryRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                outboxStatusChip(.pending)
                outboxStatusChip(.syncing)
                outboxStatusChip(.failed)
                Spacer()
            }
            if let oldest = vm.outbox.oldestUnclearedAt {
                Text("Oldest uncleared: \(vm.age(oldest))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func outboxStatusChip(_ status: OutboxSyncStatus) -> some View {
        Text("\(vm.label(for: status)) \(vm.outbox.count(of: status))")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(outboxStatusColor(status).opacity(0.18), in: Capsule())
            .foregroundStyle(outboxStatusColor(status))
    }

    private func outboxRow(_ entry: ChatOutboxEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.actionType)
                    .font(.system(.footnote, design: .monospaced).weight(.semibold))
                Spacer()
                Text(vm.label(for: entry.syncStatus))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(outboxStatusColor(entry.syncStatus).opacity(0.18), in: Capsule())
                    .foregroundStyle(outboxStatusColor(entry.syncStatus))
            }

            HStack(spacing: 8) {
                Text(vm.age(entry.createdAt))
                if !entry.conversationId.isEmpty {
                    Text("conv \(entry.conversationId)")
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text("\(entry.payloadBytes) B")
                if entry.retryCount > 0 {
                    Text("\(entry.retryCount) retr\(entry.retryCount > 1 ? "ies" : "y")")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(entry.idempotencyKey)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let lastError = entry.lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var realtimeQueueSection: some View {
        Section {
            if vm.outbox.queuedRealtimeMessages.isEmpty {
                Text("No buffered publishes")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.outbox.queuedRealtimeMessages) { queued in
                    realtimeQueueRow(queued)
                }
            }
        } header: {
            Text("Realtime offline queue (\(vm.outbox.queuedRealtimeMessages.count))")
        } footer: {
            Text("MQTT publishes buffered while the socket was down. The transport flushes them on reconnect. This queue is in-memory, so anything listed here is lost if the app is killed first.")
        }
    }

    private func realtimeQueueRow(_ queued: ChatQueuedRealtimeMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(queued.topicPath)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if queued.isExpired {
                    Text("expired")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.18), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            HStack(spacing: 8) {
                Text(vm.age(queued.queuedAt))
                Text("QoS \(queued.qos.rawValue)")
                Text("priority \(queued.priority.rawValue)")
                Text("\(queued.payloadBytes) B")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func outboxStatusColor(_ status: OutboxSyncStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .syncing: return .blue
        case .synced:  return .green
        case .failed:  return .red
        }
    }

    private var activeSubscriptionsSection: some View {
        Section {
            if vm.diagnostics.isEmpty {
                Text("No active subscriptions")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(vm.diagnostics) { diag in
                    subscriptionRow(diag)
                }
            }
        } header: {
            Text("Active subscriptions (\(vm.diagnostics.count))")
        }
    }

    private var declaredTopicsSection: some View {
        Section {
            ForEach(vm.expectedTopics, id: \.self) { topic in
                HStack {
                    Image(systemName: vm.isExpectedSubscribed(topic) ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(vm.isExpectedSubscribed(topic) ? .green : .red)
                    Text(topic)
                        .font(.system(.footnote, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Text(vm.isExpectedSubscribed(topic) ? "subscribed" : "missing")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Declared chat topics")
        } footer: {
            Text("Topics FeatureChat declares it needs. \"missing\" means no active subscription currently covers it.")
        }
    }

    private func subscriptionRow(_ diag: RealtimeSubscriptionDiagnostic) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(diag.topicPath)
                    .font(.system(.footnote, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if diag.topicPath == vm.inboxTopicPath {
                    Text("inbox")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.15), in: Capsule())
                }
                Spacer()
                subscriberBadge(diag.subscriberCount)
            }
            HStack(spacing: 8) {
                Text("QoS \(diag.qos.rawValue)")
                if diag.isWildcard {
                    Text("wildcard")
                }
                if let feature = diag.feature {
                    Text(feature)
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    private func subscriberBadge(_ count: Int) -> some View {
        Text("\(count) sub\(count > 1 ? "s" : "")")
            .font(.caption2.weight(.bold))
            .foregroundStyle(count > 1 ? .white : .secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(
                count > 1 ? Color.orange : Color.gray.opacity(0.2),
                in: Capsule()
            )
    }
    
    private func syncHealthRow(_ metric: SyncHealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(vm.heartIndicator(for: metric.status))
                    .font(.title3)
                Text(metric.topic)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text(vm.timeSinceSync(metric.lastSyncTime))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            HStack(spacing: 12) {
                if let lastSuccess = metric.lastSuccessTime {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                        Text(vm.timeSinceSync(lastSuccess))
                    }
                }
                
                if metric.consecutiveFailures > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                        Text("\(metric.consecutiveFailures) fail\(metric.consecutiveFailures > 1 ? "s" : "")")
                    }
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: Connection presentation

    private var connectionColor: Color {
        switch vm.connectionState {
        case .connected: return .green
        case .connecting, .authenticating, .reconnecting: return .orange
        case .suspended: return .yellow
        case .disconnected: return .red
        }
    }

    private var connectionLabel: String {
        switch vm.connectionState {
        case .connected: return "Connected"
        case .connecting: return "Connecting…"
        case .authenticating: return "Authenticating…"
        case .reconnecting(let attempt, _): return "Reconnecting (attempt \(attempt))…"
        case .suspended: return "Suspended"
        case .disconnected: return "Disconnected"
        }
    }
}
