import Foundation

// MARK: - Conversation Type

public enum ConversationType: Hashable {
    /// `conversationId` is set when opening an existing chat from the list; nil for a brand-new chat.
    /// `peer` carries the identity the caller already holds — see `DirectChatPeer`.
    case direct(phoneNumber: String, conversationId: String?, peer: DirectChatPeer? = nil)
    case group(conversationId: String)

    var isGroup: Bool {
        if case .group = self { return true }
        return false
    }
}

// MARK: - Direct Chat Peer

/// Who is on the other side of a direct chat, when the caller already knows.
///
/// A phone number alone is not an identity. The room can only turn one into a
/// name, an avatar and — crucially — a `userId` by matching it against the
/// *current user's* own contacts, which misses for the case that matters most:
/// a number shared with you precisely because you don't have it. Every outbound
/// message carries `receiverId`, so a miss doesn't just blank the header, it
/// addresses the message to nobody.
///
/// A shared contact card already travels with all of this (`ContactPayloadDTO`),
/// so the bubble that opens the room hands it over rather than making the room
/// guess.
public struct DirectChatPeer: Hashable, Sendable {
    /// Waangu account id. This is what `receiverId` on the wire is built from.
    public let userId: String
    /// The current user's local address-book row id for this person, when saved.
    public let idContact: String
    public let name: String
    public let avatar: String

    public init(
        userId: String = "",
        idContact: String = "",
        name: String = "",
        avatar: String = ""
    ) {
        self.userId = userId
        self.idContact = idContact
        self.name = name
        self.avatar = avatar
    }

    /// A directory row already carries every field this needs.
    public init(contact: UserContactProps) {
        self.init(
            userId: contact.userId,
            idContact: contact.idContact ?? "",
            name: contact.name,
            avatar: contact.avatar ?? ""
        )
    }

    /// Nothing here worth preferring over a local lookup.
    var isEmpty: Bool {
        userId.isEmpty && idContact.isEmpty && name.isEmpty && avatar.isEmpty
    }
}

// MARK: - Typing User

/// One peer typing (or recording) in one conversation.
///
/// Identity is the pair `senderId` + `conversationId`: the same person typing
/// in two conversations is two entries, and a name is not an identity — the
/// server fills it with a phone number when it cannot resolve a display name.
public struct TypingUser: Identifiable, Equatable {
    /// Display name, already resolved against the local contact book where
    /// possible. Falls back to whatever the server sent, phone number included.
    var name: String = ""
    /// Wire event: "typing", "recordingVoice", "recordingVideo".
    var msg: String = ""
    var senderId: String = ""
    var conversationId: String = ""
    var groupeId: String = ""
    var messageType: MessageTypeProps = .TEXT

    public var id: String { "\(senderId)@\(conversationId)" }
}

// MARK: - Conversation Settings
public struct UserConversationSetting: Equatable,Codable {
    var user: String? = nil
    var conversation: String? = nil
    var isMuted: Bool? = nil
    var muteStartAt: Date? = nil
    var muteEndAt: Date? = nil
    var isPinned: Bool? = nil
    var pinnedAt: Date? = nil
    var isMyFavority: Bool? = nil
    var favorityAt: Date? = nil
    var isArchived: Bool? = nil
    var archivedAt: Date? = nil
    var ephemeralMessageDuration: Int? = nil
    var ephemeralStartAt: Date? = nil
    var ephemeralEndAt: Date? = nil
    var lastReadMessage: String? = nil
    var lastReadAt: Date? = nil
    var createdAt: Date? = nil
    var updatedAt: Date? = nil
    
    public static func == (lhs: UserConversationSetting, rhs: UserConversationSetting) -> Bool {
        lhs.user == rhs.user &&
        lhs.conversation == rhs.conversation &&
        lhs.isMuted == rhs.isMuted &&
        lhs.muteStartAt == rhs.muteStartAt &&
        lhs.muteEndAt == rhs.muteEndAt &&
        lhs.isPinned == rhs.isPinned &&
        lhs.pinnedAt == rhs.pinnedAt &&
        lhs.isMyFavority == rhs.isMyFavority &&
        lhs.favorityAt == rhs.favorityAt &&
        lhs.archivedAt == rhs.archivedAt &&
        lhs.ephemeralMessageDuration == rhs.ephemeralMessageDuration &&
        lhs.ephemeralStartAt == rhs.ephemeralStartAt &&
        lhs.ephemeralEndAt == rhs.ephemeralEndAt &&
        lhs.lastReadMessage == rhs.lastReadMessage &&
        lhs.lastReadAt == rhs.lastReadAt
    }
}

// MARK: - Contact Channel
public struct ContactChannel: Identifiable, Equatable,Codable {
    var userName: String = ""
    var phone: String = ""
    var image: String? = nil
    var isBlocked: Bool
    var isGroup: Bool = false  // NEW: Explicitly mark if this is a group chat
    /// A canal Updates (Core `BROADCAST`). Rooms like this are read-only for
    /// everyone but the channel's owner and admins, so the row has to say which
    /// kind of multi-party thread it is — `isGroup` alone cannot.
    var isChannel: Bool = false
    
    public var id: String = ""
    /// Waangu account id — distinct from `id` (contact record id).
    var userId: String = ""
    /// The Waangu Copilot conversation — on this device only. Optional so rows
    /// encoded before it existed still decode.
    var isCopilot: Bool? = nil

    var isCopilotChat: Bool { isCopilot == true }
}

// MARK: - Discussion Chat Item
public struct DiscussionChatItem: Identifiable, Equatable {
    var lastMessage: MessageDataItem
    var conversationId: String = ""
    var contact: ContactChannel? = nil
//    var contact: WaanguContact? = nil
    var count: Int = 0
    var setting: UserConversationSetting? = nil
    /// Composer text left behind in the room. When set, the list row shows it
    /// instead of `lastMessage`. Nil when there is nothing to show.
    var draft: String? = nil
    
    public var id: String { conversationId }
    
    /// Hand-written, and `ChannelTabViewModel.arraysHaveSameContent` uses it to
    /// decide whether the list is worth republishing — so a field left out here
    /// is a field that never reaches the screen.
    public static func == (lhs: DiscussionChatItem, rhs: DiscussionChatItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.conversationId == rhs.conversationId &&
        lhs.count == rhs.count &&
        lhs.draft == rhs.draft &&
        lhs.lastMessage.codeMessage == rhs.lastMessage.codeMessage &&
        lhs.lastMessage.typeMessage == rhs.lastMessage.typeMessage &&
        lhs.lastMessage.message.text == rhs.lastMessage.message.text &&
        lhs.lastMessage.isEdited == rhs.lastMessage.isEdited &&
        lhs.lastMessage.status == rhs.lastMessage.status &&
        lhs.contact?.image == rhs.contact?.image
    }
}


// MARK: - Selected Image
final class SelectedImage {
    var id: String = ""
}
