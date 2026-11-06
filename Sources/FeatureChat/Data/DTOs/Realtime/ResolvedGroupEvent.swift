import Foundation

/// What a message says about a group change, once the wire's several spellings
/// have been reconciled.
///
/// This is the single answer to "is this message a group event, who did it, and
/// who is it about". Everything downstream — the stored type, the checkpoint, the
/// roster, whether the conversation may show it as its last message — asks this
/// and nothing else, so the answer cannot differ between the MQTT path,
/// pull-events and the inbox summary.
public struct ResolvedGroupEvent: Sendable {
    public let type: MessageTypeProps
    public let actorId: String
    public let actorName: String
    public let actorPhone: String
    /// Who the event is about. The full initial roster on `GROUP_CREATED`, the
    /// affected member on the membership and role events, empty on `GROUP_UPDATED`.
    public let targets: [GroupRosterParticipantDTO]
    public let title: String?
    public let avatar: String?

    /// The member the event is *about*, for events that are about a member.
    ///
    /// Creation and update are not: their `targetUsers` is the founding roster or
    /// nothing at all, so taking the first entry would name the owner as the
    /// subject of "created the group" and give the checkpoint a target it does
    /// not have.
    public var primaryTarget: GroupRosterParticipantDTO? {
        switch type {
        case .GROUP_CREATED, .GROUP_UPDATED: return nil
        default:                             return targets.first
        }
    }

    /// True when the roster it carries is the whole group rather than a delta, and
    /// so may be applied as-is.
    public var carriesFullRoster: Bool { type == .GROUP_CREATED }
}

public extension InboundMessageDTO {

    /// Nil for anything that is not a group event, which is almost every message.
    ///
    /// Asked of the envelope first: `typeMessage` now carries the event kind and
    /// `senderId` the real actor. Older payloads put the kind inside `content` and
    /// sent the envelope as `"system"`, so both are still read — a device mid
    /// rollout will see either.
    var resolvedGroupEvent: ResolvedGroupEvent? {
        let content = messageContent
        guard let type = resolvedGroupEventType else { return nil }

        let targets = content.targetUsers ?? content.participants ?? []
        let actor = resolvedGroupActor(for: type, content: content, targets: targets)

        return ResolvedGroupEvent(
            type: type,
            actorId: actor.id,
            actorName: actor.name,
            actorPhone: actor.phone,
            targets: targets,
            title: content.resolvedGroupTitle,
            avatar: content.resolvedGroupAvatar
        )
    }

    private var resolvedGroupEventType: MessageTypeProps? {
        let content = messageContent
        let candidates = [typeMessage, content.groupEventType, content.eventType]
        for raw in candidates.compactMap({ $0 }) {
            let normalized = raw.uppercased().replacingOccurrences(of: "-", with: "_")
            if let type = MessageTypeProps(rawValue: normalized), type.isGroupEvent {
                return type
            }
        }
        return nil
    }

    /// The envelope's sender is the actor in the current shape. `"system"` is the
    /// tell that it is an older payload, where the actor is named inside the
    /// content under a different key per event.
    private func resolvedGroupActor(
        for type: MessageTypeProps,
        content: MessageContentDTO,
        targets: [GroupRosterParticipantDTO]
    ) -> (id: String, name: String, phone: String) {
        let envelopeIsUsable = !senderId.isEmpty
            && senderId.caseInsensitiveCompare("system") != .orderedSame
        if envelopeIsUsable {
            return (senderId, senderName, senderPhone ?? "")
        }

        guard let declared = content.declaredActor(for: type, targets: targets) else {
            return ("", "", "")
        }
        let match = targets.first { $0.userId == declared.userId }
        return (
            declared.userId,
            declared.displayName ?? match?.displayName ?? "",
            [declared.phone, match?.phone].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        )
    }
}

public extension MessageContentDTO {

    var resolvedGroupTitle: String? {
        [groupTitle, title].compactMap { $0 }.first { !$0.isEmpty }
    }

    var resolvedGroupAvatar: String? {
        [groupAvatarUrl, groupAvatar, avatarUrl, avatar]
            .compactMap { $0 }
            .first { !$0.isEmpty }
    }

    /// Only reached for payloads predating the actor moving onto the envelope.
    func declaredActor(
        for type: MessageTypeProps,
        targets: [GroupRosterParticipantDTO]
    ) -> GroupActorDTO? {
        switch type {
        case .GROUP_CREATED:            return createdBy
        case .GROUP_UPDATED:            return updatedBy
        case .USER_ADDED_TO_GROUP:      return addedBy
        case .USER_REMOVED_FROM_GROUP:  return removedBy
        case .USER_PROMOTED_TO_ADMIN,
             .USER_DEMOTED_FROM_ADMIN:  return changedBy
        // Nobody else performs these — the person who left or joined did it.
        case .USER_LEFT_GROUP, .USER_JOINED_GROUP:
            let id = targetUserId ?? targets.first?.userId
            return id.map { GroupActorDTO(userId: $0) }
        default:
            return nil
        }
    }
}
