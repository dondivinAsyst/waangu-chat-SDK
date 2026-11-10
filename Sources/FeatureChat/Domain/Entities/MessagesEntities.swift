import Foundation
import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

public indirect enum MessageReply:  Equatable {
    case message(MessageDataItem?)
}

// MARK: - Message Enums
public enum MessageTypeProps: String,Codable {
    case TEXT
    case IMAGE
    case DOCUMENT
    case AUDIO
    case VOICE
    case VIDEO
    case VIDEO_NOTE
    case CONTACT
    case LOCATION
    case POLL
    case MISSING_CALL_AUDIO
    case MISSING_CALL_VIDEO
    case CALL_AUDIO
    case CALL_VIDEO
    case ISMONEY
    case GROUP_CREATED
    case GROUP_UPDATED
    case USER_ADDED_TO_GROUP
    case USER_JOINED_GROUP
    case USER_LEFT_GROUP
    case USER_REMOVED_FROM_GROUP
    case USER_PROMOTED_TO_ADMIN
    case USER_DEMOTED_FROM_ADMIN
    case STATUS
    case CHANNEL_INVITE

    /// A message whose media is a video file.
    ///
    /// A video note travels exactly like a video — same upload, same cache,
    /// same `content.video` — and only differs in its type and its bubble, so
    /// every place that handles a video handles both through this.
    public var isVideo: Bool {
        self == .VIDEO || self == .VIDEO_NOTE
    }

    /// A record of a membership or metadata change on a group, projected into the
    /// conversation by the backend.
    ///
    /// Like call records these were never transmitted by anyone, so they have no
    /// send lifecycle — no ticks, and no read receipt to return, because the id
    /// they carry may be one this device derived rather than one the server issued.
    public var isGroupEvent: Bool {
        switch self {
        case .GROUP_CREATED, .GROUP_UPDATED, .USER_ADDED_TO_GROUP, .USER_JOINED_GROUP,
             .USER_LEFT_GROUP, .USER_REMOVED_FROM_GROUP, .USER_PROMOTED_TO_ADMIN,
             .USER_DEMOTED_FROM_ADMIN:
            return true
        default:
            return false
        }
    }

    /// A record written into the thread rather than something a user sent.
    ///
    /// Nothing was transmitted, so there is no send lifecycle: nothing to be sent,
    /// delivered, read or retried. In particular none of these may be acknowledged
    /// with a read receipt — the id on one is a call or system id the server cannot
    /// resolve to a message, so the receipt is published against nothing.
    public var isSystemRecord: Bool {
        isCallEvent || isGroupEvent
    }

    /// A record of a call rather than something the user sent.
    ///
    /// Written locally when a call ends, and also projected into a conversation
    /// by the backend — so the local copy is not the only source. Either way
    /// nothing was transmitted, so there is no send lifecycle: nothing to be
    /// sent, delivered, read or retried. UI must not show delivery ticks for
    /// them, and they must never be acknowledged with a read receipt, because
    /// the id they carry is a call id the server cannot resolve to a message.
    public var isCallEvent: Bool {
        switch self {
        case .CALL_AUDIO, .CALL_VIDEO, .MISSING_CALL_AUDIO, .MISSING_CALL_VIDEO:
            return true
        default:
            return false
        }
    }
}

public enum MessageStatus: String ,Codable{
    case PENDING
    case SENT
    case DELIVERED
    case UNSEEN
    case SEEN
    case FAILED
    case MODIFY
}

// MARK: - Participants
public struct ParticipantItem: Identifiable, Codable {
    public var id: String = UUID().uuidString.lowercased()
    var name: String?
    var image: String?
    var phone: String
    /// Waangu account id. Optional because messages written before this existed
    /// have none — and because a call to an unknown number never had one.
    var userId: String?
    var status: String?
    var startedAt: Date?
    var endAt: Date?
}

// MARK: - Location
public struct CoordsLocation: Codable {
    var lat: Double
    var lng: Double
}

public struct ChatLocationItem: Codable {
    var coords: CoordsLocation
    var title: String?
    var address: String?
    var duration: Double?
    var distance: Double?

    // ── Live share ────────────────────────────────────────────
    // The anchor of a live location: the bubble persists, the GPS ticks that
    // move its pin do not. See `LiveLocationTick` for the ephemeral half.

    /// True when the sender started a live share from this message.
    var isLive: Bool?

    /// Identifies the share across participants, so ticks find their bubble.
    /// Defaults to the message's own `codeMessage` when the sender named none.
    var shareId: String?

    /// When the share stops accepting ticks.
    var expiresAt: Date?

    /// True while this bubble should follow live ticks.
    ///
    /// `isLive` alone never decides. It stays true for the life of the message —
    /// that is what lets an ended share still say it *was* one — so the deadline
    /// is the whole answer, and a share ends by its deadline passing.
    ///
    /// No deadline means ended, not eternal. The contract has no unbounded
    /// share: every start carries `expiresAt`. Treating a missing one as "still
    /// live" made any anchor that lost the field — an older row, a sender that
    /// omitted it — a bubble that claimed to be live on every launch, forever,
    /// with no countdown to contradict it.
    func isLiveActive(asOf now: Date = Date()) -> Bool {
        guard isLive == true, let expiresAt else { return false }
        return expiresAt > now
    }
}

// MARK: - Contact
public struct ContactItem: Codable {
    var id: String = UUID().uuidString.lowercased()
    var idContact: String?
    var userId: String
    var phone: String
    var name: String?
    var avatar: String?
    /// True when this phone is a registered Waangu user (directory lookup), not just a saved local contact.
    var isRegistered: Bool?
}

// MARK: - Calls
public enum CallScope: String, Codable {
    case group
    case `private`
}

public enum CallType: String, Codable {
    case video
    case audio
}

public struct CallContent: Codable {
    var callType: CallType = .audio
    var callScope: CallScope = .private
    var participants: [ParticipantItem]?
    var initiator: String?
    /// How the call actually ended, as `CallOutcome.rawValue`.
    ///
    /// The message type only distinguishes connected from not, so without this
    /// every unconnected outgoing call reads as "Cancelled" — including ones the
    /// server refused and ones that simply rang out. Optional because messages
    /// written before this field existed have none.
    var outcome: String?
}

// MARK: - Group Event Content

/// What a group system message carries beyond its text.
///
/// `MessageTypeModel` collapses every group event to `.system` in storage, so the
/// kind is kept here — the same job `callIsVideo` / `callConnected` do for calls.
/// The target and its name are what let the bubble say *who* was added, removed or
/// promoted, rather than falling back to the server's pre-rendered English.
public struct GroupEventContent: Codable {
    var eventType: String
    var targetUserId: String?
    var targetName: String?
    var groupTitle: String?
}

// MARK: - Channel Invite Content

/// Channel invitation card content sent via direct message.
///
/// When a channel owner invites contacts, each receives a DM with this embedded
/// invite card. The recipient can tap "Join Channel" to subscribe.
public struct ChannelInviteContent: Codable, Equatable {
    /// The channel being invited to
    public var channelId: String
    public var channelName: String
    public var channelImage: String?
    public var channelDescription: String?
    public var followerCount: Int
    /// User ID of who sent the invitation
    public var invitedBy: String
    /// Name of who sent the invitation (for display)
    public var inviterName: String?
    /// When the invitation was sent
    public var invitedAt: Date?
    
    public init(
        channelId: String,
        channelName: String,
        channelImage: String? = nil,
        channelDescription: String? = nil,
        followerCount: Int = 0,
        invitedBy: String,
        inviterName: String? = nil,
        invitedAt: Date? = nil
    ) {
        self.channelId = channelId
        self.channelName = channelName
        self.channelImage = channelImage
        self.channelDescription = channelDescription
        self.followerCount = followerCount
        self.invitedBy = invitedBy
        self.inviterName = inviterName
        self.invitedAt = invitedAt
    }
}

// MARK: - Message Content
public struct MessageContent {
    var text: String = ""
    var image: String?
    var UIimage: UIImage?
    var shouldUploadDownload: Bool = false
    var shouldRetry: Bool = false
    var audio: String?
    var video: String?
    var file: String?
    var fileName: String?
    var size: Int?
    var width: Int?
    var height: Int?
    /// Automatic transfer attempts already spent on this message's media.
    /// Local only — see `MessageContentModel.autoTransferAttempts`.
    var autoTransferAttempts: Int?
    var thumbnail: String?
    var remoteUri: String?
    var caption: String?
    var mimeType: String?
    var location: ChatLocationItem?
    var contact: [ContactItem]?
    var poll: PollContent?
    var call: CallContent?
    var groupEvent: GroupEventContent?
    var channelInvite: ChannelInviteContent?

    /// Carte financière portée par un message `ISMONEY`.
    ///
    /// À côté de `poll`, `call` et `groupEvent` : même schéma, un contenu riche
    /// par type de message. `nil` sur un message financier signifie que l'objet
    /// n'a pas encore été réconcilié — la bulle affiche alors une carte d'attente,
    /// jamais rien (voir `BubbleView`).
    var financial: FinancialCardPayload?

    /// Nature de l'objet financier, connue **avant** sa carte.
    ///
    /// Un message financier part avant que la carte ait été lue au serveur —
    /// une demande d'argent, toujours. Sans ce champ, sa nature ne voyageait
    /// qu'avec la carte : le destinataire recevait une demande sans type, et
    /// la lisait comme un paiement.
    var financialObjectType: FinancialObjectType? = nil

    var sticker: String?
    var url: String?
    var externalUrl: Bool = false
    var videoDuration: TimeInterval?
    var audioDuration: TimeInterval? // Duration of audio recording in seconds
    var waveform: [Float]?
    /// Set to a shared UUID when multiple images/videos are sent in one batch.
    /// Nil for single-item sends. Used by the timeline builder to form media groups.
    var mediaBatchId: String? = nil
    /// When this device used up a view-once message. Local only — see
    /// `MessageContentModel.viewOnceOpenedAt`.
    var viewOnceOpenedAt: Date? = nil
}

// MARK: - Reactions
public struct ReactionItem: Codable, Equatable {
    var userId: String
    var reaction: String
    
    public  static func == (lhs: ReactionItem, rhs: ReactionItem) -> Bool {
        lhs.userId == rhs.userId && lhs.reaction == rhs.reaction
    }
}
// MARK: - Media Group Model
public struct MediaGroup: Identifiable, Equatable {
    /// Stable id derived from messages (not UUID) so SwiftUI can diff correctly
    public let id: String
    let messages: [MessageDataItem]
    let isFromCurrentUser: Bool
    
    var count: Int { messages.count }
    
    public init(messages: [MessageDataItem], isFromCurrentUser: Bool) {
        self.id = "mediagroup_\(messages.first?.id ?? UUID().uuidString.lowercased())"
        self.messages = messages
        self.isFromCurrentUser = isFromCurrentUser
    }
}

// MARK: - Message Data
public struct MessageDataItem: Identifiable, Equatable  {
    var codeMessage: String
    var senderId: String = ""
    var senderAvatar: String?
    var senderPhone: String = ""
    var senderName: String = ""
    var receiverId: String = ""
    var groupId: String?
    var typeMessage: MessageTypeProps = .TEXT
    var message: MessageContent
    var reply: MessageReply? = nil
//    var statusDeleted: [String] = []
//    var deleteChat: [String] = []
//    var isDeleted: [String] = []
    var isDeleted: Bool = false
    var forwarded: Bool = false
    var reactions: [ReactionItem]? = []
    var status: MessageStatus = .PENDING
    var isMoney: Bool = false
    var isViewOnce: Bool = false
    var isEdited: Bool = false
    var editedAt: Date?
    var favority: [String] = []
    var transactionId: String?
    var createdAt: Date
    
    
    public var id: String { codeMessage }
    
    public static func == (lhs: MessageDataItem, rhs: MessageDataItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.senderId == rhs.senderId &&
        lhs.status == rhs.status &&
        lhs.isDeleted == rhs.isDeleted &&
        lhs.isEdited == rhs.isEdited &&
        lhs.groupId == rhs.groupId &&
        lhs.receiverId == rhs.receiverId &&
        lhs.message.text == rhs.message.text &&
        lhs.message.fileName == rhs.message.fileName &&
        lhs.message.shouldUploadDownload == rhs.message.shouldUploadDownload &&
        lhs.message.shouldRetry == rhs.message.shouldRetry &&
        lhs.reactions == rhs.reactions &&
        // A vote changes nothing else on the message, so without this a poll
        // whose bars just moved compares equal and the timeline diff decides
        // there is nothing to redraw.
        lhs.message.poll == rhs.message.poll &&
        replyIdentity(lhs.reply) == replyIdentity(rhs.reply)
    }

    private static func replyIdentity(_ reply: MessageReply?) -> String? {
        guard case .message(let item?) = reply else { return nil }
        return item.codeMessage
    }
    
    /// `groupId?.isEmpty` is an `Optional<Bool>`, so comparing it to nil only ever
    /// asked whether `groupId` was set — an empty string counted as a group.
    var isGroupChat: Bool { !(groupId?.isEmpty ?? true) }
    
    public var direction: MessageDirection { senderId == CurrentSessionInfo.shared.currentUid ? .sent : .received }
    
    var alignment: Alignment { direction == .received ? .leading : .trailing }
    var horizontalAlignment: HorizontalAlignment { direction == .received ? .leading : .trailing }
    var backgroundColor: Color {
        direction == .sent
            ? Color("bubbleSent", bundle: .module)
            : Color("bubbleReceived", bundle: .module)
    }
    var showGroupPartnerInfo: Bool { isGroupChat && direction == .received }

    /// A view-once message this device has already opened. Each side has its
    /// own copy, so the sender and the receiver each get one look.
    var isViewOnceOpened: Bool { isViewOnce && message.viewOnceOpenedAt != nil }

    /// Opened, but the content is still here — the app was closed while it was
    /// on screen. It is wiped the next time it is seen.
    var viewOnceNeedsWipe: Bool {
        isViewOnceOpened && (
            !message.text.isEmpty
                || message.audio != nil || message.video != nil || message.image != nil
                || message.file != nil || message.fileName != nil || message.remoteUri != nil
        )
    }
    
    var horizontalPadding: CGFloat = 25
    var leadingPadding: CGFloat { direction == .received ? 0 : horizontalPadding }
    var trailingPadding: CGFloat { direction == .received ? horizontalPadding : 0 }
    
    var imageSize: CGSize { CGSize(width: 30, height: 30) }
    
    var imageWidth: CGFloat { (UIScreen.main.bounds.width) / 1.5 }
    
    var audioDurationInString: String { "00:00" }
    var isSentByMe: Bool { senderId == CurrentSessionInfo.shared.currentUid }
    
    var menuAnchor: UnitPoint { direction == .received ? .leading : .trailing }
    var reactionAnchor: Alignment { direction == .sent ? .bottomTrailing : .bottomLeading }
    var hasReactions: Bool { reactions?.isEmpty == false }
    var currentUserHasReacted: Bool {
        reactions?.contains { $0.userId == CurrentSessionInfo.shared.currentUid } == true
    }
    var currentUserReaction: String? {
        reactions?.first { $0.userId == CurrentSessionInfo.shared.currentUid }?.reaction
    }
    
    func containsSameOwner(as message: MessageDataItem) -> Bool { false }
}


// MARK: - Date Formatting
extension MessageDataItem {
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()
    
    var displayTime: String {
//        Self.isoFormatter.date(from: createdAt).flatMap { Self.timeFormatter.string(from: $0) } ?? "N/A"
        createdAt.dayOrTimeRepresentation
    }

    /// Time-only stamp for in-chat bubbles (date is shown in the sticky section header).
    var bubbleTime: String {
        ChatTimeFormatting.formatTime(createdAt)
    }
}


// MARK: - Date Helpers
private extension Calendar {
    static let chatCalendar = Calendar.current
}

private extension DateFormatter {
    static let chatTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let chatWeekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE" // Monday, Tuesday, ...
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let chatShortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

// MARK: - Outgoing message local save

@MainActor
public final class OutgoingMessageLocallySavedEvent {
    public let conversationId: String
    public let message: MessageDataItem

    public init(conversationId: String, message: MessageDataItem) {
        self.conversationId = conversationId
        self.message = message
    }
}

