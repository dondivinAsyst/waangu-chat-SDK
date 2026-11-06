//
//  ChatRoomHeartbeatMonitor.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Tracks the health of the realtime link for one chat room's inbox topic.
///
/// This lives on its own object rather than on `ChatRoomViewModel` because it
/// publishes once a second, forever, while the room is open. On the room view
/// model that tick invalidated every observer of the room — the message list and
/// each visible bubble — so the whole timeline was re-evaluated and re-laid out
/// once a second whether or not a single message had changed. Only the header
/// indicator cares about the beat, so only the header indicator should observe it.
@MainActor
final class ChatRoomHeartbeatMonitor: ObservableObject {

    /// Live health of the realtime link.
    @Published private(set) var status: RealtimeHeartbeatStatus = .down
    /// Flipped on every tick to drive the pulsing animation.
    @Published private(set) var pulse: Bool = false

    private var heartbeatTask: Task<Void, Never>?
    private var connectionObserverTask: Task<Void, Never>?
    private let interval: UInt64

    init(interval: UInt64 = 1_000_000_000) {
        self.interval = interval
    }

    /// Hybrid monitor:
    /// 1. Reacts instantly to connection transitions via `observeRealtimeConnectionState()`.
    /// 2. A steady poll drives the beat animation and catches subscribe/unsubscribe
    ///    churn (which has no event stream yet).
    func start(useCases: ConversationRoomUseCasesProtocol) {
        stop()

        connectionObserverTask = Task { [weak self] in
            for await state in useCases.observeRealtimeConnectionState() {
                guard let self, !Task.isCancelled else { break }
                let subscribed = await useCases.isInboxSubscribed()
                self.apply(state: state, subscribed: subscribed, beat: false)
            }
        }

        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let state = await useCases.realtimeConnectionState()
                let subscribed = await useCases.isInboxSubscribed()
                self.apply(state: state, subscribed: subscribed, beat: true)
                try? await Task.sleep(nanoseconds: self.interval)
            }
        }
    }

    func stop() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        connectionObserverTask?.cancel()
        connectionObserverTask = nil
    }

    private func apply(
        state: RealtimeConnectionState,
        subscribed: Bool,
        beat: Bool
    ) {
        let next: RealtimeHeartbeatStatus
        if state.isConnected {
            next = subscribed ? .live : .degraded
        } else if state.isTransitioning {
            next = .connecting
        } else {
            next = .down
        }

        // Only publish a status that actually moved. The poll runs every second
        // and the link is steady almost all of that time.
        if next != status { status = next }
        if beat { pulse.toggle() }
    }
}
