// FeatureChat/Data/DTOs/MessageDTO.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: OutboundMessageDTO
// ─────────────────────────────────────────────────────────────
// Flat server wire format published via MQTT / outbox.

public struct OutboundMessageDTO: Codable, Sendable, Equatable {

    /// Redis Identity session — required by realtime for MQTT auth.
    public let sessionId: String
    public let senderId: String
    public let senderName: String
    public let senderPhone: String
    public let senderAvatar: String?
    public let receiverId: String
    public let groupId: String?
    public let conversationId: String
    public let codeMessage: String
    /// JSON string of `MessageContentDTO` — reply snapshot lives inside this payload.
    public let content: String
    public let typeMessage: String
    public let status: String
    public let forwarded: Bool
    public let viewOnce: Bool?
    public let isMoney: Bool
    public let transactionId: String?
    public let isMessageSystem: Bool?
    public let tenantId: String?
    public let country: String?
    /// A new lowercase UUID on **every** send attempt, retries included, while
    /// `codeMessage` stays the same. Set only by `withFreshNonce()` right before
    /// a publish, and never stored: the outbox saves the message without it.
    /// `nil` (and absent from the JSON) everywhere else.
    public var nonce: String?

    public init(
        sessionId: String,
        senderId: String,
        senderName: String,
        senderPhone: String,
        senderAvatar: String?,
        receiverId: String,
        groupId: String?,
        conversationId: String,
        codeMessage: String,
        content: String,
        typeMessage: String,
        status: String,
        forwarded: Bool,
        viewOnce: Bool? = nil,
        isMoney: Bool,
        transactionId: String? = nil,
        isMessageSystem: Bool? = nil,
        tenantId: String? = nil,
        country: String? = nil,
        nonce: String? = nil
    ) {
        self.sessionId = sessionId
        self.senderId = senderId
        self.senderName = senderName
        self.senderPhone = senderPhone
        self.senderAvatar = senderAvatar
        self.receiverId = receiverId
        self.groupId = groupId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
        self.content = content
        self.typeMessage = typeMessage
        self.status = status
        self.forwarded = forwarded
        self.viewOnce = viewOnce
        self.isMoney = isMoney
        self.transactionId = transactionId
        self.isMessageSystem = isMessageSystem
        self.tenantId = tenantId
        self.country = country
        self.nonce = nonce
    }

    /// This message for one send attempt: the same message, with a new nonce.
    /// Call it right before each `publish` — first send and every retry.
    public func withFreshNonce() -> OutboundMessageDTO {
        var attempt = self
        attempt.nonce = UUID().uuidString.lowercased()
        return attempt
    }

    /// This message as the outbox stores it: without a nonce.
    public func withoutNonce() -> OutboundMessageDTO {
        var stored = self
        stored.nonce = nil
        return stored
    }

    /// Backward-compatible alias used by outbox / flush handlers.
    public var id: String { codeMessage }
}

// ─────────────────────────────────────────────────────────────
// MARK: InboundMessageDTO
// ─────────────────────────────────────────────────────────────
// Flat server wire format received via MQTT / sync pull.

public struct InboundMessageDTO: Codable, Sendable, Equatable {

    public let senderId: String
    public let senderName: String
    public let senderPhone: String?
    public let senderAvatar: String?
    public let receiverId: String?
    public let groupId: String?
    public let conversationId: String?  // Optional: not present in conversation sync nested messages
    public let codeMessage: String
    /// JSON string of `MessageContentDTO` — reply snapshot lives inside this payload.
    public let content: String
    /// Legacy top-level reply JSON. Prefer `messageContent.replyTo*`.
    public let reply: String?
    public let typeMessage: String
    public let status: String?
    public let forwarded: Bool?
    public let viewOnce: Bool?
    public let isMoney: Bool?
    public let transactionId: String?
    public let isMessageSystem: Bool?
    public let tenantId: String?
    public let country: String?
    public let timestamp: Double?

    public init(
        senderId: String,
        senderName: String,
        senderPhone: String? = nil,
        senderAvatar: String? = nil,
        receiverId: String? = nil,
        groupId: String? = nil,
        conversationId: String? = nil,  // Made optional
        codeMessage: String,
        content: String,
        reply: String? = nil,
        typeMessage: String,
        status: String? = nil,
        forwarded: Bool? = nil,
        viewOnce: Bool? = nil,
        isMoney: Bool? = nil,
        transactionId: String? = nil,
        isMessageSystem: Bool? = nil,
        tenantId: String? = nil,
        country: String? = nil,
        timestamp: Double? = nil
    ) {
        self.senderId = senderId
        self.senderName = senderName
        self.senderPhone = senderPhone
        self.senderAvatar = senderAvatar
        self.receiverId = receiverId
        self.groupId = groupId
        self.conversationId = conversationId
        self.codeMessage = codeMessage
        self.content = content
        self.reply = reply
        self.typeMessage = typeMessage
        self.status = status
        self.forwarded = forwarded
        self.viewOnce = viewOnce
        self.isMoney = isMoney
        self.transactionId = transactionId
        self.isMessageSystem = isMessageSystem
        self.tenantId = tenantId
        self.country = country
        self.timestamp = timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        senderId = try container.decode(String.self, forKey: .senderId)
        senderName = try container.decode(String.self, forKey: .senderName)
        senderPhone = try container.decodeIfPresent(String.self, forKey: .senderPhone)
        senderAvatar = try container.decodeIfPresent(String.self, forKey: .senderAvatar)
        receiverId = try container.decodeIfPresent(String.self, forKey: .receiverId)
        groupId = try container.decodeIfPresent(String.self, forKey: .groupId)
        conversationId = try container.decodeIfPresent(String.self, forKey: .conversationId)  // Made optional
//        oldConversationId = try container.decodeIfPresent(String.self, forKey: .oldConversationId)

        if let code = try container.decodeIfPresent(String.self, forKey: .codeMessage) {
            codeMessage = code
        } else if let legacyId = try container.decodeIfPresent(String.self, forKey: .id) {
            codeMessage = legacyId
        } else {
            throw DecodingError.keyNotFound(
                CodingKeys.codeMessage,
                .init(codingPath: decoder.codingPath, debugDescription: "Missing codeMessage or id")
            )
        }

        content = try Self.decodeContent(from: container)
        reply = try container.decodeIfPresent(String.self, forKey: .reply)

        if let type = try container.decodeIfPresent(String.self, forKey: .typeMessage) {
            typeMessage = type
        } else if let legacyType = try container.decodeIfPresent(String.self, forKey: .type) {
            typeMessage = legacyType.uppercased()
        } else {
            typeMessage = "TEXT"
        }

        status = try container.decodeIfPresent(String.self, forKey: .status)
        if let value = try container.decodeIfPresent(Bool.self, forKey: .forwarded) {
            forwarded = value
        } else {
            forwarded = try container.decodeIfPresent(Bool.self, forKey: .isForwarded)
        }
        if let value = try container.decodeIfPresent(Bool.self, forKey: .viewOnce) {
            viewOnce = value
        } else {
            viewOnce = try container.decodeIfPresent(Bool.self, forKey: .isViewOnce)
        }
        isMoney = try container.decodeIfPresent(Bool.self, forKey: .isMoney)
        transactionId = try container.decodeIfPresent(String.self, forKey: .transactionId)
        isMessageSystem = try container.decodeIfPresent(Bool.self, forKey: .isMessageSystem)
        tenantId = try container.decodeIfPresent(String.self, forKey: .tenantId)
        country = try container.decodeIfPresent(String.self, forKey: .country)
        if let epoch = try container.decodeIfPresent(Double.self, forKey: .timestamp) {
            timestamp = epoch
        } else if let sentAt = try container.decodeIfPresent(String.self, forKey: .sentAt) {
            timestamp = Self.parseSentAt(sentAt)
        } else {
            timestamp = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(senderId, forKey: .senderId)
        try container.encode(senderName, forKey: .senderName)
        try container.encodeIfPresent(senderPhone, forKey: .senderPhone)
        try container.encodeIfPresent(senderAvatar, forKey: .senderAvatar)
        try container.encodeIfPresent(receiverId, forKey: .receiverId)
        try container.encodeIfPresent(groupId, forKey: .groupId)
        try container.encode(conversationId, forKey: .conversationId)
//        try container.encodeIfPresent(oldConversationId, forKey: .oldConversationId)
        try container.encode(codeMessage, forKey: .codeMessage)
        try container.encode(content, forKey: .content)
        // Reply snapshot is embedded in `content` (MessageContentDTO). Do not re-emit top-level `reply`.
        try container.encode(typeMessage, forKey: .typeMessage)
        try container.encodeIfPresent(status, forKey: .status)
        try container.encodeIfPresent(forwarded, forKey: .forwarded)
        try container.encodeIfPresent(viewOnce, forKey: .viewOnce)
        try container.encodeIfPresent(isMoney, forKey: .isMoney)
        try container.encodeIfPresent(transactionId, forKey: .transactionId)
        try container.encodeIfPresent(isMessageSystem, forKey: .isMessageSystem)
        try container.encodeIfPresent(tenantId, forKey: .tenantId)
        try container.encodeIfPresent(country, forKey: .country)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
    }

    private enum CodingKeys: String, CodingKey {
        case senderId, senderName, senderPhone, senderAvatar
        case receiverId, groupId, conversationId, oldConversationId
        case codeMessage, id, content, reply
        case typeMessage, type, status
        case forwarded, isForwarded, viewOnce, isViewOnce
        case isMoney, transactionId, isMessageSystem, tenantId, country, timestamp, sentAt
    }

    /// Backward-compatible alias for mappers.
    public var id: String { codeMessage }

    /// Lowercase type for legacy inbound mapping.
    public var type: String { typeMessage.lowercased() }

    public var resolvedTimestamp: Double {
        groupEventTimestamp ?? timestamp ?? Date().timeIntervalSince1970
    }

    /// A group event's own `createdAt` sits inside its content and is when the
    /// change actually happened — it outranks the envelope's `sentAt`, which is
    /// only when the server got round to forwarding it, and it is the only source
    /// at all when the envelope carries no time.
    ///
    /// Restricted to group events: an ordinary message's content may carry an
    /// unrelated `createdAt`, and it must not displace the envelope's.
    private var groupEventTimestamp: Double? {
        guard resolvedGroupEvent != nil,
              let createdAt = messageContent.createdAt,
              createdAt > 0
        else { return nil }
        return createdAt > 10_000_000_000 ? createdAt / 1000 : createdAt
    }

    public var replyToMessageId: String? {
        messageContent.replyToMessageId ?? legacyParsedReply?.replyToMessageId
    }
    public var replyToSenderName: String? {
        messageContent.replyToSenderName ?? legacyParsedReply?.replyToSenderName
    }
    public var replyToMessageType: String? {
        messageContent.replyToMessageType ?? legacyParsedReply?.replyToMessageType
    }
    public var replyToMessagePreview: String? {
        messageContent.replyToMessagePreview ?? legacyParsedReply?.replyToMessagePreview
    }
    public var replyToThumbnailURL: String? {
        messageContent.replyToThumbnailURL ?? legacyParsedReply?.replyToThumbnailURL
    }

    public var isForwarded: Bool? { forwarded }

    public var messageContent: MessageContentDTO {
        MessageContentWireCodec.decode(content, typeMessage: typeMessage)
    }

    private var legacyParsedReply: ReplyWire? {
        MessageReplyWireCodec.decode(reply)
    }

    /// `content` is a JSON string for ordinary messages, but system records — the
    /// ones the backend projects into a thread — send it as a nested object.
    ///
    /// Decoding it strictly as a string threw, and because `decodePayload` swallows
    /// the error with `try?` the whole message vanished without a trace. Accepting
    /// both and re-serialising the object keeps one representation downstream.
    private static func decodeContent(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> String {
        if let raw = try? container.decode(String.self, forKey: .content) {
            return raw
        }

        let object = try container.decode(CodableValue.self, forKey: .content)
        if case .null = object {
            throw DecodingError.dataCorruptedError(
                forKey: .content,
                in: container,
                debugDescription: "content is null"
            )
        }
        guard let data = try? JSONEncoder().encode(object),
              let json = String(data: data, encoding: .utf8) else {
            throw DecodingError.dataCorruptedError(
                forKey: .content,
                in: container,
                debugDescription: "content object could not be re-encoded"
            )
        }
        return json
    }

    private static func parseSentAt(_ value: String) -> Double? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)?.timeIntervalSince1970
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: MessageContentDTO
// ─────────────────────────────────────────────────────────────
// Internal structured content — used when mapping to MessageModel.

public struct MessageContentDTO: Codable, Sendable {
    public let text:                String?
    public let url:                 String?
    public let thumbnailURL:        String?
    public let mimeType:            String?
    public let fileSize:            Int?
    public let fileName:            String?
    public let width:               Int?
    public let height:              Int?
    public let durationSeconds:     Double?
    public let waveform:            [Float]?
    /// Shared by every photo and video sent in one batch, so the receiver's
    /// timeline groups them the way the sender's already does. Nil for a single
    /// send — the key is simply absent on an ordinary message.
    public let mediaBatchId:        String?
    public let latitude:            Double?
    public let longitude:           Double?
    public let locationName:        String?
    public let locationAddress:     String?
    public let liveDurationSeconds: Int?
    /// The nested form, which is the only place the live share fields appear.
    /// Absent on an ordinary pinned location from a build that predates it.
    public let location:            MessageLocationPayloadDTO?
    public let contactName:         String?
    public let contactPhone:        String?
    public let contactVCard:        String?
    /// True when the shared contact phone belongs to a registered Waangu user.
    public let isRegistered:        Bool?
    /// The shared contact's Waangu account id, on the flat one-contact shape
    /// that carries no `contacts` array. Spelled `userId` because that is the
    /// key on the wire — Android sends it beside `contactName`/`contactPhone`.
    /// Without it the card cannot open a chat and has to guess from the phone.
    public let userId:              String?
    /// Every contact shared in one send, in the order the sender picked them.
    ///
    /// `contactName` / `contactPhone` / `isRegistered` above describe only the
    /// first of these, and stay on the wire so a receiver that predates this
    /// field — Android, or an older build — still renders that one. Anyone who
    /// reads this array gets the whole selection, with the account id and avatar
    /// the flat fields have no room for.
    public let contacts:            [ContactPayloadDTO]?
    public let pollQuestion:        String?
    public let pollOptions:         [PollOptionDTO]?
    public let pollIsMultipleChoice: Bool?
    public let pollIsClosed:        Bool?
    public let paymentAmount:       Double?
    public let paymentCurrency:     String?
    public let paymentStatus:       String?
    public let paymentRef:          String?
    /// Nature de l'objet (`FinancialObjectType.rawValue`) et sa révision.
    ///
    /// Sans eux, le destinataire ne pouvait pas choisir de carte : il gardait
    /// la carte d'attente tant que le backend n'avait pas été relu — et aucune
    /// route de lecture n'existe encore. Absents d'un client qui ne les envoie
    /// pas encore, ce qui ramène exactement au comportement d'avant.
    public let financialObjectType:    String?
    public let financialObjectVersion: Int?
    public let rideStatus:          String?
    public let rideETA:             Int?
    public let rideOrigin:          String?
    public let rideDestination:     String?
    public let orderStatus:         String?
    public let orderRef:            String?
    public let callType:            String?
    public let callDuration:        Int?
    /// How the call ended, as `CallOutcome.rawValue`, for call records the
    /// server projects into the thread rather than the device writing them.
    public let callOutcome:         String?

    // Reply snapshot (chat message or status) — embedded in content JSON
    public let replyToMessageId:      String?
    public let replyToSenderName:     String?
    public let replyToMessageType:    String?
    public let replyToMessagePreview: String?
    public let replyToThumbnailURL:   String?

    // ── Group system event ────────────────────────────────────
    //
    // Read straight off the wire's own content object. This is the only
    // representation every inbound path shares: MQTT, pull-events and the inbox
    // summary all reach `InboundMessageDTO`, but only MQTT passes through a
    // parser, and `typeMessage` says a useless `"SYSTEM"` on the other two.
    // Anything that decides what a message *is* must look here, not at the type.
    /// Who the event is about. Its meaning is the event's: the full initial roster
    /// on `GROUP_CREATED`, and just the affected member on everything else. Empty
    /// on `GROUP_UPDATED`, which is about the group rather than anyone in it.
    public let targetUsers:    [GroupRosterParticipantDTO]?
    public let groupDescription: String?
    public let groupAvatar:      String?
    public let groupAvatarUrl:   String?
    public let groupInviteLink:  String?
    public let groupIsLocked:    Bool?

    // Earlier spellings of the same facts, still accepted so a device mid-rollout
    // reads both. `eventType` in particular used to be the only place the kind
    // appeared; it now rides on `typeMessage`.
    public let eventType:      String?
    public let targetUserId:   String?
    public let participants:   [GroupRosterParticipantDTO]?
    public let title:          String?
    public let createdBy:      GroupActorDTO?
    public let addedBy:        GroupActorDTO?
    public let removedBy:      GroupActorDTO?
    public let changedBy:      GroupActorDTO?
    public let updatedBy:      GroupActorDTO?
    public let avatarUrl:      String?
    public let avatar:         String?
    /// Epoch millis on the wire.
    public let createdAt:      Double?

    // The same facts after normalization, as stored. Present so a message read
    // back from the database resolves identically to one off the wire.
    public let groupEventType:     String?
    public let groupTargetUserId:  String?
    public let groupTargetName:    String?
    public let groupTitle:         String?

    public init(
        text: String? = nil,
        url: String? = nil,
        thumbnailURL: String? = nil,
        mimeType: String? = nil,
        fileSize: Int? = nil,
        fileName: String? = nil,
        width: Int? = nil,
        height: Int? = nil,
        durationSeconds: Double? = nil,
        waveform: [Float]? = nil,
        mediaBatchId: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        locationName: String? = nil,
        locationAddress: String? = nil,
        liveDurationSeconds: Int? = nil,
        location: MessageLocationPayloadDTO? = nil,
        contactName: String? = nil,
        contactPhone: String? = nil,
        contactVCard: String? = nil,
        isRegistered: Bool? = nil,
        userId: String? = nil,
        contacts: [ContactPayloadDTO]? = nil,
        pollQuestion: String? = nil,
        pollOptions: [PollOptionDTO]? = nil,
        pollIsMultipleChoice: Bool? = nil,
        pollIsClosed: Bool? = nil,
        paymentAmount: Double? = nil,
        paymentCurrency: String? = nil,
        paymentStatus: String? = nil,
        paymentRef: String? = nil,
        financialObjectType: String? = nil,
        financialObjectVersion: Int? = nil,
        rideStatus: String? = nil,
        rideETA: Int? = nil,
        rideOrigin: String? = nil,
        rideDestination: String? = nil,
        orderStatus: String? = nil,
        orderRef: String? = nil,
        callType: String? = nil,
        callDuration: Int? = nil,
        callOutcome: String? = nil,
        replyToMessageId: String? = nil,
        replyToSenderName: String? = nil,
        replyToMessageType: String? = nil,
        replyToMessagePreview: String? = nil,
        replyToThumbnailURL: String? = nil,
        targetUsers: [GroupRosterParticipantDTO]? = nil,
        groupDescription: String? = nil,
        groupAvatar: String? = nil,
        groupAvatarUrl: String? = nil,
        groupInviteLink: String? = nil,
        groupIsLocked: Bool? = nil,
        eventType: String? = nil,
        targetUserId: String? = nil,
        participants: [GroupRosterParticipantDTO]? = nil,
        title: String? = nil,
        createdBy: GroupActorDTO? = nil,
        addedBy: GroupActorDTO? = nil,
        removedBy: GroupActorDTO? = nil,
        changedBy: GroupActorDTO? = nil,
        updatedBy: GroupActorDTO? = nil,
        avatarUrl: String? = nil,
        avatar: String? = nil,
        createdAt: Double? = nil,
        groupEventType: String? = nil,
        groupTargetUserId: String? = nil,
        groupTargetName: String? = nil,
        groupTitle: String? = nil
    ) {
        self.text = text
        self.url = url
        self.thumbnailURL = thumbnailURL
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.fileName = fileName
        self.width = width
        self.height = height
        self.durationSeconds = durationSeconds
        self.waveform = waveform
        self.mediaBatchId = mediaBatchId
        self.latitude = latitude
        self.longitude = longitude
        self.locationName = locationName
        self.locationAddress = locationAddress
        self.liveDurationSeconds = liveDurationSeconds
        self.location = location
        self.contactName = contactName
        self.contactPhone = contactPhone
        self.contactVCard = contactVCard
        self.isRegistered = isRegistered
        self.userId = userId
        self.contacts = contacts
        self.pollQuestion = pollQuestion
        self.pollOptions = pollOptions
        self.pollIsMultipleChoice = pollIsMultipleChoice
        self.pollIsClosed = pollIsClosed
        self.paymentAmount = paymentAmount
        self.paymentCurrency = paymentCurrency
        self.paymentStatus = paymentStatus
        self.paymentRef = paymentRef
        self.financialObjectType = financialObjectType
        self.financialObjectVersion = financialObjectVersion
        self.rideStatus = rideStatus
        self.rideETA = rideETA
        self.rideOrigin = rideOrigin
        self.rideDestination = rideDestination
        self.orderStatus = orderStatus
        self.orderRef = orderRef
        self.callType = callType
        self.callDuration = callDuration
        self.callOutcome = callOutcome
        self.replyToMessageId = replyToMessageId
        self.replyToSenderName = replyToSenderName
        self.replyToMessageType = replyToMessageType
        self.replyToMessagePreview = replyToMessagePreview
        self.replyToThumbnailURL = replyToThumbnailURL
        self.targetUsers = targetUsers
        self.groupDescription = groupDescription
        self.groupAvatar = groupAvatar
        self.groupAvatarUrl = groupAvatarUrl
        self.groupInviteLink = groupInviteLink
        self.groupIsLocked = groupIsLocked
        self.eventType = eventType
        self.targetUserId = targetUserId
        self.participants = participants
        self.title = title
        self.createdBy = createdBy
        self.addedBy = addedBy
        self.removedBy = removedBy
        self.changedBy = changedBy
        self.updatedBy = updatedBy
        self.avatarUrl = avatarUrl
        self.avatar = avatar
        self.createdAt = createdAt
        self.groupEventType = groupEventType
        self.groupTargetUserId = groupTargetUserId
        self.groupTargetName = groupTargetName
        self.groupTitle = groupTitle
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: GroupActorDTO
// ─────────────────────────────────────────────────────────────

/// Whoever performed a group event.
///
/// Sent as a full object on the live wire and as a bare id in the flat form, so
/// both decode. The name matters as much as the id: the message envelope around a
/// group event says `senderId: "system"`, so this is the only place the person's
/// name can come from.
public struct GroupActorDTO: Codable, Sendable {
    public let userId:   String
    public let username: String?
    public let phone:    String?
    public let role:     String?

    public var displayName: String? {
        username.flatMap { $0.isEmpty ? nil : $0 }
    }

    public init(userId: String, username: String? = nil, phone: String? = nil, role: String? = nil) {
        self.userId = userId
        self.username = username
        self.phone = phone
        self.role = role
    }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(),
           let id = try? single.decode(String.self) {
            self.init(userId: id)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            userId: try container.decode(String.self, forKey: .userId),
            username: try container.decodeIfPresent(String.self, forKey: .username),
            phone: try container.decodeIfPresent(String.self, forKey: .phone),
            role: try container.decodeIfPresent(String.self, forKey: .role)
        )
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: MessageLocationPayloadDTO
// ─────────────────────────────────────────────────────────────

/// The `location` object of a `LOCATION` message's content.
///
/// The live location contract nests the position here, alongside the fields
/// that describe the share. The flat `latitude` / `longitude` / `locationName`
/// / `locationAddress` on `MessageContentDTO` carry the same position and stay
/// on the wire beside this — a build that predates live sharing reads those and
/// still renders the pin. Only the share itself lives here, since nothing older
/// has anywhere to put it.
public struct MessageLocationPayloadDTO: Codable, Sendable {
    public let latitude:        Double?
    public let longitude:       Double?
    public let title:           String?
    public let address:         String?
    public let isLive:          Bool?
    public let shareId:         String?
    /// Epoch millis on the wire, as everywhere else in this file.
    public let expiresAt:       Double?
    public let durationMinutes: Int?

    public init(
        latitude: Double? = nil,
        longitude: Double? = nil,
        title: String? = nil,
        address: String? = nil,
        isLive: Bool? = nil,
        shareId: String? = nil,
        expiresAt: Double? = nil,
        durationMinutes: Int? = nil
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.title = title
        self.address = address
        self.isLive = isLive
        self.shareId = shareId
        self.expiresAt = expiresAt
        self.durationMinutes = durationMinutes
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: PollOptionDTO
// ─────────────────────────────────────────────────────────────

public struct PollOptionDTO: Codable, Sendable {
    public let id:        String
    public let text:      String
    public let voterIds:  [String]?
    public let voteCount: Int?
}

// ─────────────────────────────────────────────────────────────
// MARK: ContactPayloadDTO
// ─────────────────────────────────────────────────────────────

/// One shared contact as it travels.
///
/// The sender's own address-book row id is deliberately absent: it identifies a
/// record on their device, is meaningless on the receiver's, and matching a
/// shared contact against the receiver's address book is done by phone anyway.
/// `userId` is the opposite — it is the Waangu account id, and it is what lets
/// the receiver open a chat with this person rather than guessing from a number.
public struct ContactPayloadDTO: Codable, Sendable {
    /// Stable within one message, so the shared-contacts list keeps its identity
    /// across re-renders. Optional because a sender may omit it; the receiver
    /// falls back to the phone, which is unique within a selection.
    public let id:           String?
    public let userId:       String?
    public let phone:        String
    public let name:         String?
    public let avatar:       String?
    public let isRegistered: Bool?

    public init(
        id: String? = nil,
        userId: String? = nil,
        phone: String,
        name: String? = nil,
        avatar: String? = nil,
        isRegistered: Bool? = nil
    ) {
        self.id = id
        self.userId = userId
        self.phone = phone
        self.name = name
        self.avatar = avatar
        self.isRegistered = isRegistered
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Reply wire codec (legacy top-level reply JSON + helpers)
// ─────────────────────────────────────────────────────────────

struct ReplyWire: Codable, Sendable {
    let replyToMessageId: String?
    let replyToSenderName: String?
    let replyToMessageType: String?
    let replyToMessagePreview: String?
    let replyToThumbnailURL: String?
}

enum MessageReplyWireCodec {

    static func fields(from reply: MessageReply?) -> ReplyWire? {
        guard case .message(let item?) = reply else { return nil }
        return ReplyWire(
            replyToMessageId: item.codeMessage,
            replyToSenderName: item.senderName.isEmpty ? nil : item.senderName,
            replyToMessageType: item.typeMessage.rawValue,
            replyToMessagePreview: replyPreview(for: item),
            replyToThumbnailURL: item.message.thumbnail ?? item.message.image
        )
    }

    /// Legacy decode for inbound payloads that still send top-level `reply`.
    static func decode(_ reply: String?) -> ReplyWire? {
        guard let reply, !reply.isEmpty, let data = reply.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ReplyWire.self, from: data)
    }

    static func replyPreview(for message: MessageDataItem) -> String? {
        if message.isViewOnce { return "View once message" }
        let text = message.message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }
        switch message.typeMessage {
        case .IMAGE:         return "Photo"
        case .VIDEO:         return "Video"
        case .VIDEO_NOTE:    return "Video note"
        case .STATUS:        return StatusReplySnapshotBuilder.previewLabel
        case .AUDIO, .VOICE: return "Audio"
        case .DOCUMENT:      return "Document"
        case .LOCATION:      return "Location"
        case .CONTACT:       return "Contact"
        case .POLL:          return "Poll"
        case .ISMONEY:       return "Payment"
        default:             return nil
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Content wire codec (content JSON string ↔ MessageContentDTO)
// ─────────────────────────────────────────────────────────────

enum MessageContentWireCodec {

    static func encode(from message: MessageDataItem) -> String {
        encode(dto: buildContentDTO(from: message)) ?? message.message.text
    }

    static func encode(dto: MessageContentDTO) -> String? {
        guard let data = try? JSONEncoder().encode(dto) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func decode(_ content: String, typeMessage: String) -> MessageContentDTO {
        guard let data = content.data(using: .utf8) else {
            return legacyPlainContent(content, typeMessage: typeMessage)
        }

        if let dto = try? JSONDecoder().decode(MessageContentDTO.self, from: data) {
            return dto
        }

        // A sender that spells a number as a string used to lose the entire
        // content object here. Android sends `"width":"1280"`; `Int?` rejects it,
        // the strict decode above throws, and `legacyPlainContent` then hands
        // `url` the whole JSON blob — so the message arrived with no image, no
        // thumbnail and no size, while looking perfectly fine on the wire.
        //
        // Reached only once the strict decode has already failed, so every
        // payload that decodes today still takes exactly the path it took before.
        if let repaired = InboundContentJSONRepair.repaired(data),
           let dto = try? JSONDecoder().decode(MessageContentDTO.self, from: repaired) {
            return dto
        }

        #if DEBUG
        // Worth saying out loud: the `try?` above is why this class of bug was
        // invisible. Only for content that meant to be an object — an ordinary
        // legacy plain-text body is not a failure.
        if content.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            print("[MessageContentWireCodec] Undecodable \(typeMessage) content, "
                  + "falling back to plain: \(content.prefix(300))")
        }
        #endif

        return legacyPlainContent(content, typeMessage: typeMessage)
    }

    static func buildContentDTO(from message: MessageDataItem) -> MessageContentDTO {
        let content = message.message
        let reply = MessageReplyWireCodec.fields(from: message.reply)
        return MessageContentDTO(
            text: content.text.isEmpty ? nil : content.text,
            url: content.remoteUri
                ?? content.image
                ?? content.video
                ?? content.audio
                ?? content.file
                ?? content.url,
            thumbnailURL: content.thumbnail,
            mimeType: content.mimeType,
            fileSize: content.size,
            fileName: content.fileName,
            width: content.width,
            height: content.height,
            durationSeconds: content.audioDuration ?? content.videoDuration,
            waveform: content.waveform,
            mediaBatchId: content.mediaBatchId.flatMap { $0.isEmpty ? nil : $0 },
            latitude: content.location?.coords.lat,
            longitude: content.location?.coords.lng,
            locationName: content.location?.title,
            locationAddress: content.location?.address,
            liveDurationSeconds: content.location?.duration.map { Int($0) },
            location: liveLocationPayload(from: content.location),
            contactName: content.contact?.first?.name,
            contactPhone: content.contact?.first?.phone,
            contactVCard: nil,
            isRegistered: content.contact?.first?.isRegistered,
            // The flat account id and avatar of the first contact, for a reader
            // that never looks at `contacts` — Android sends and expects them
            // here. Both are lost otherwise, and a card with no account id can
            // only be opened by guessing at the phone number.
            userId: content.contact?.first.map(\.userId).flatMap { $0.isEmpty ? nil : $0 },
            contacts: content.contact.map { shared in
                shared.map { contact in
                    ContactPayloadDTO(
                        id: contact.id,
                        userId: contact.userId.isEmpty ? nil : contact.userId,
                        phone: contact.phone,
                        name: contact.name,
                        avatar: contact.avatar.flatMap { $0.isEmpty ? nil : $0 },
                        isRegistered: contact.isRegistered
                    )
                }
            },
            pollQuestion: content.poll?.question,
            pollOptions: content.poll?.options.map {
                PollOptionDTO(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds,
                    voteCount: $0.voteCount
                )
            },
            pollIsMultipleChoice: content.poll?.isMultipleChoice,
            pollIsClosed: content.poll?.isClosed,
            paymentAmount: content.financial.map { NSDecimalNumber(decimal: $0.amount).doubleValue },
            paymentCurrency: content.financial?.currency,
            paymentStatus: content.financial?.status.rawValue,
            paymentRef: content.financial?.reference.id ?? message.transactionId,
            // La nature part même sans carte : c'est elle qui choisit la carte
            // du destinataire. La révision, elle, ne vient que de la carte.
            financialObjectType: (content.financial?.reference.type ?? content.financialObjectType)?.rawValue,
            financialObjectVersion: content.financial?.reference.version,
            rideStatus: nil,
            rideETA: nil,
            rideOrigin: nil,
            rideDestination: nil,
            orderStatus: nil,
            orderRef: nil,
            callType: nil,
            callDuration: nil,
            replyToMessageId: reply?.replyToMessageId,
            replyToSenderName: reply?.replyToSenderName,
            replyToMessageType: reply?.replyToMessageType,
            replyToMessagePreview: reply?.replyToMessagePreview,
            replyToThumbnailURL: reply?.replyToThumbnailURL,
            avatar: content.contact?.first?.avatar.flatMap { $0.isEmpty ? nil : $0 },
            groupEventType: content.groupEvent?.eventType,
            groupTargetUserId: content.groupEvent?.targetUserId,
            groupTargetName: content.groupEvent?.targetName,
            groupTitle: content.groupEvent?.groupTitle
        )
    }

    /// The nested `location` object, written only for a live share.
    ///
    /// An ordinary pinned location keeps byte-for-byte the payload it sent
    /// before this field existed — the flat coordinates alone — so nothing that
    /// works today can start failing against a server that rejects keys it does
    /// not know. A live share has no such history to protect.
    private static func liveLocationPayload(
        from location: ChatLocationItem?
    ) -> MessageLocationPayloadDTO? {
        guard let location, location.isLive == true else { return nil }
        return MessageLocationPayloadDTO(
            latitude: location.coords.lat,
            longitude: location.coords.lng,
            title: location.title,
            address: location.address,
            isLive: true,
            shareId: location.shareId,
            expiresAt: location.expiresAt.map { $0.timeIntervalSince1970 * 1000 },
            durationMinutes: location.duration.map { Int(($0 / 60).rounded()) }
        )
    }

    private static func legacyPlainContent(_ content: String, typeMessage: String) -> MessageContentDTO {
        let type = typeMessage.uppercased()
        switch type {
        case "TEXT":
            return MessageContentDTO(text: content.isEmpty ? nil : content)
        case "IMAGE", "VIDEO", "VIDEO_NOTE", "AUDIO", "VOICE", "DOCUMENT", "STICKER", "GIF":
            return MessageContentDTO(url: content.isEmpty ? nil : content)
        case "LOCATION", "CONTACT", "ISMONEY", "PAYMENT":
            return MessageContentDTO(
                text: content.isEmpty ? nil : content,
                url: content.isEmpty ? nil : content
            )
        default:
            return MessageContentDTO(text: content.isEmpty ? nil : content)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Inbound content JSON repair
// ─────────────────────────────────────────────────────────────

/// Coerces an inbound `content` object into the shapes `MessageContentDTO` declares.
///
/// `JSONDecoder` does no string→number conversion, and `decodeIfPresent` returns
/// nil only for an absent or null key — a value of the wrong *type* throws and
/// takes the whole content object down with it. Other platforms on this wire do
/// quote their numbers, so the reader has to be the tolerant side.
///
/// Deliberately a separate repair pass rather than a hand-written
/// `init(from:)` on `MessageContentDTO`: leaving that type alone keeps its
/// synthesized encoder exactly as it was, so outbound payloads are untouched —
/// `fileSize` still goes out as `fileSize`, nils still omitted.
enum InboundContentJSONRepair {

    /// Keys the DTO types as `Int` or `Double`.
    private static let numericKeys: Set<String> = [
        "fileSize", "width", "height", "durationSeconds", "liveDurationSeconds",
        "latitude", "longitude", "rideETA", "callDuration", "paymentAmount", "financialObjectVersion",
        "createdAt", "voteCount", "expiresAt", "durationMinutes"
    ]

    /// Keys the DTO types as `Bool`.
    private static let booleanKeys: Set<String> = [
        "isRegistered", "pollIsMultipleChoice", "pollIsClosed", "groupIsLocked",
        "isLive"
    ]

    /// Other spellings of `fileSize` seen on the wire — Android sends `size`.
    ///
    /// Read into `fileSize` and nothing more: the property, the stored column and
    /// every outbound payload keep that one name.
    private static let fileSizeAliases = ["size", "filesize", "file_size"]

    /// Returns repaired JSON, or nil when there is nothing here worth retrying —
    /// a fragment, an array, or anything that is not a JSON object.
    static func repaired(_ data: Data) -> Data? {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              var dictionary = object as? [String: Any]
        else { return nil }

        if isMissing(dictionary["fileSize"]) {
            for alias in fileSizeAliases {
                guard let value = dictionary[alias], !isMissing(value) else { continue }
                dictionary["fileSize"] = value
                break
            }
        }

        return try? JSONSerialization.data(withJSONObject: coerced(dictionary))
    }

    /// Walks nested objects too, so a quoted `voteCount` inside `pollOptions` is
    /// repaired on the same pass. None of the nested DTOs declare a *string*
    /// under any of these key names, so matching by name alone is safe.
    private static func coerced(_ dictionary: [String: Any]) -> [String: Any] {
        var result = dictionary

        for (key, value) in dictionary {
            if let nested = value as? [String: Any] {
                result[key] = coerced(nested)
            } else if let array = value as? [Any] {
                result[key] = array.map { element in
                    (element as? [String: Any]).map(coerced) ?? element
                }
            } else if let string = value as? String, numericKeys.contains(key) {
                // A string that is not a number at all is dropped rather than left
                // in place to fail the retry as well. One unreadable field must not
                // cost the message its url and its thumbnail — the field reads as
                // absent, which is the truth about what we know.
                if let number = number(from: string) {
                    result[key] = number
                } else {
                    result.removeValue(forKey: key)
                }
            } else if let string = value as? String, booleanKeys.contains(key) {
                if let flag = bool(from: string) {
                    result[key] = flag
                } else {
                    result.removeValue(forKey: key)
                }
            }
        }

        return result
    }

    private static func number(from string: String) -> NSNumber? {
        let trimmed = string.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let int = Int(trimmed) { return NSNumber(value: int) }

        guard let double = Double(trimmed), double.isFinite else { return nil }
        // An `Int`-typed field must not be handed a fractional number, and a
        // `Double`-typed one reads a whole number without complaining, so
        // anything integral crosses back as an Int.
        if let exact = Int(exactly: double.rounded()), Double(exact) == double {
            return NSNumber(value: exact)
        }
        return NSNumber(value: double)
    }

    private static func bool(from string: String) -> Bool? {
        switch string.trimmingCharacters(in: .whitespaces).lowercased() {
        case "true", "yes", "1":  return true
        case "false", "no", "0":  return false
        default:                  return nil
        }
    }

    /// A JSON null arrives as `NSNull`, which is present but carries nothing.
    private static func isMissing(_ value: Any?) -> Bool {
        value == nil || value is NSNull
    }
}
