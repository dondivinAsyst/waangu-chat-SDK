//
//  ConversationTypeMapper.swift
//  FeatureChat
//
//  Wire conversation type ↔ stored conversation type.
//

import Foundation

/// Turns the `conversationType` the Projection service sends into the type this
/// device stores.
///
/// The wire carries four values today: `DIRECT`, `GROUP`, `BROADCAST`, and the
/// last one being a canal Updates, created by Identity as a Core conversation of
/// type `BROADCAST` when a channel is created. It has no `peer`, so mapping it
/// to `.direct` — as the fallback used to — made every subscribed channel look
/// like a one-to-one thread with nobody on the other end, and the inbox dropped
/// it. Unknown values still fall back to `.direct`, which is what a bare
/// conversation with a peer is.
///
/// `SELF` is the personal folder of `INTEGRATION_CHAT_FINANCE.md` §5.1.1 — one
/// member, no correspondent — which Core also names `FINANCIAL_SELF` in
/// `GET /financial/self-conversation`. Unmapped, it landed on `.direct`, so the
/// inbox looked for a peer that cannot exist and the row lost its title.
enum ConversationTypeMapper {

    static func model(from wire: String) -> ConversationTypeModel {
        switch wire.uppercased() {
        case "GROUP":
            return .group
        case "BROADCAST", "CHANNEL":
            return .channel
        case "SELF", "SELF_CHAT", "FINANCIAL_SELF":
            return .selfChat
        default:
            return .direct
        }
    }

    /// `true` when the wire type names a conversation that carries a `peer`.
    static func isDirect(_ wire: String) -> Bool {
        model(from: wire).hasPeer
    }

    /// The value Chat Core expects back for this type — `SELF` for the
    /// personal folder, and what the Hub is asked with.
    static func wire(from model: ConversationTypeModel) -> String {
        switch model {
        case .direct:   return "DIRECT"
        case .group:    return "GROUP"
        case .channel:  return "BROADCAST"
        case .support:  return "SUPPORT"
        case .selfChat: return "SELF"
        // Jamais envoyé : la conversation Copilot n'existe que sur l'appareil.
        case .copilot:  return "COPILOT"
        }
    }
}
