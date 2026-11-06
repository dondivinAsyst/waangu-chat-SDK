//
//  RealtimeHeartbeatIndicator.swift
//  FeatureChat
//
//  Small header indicator that "beats" on each realtime poll and reflects
//  whether we're still subscribed to the room's inbox topic.
//

import SwiftUI

/// Health of the realtime link for the current chat room's inbox topic.
enum RealtimeHeartbeatStatus: Equatable {
    /// Connected and subscribed to the inbox topic.
    case live
    /// Connected but not subscribed to the inbox topic (subscription dropped).
    case degraded
    /// Connecting / reconnecting.
    case connecting
    /// Not connected.
    case down

    var color: Color {
        switch self {
        case .live: return .green
        case .degraded: return .yellow
        case .connecting: return .orange
        case .down: return .red
        }
    }

    var label: String {
        switch self {
        case .live: return "Subscribed"
        case .degraded: return "Connected · not subscribed"
        case .connecting: return "Connecting…"
        case .down: return "Disconnected"
        }
    }

    /// Whether the heart should animate (no beat when fully down).
    var animates: Bool { self != .down }
}

/// A compact pulsing heart used in the chat room header for live subscription monitoring.
struct RealtimeHeartbeatIndicator: View {
    let status: RealtimeHeartbeatStatus
    let pulse: Bool
    var showsLabel: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "heart.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(status.color)
                .scaleEffect(scale)
                .opacity(status == .down ? 0.55 : 1)
                .animation(.easeInOut(duration: 0.35), value: pulse)
                .animation(.easeInOut(duration: 0.25), value: status)

            if showsLabel {
                Text(status.label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Realtime status: \(status.label)"))
    }

    private var scale: CGFloat {
        guard status.animates else { return 0.9 }
        return pulse ? 1.25 : 0.92
    }
}

/// Observes the monitor so the once-a-second beat invalidates this indicator and
/// nothing else. Reading `monitor.status` / `monitor.pulse` from the chat room
/// header directly would subscribe the header — and with it the message list it
/// contains — to every tick.
struct LiveRealtimeHeartbeatIndicator: View {
    @ObservedObject var monitor: ChatRoomHeartbeatMonitor
    var showsLabel: Bool = false

    var body: some View {
        RealtimeHeartbeatIndicator(
            status: monitor.status,
            pulse: monitor.pulse,
            showsLabel: showsLabel
        )
    }
}
