//
//  MessageModelMapper.swift
//  FeatureChat
//
//  Single source of truth for MessageModel ↔ MessageDataItem conversions.
//

import Foundation
import WaanguCoreKit

struct MessageModelMapper {

    // MARK: - MessageModel → MessageDataItem

    static func toDomain(
        _ model: MessageModel,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> MessageDataItem {
        let content = model.content
        let resolvedText = resolvedPlainText(from: model, content: content, fieldCrypto: fieldCrypto)
        let messageContent = MessageContent(
            text: resolvedText,
            image: content.url.flatMap { isType(model.type, .image) ? $0 : nil },
            UIimage: nil,
            shouldUploadDownload: content.pendingUpload == true,
            // Was hardcoded false, which is what made every "did this fail?" check
            // in the bubbles unanswerable across a reload.
            shouldRetry: content.mediaTransferFailed == true,
            audio: isType(model.type, .audio) || isType(model.type, .voice) ? content.url : nil,
            video: isType(model.type, .video) || isType(model.type, .videoNote) ? content.url : nil,
            file: isType(model.type, .document) ? content.url : nil,
            fileName: content.fileName,
            size: content.fileSize,
            // Carried so a media bubble can reserve its height before the image
            // itself exists. The column and the wire field were both already here;
            // nothing read them, so every media row was laid out twice — once at
            // placeholder size, once at photo size — and the list jumped.
            width: content.width,
            height: content.height,
            autoTransferAttempts: content.autoTransferAttempts,
            thumbnail: content.thumbnailURL,
            remoteUri: content.url,
            caption: content.text.flatMap {
                isType(model.type, .image) || isType(model.type, .video) || isType(model.type, .videoNote)
                    ? fieldCrypto.decrypt($0) : nil
            },
            mimeType: content.mimeType,
            location: buildLocation(from: content, sentAt: model.timestamp),
            contact: buildContact(from: content),
            poll: buildPoll(from: content),
            call: buildCall(from: content),
            groupEvent: buildGroupEvent(from: content),
            financial: buildFinancial(from: content),
            financialObjectType: content.financialObjectType.flatMap(FinancialObjectType.init(rawValue:)),
            sticker: isType(model.type, .sticker) ? content.url : nil,
            url: content.url,
            externalUrl: false,
            audioDuration: content.durationSeconds,
            waveform: content.waveform,
            mediaBatchId: content.mediaBatchId,
            viewOnceOpenedAt: content.viewOnceOpenedAt
        )

        return MessageDataItem(
            codeMessage: model.id,
            senderId: model.senderId,
            senderAvatar: nil,
            senderPhone: model.senderPhone,
            senderName: fieldCrypto.decrypt(model.senderName),
            receiverId: model.receiverId,
            groupId: model.groupId ?? model.conversationId,
            typeMessage: resolveType(model, content: content),
            message: messageContent,
            reply: buildReply(from: model),
            isDeleted: model.isDeleted,
            forwarded: model.isForwarded,
            reactions: nil,
            status: mapStatus(model.deliveryStatus),
            isMoney: model.type == .payment,
            isViewOnce: model.isViewOnce,
            isEdited: model.isEdited,
            editedAt: model.editedAt,
            favority: model.isStarred ? [model.senderId] : [],
            transactionId: content.paymentRef,
            createdAt: model.timestamp
        )
    }

    // MARK: - MessageDataItem → MessageModel

    static func toModel(
        from message: MessageDataItem,
        conversationId: String,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> MessageModel {
        let content = buildContent(from: message, fieldCrypto: fieldCrypto)
        let type = mapType(message.typeMessage)
        let existingId = message.codeMessage
        let replyMeta = replyMetadata(from: message.reply)

        return MessageModel(
            id: existingId,
            conversationId: conversationId,
            groupId: message.groupId.flatMap { $0.isEmpty ? nil : $0 },
            senderId: message.senderId,
            senderName: fieldCrypto.encrypt(message.senderName),
            senderPhone: message.senderPhone,
            receiverId: message.receiverId,
            type: type,
            content: content,
            timestamp: message.createdAt,
            deliveryStatus: mapToDeliveryStatus(message.status),
            replyToMessageId: replyMeta.messageId,
            replyToSenderName: replyMeta.senderName,
            replyToMessageType: replyMeta.messageType,
            replyToMessagePreview: replyMeta.preview,
            replyToThumbnailURL: replyMeta.thumbnailURL,
            isForwarded: message.forwarded,
            isDeleted: message.isDeleted,
            deletedAt: message.isDeleted ? Date() : nil,
            isViewOnce: message.isViewOnce,
            isStarred: !message.favority.isEmpty,
            createdAt: message.createdAt,
            updatedAt: Date()
        )
    }

    // MARK: - MessageDataItem → MessageContentModel

    static func buildContent(
        from message: MessageDataItem,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> MessageContentModel {
        let mc = message.message
        let call = callFacts(for: message.typeMessage)
        var content = MessageContentModel(
            text: mc.text.isEmpty ? nil : fieldCrypto.encrypt(mc.text),
            url: mc.remoteUri ?? mc.image ?? mc.video ?? mc.audio ?? mc.file ?? mc.url,
            thumbnailURL: mc.thumbnail,
            localPath: nil,
            mimeType: mc.mimeType,
            fileSize: mc.size,
            fileName: mc.fileName,
            width: mc.width,
            height: mc.height,
            autoTransferAttempts: mc.autoTransferAttempts,
            durationSeconds: mc.audioDuration ?? mc.videoDuration,
            waveform: mc.waveform,
            latitude: mc.location?.coords.lat,
            longitude: mc.location?.coords.lng,
            locationName: mc.location?.title,
            locationAddress: mc.location?.address,
            liveDurationSeconds: mc.location?.duration.map { Int($0) },
            isLiveLocation: mc.location?.isLive,
            liveShareId: mc.location?.shareId,
            liveExpiresAt: mc.location?.expiresAt.map { $0.timeIntervalSince1970 },
            contacts: mc.contact?.map {
                MessageContactModel(
                    id: $0.id,
                    idContact: $0.idContact,
                    userId: $0.userId,
                    phone: $0.phone,
                    name: $0.name,
                    avatar: $0.avatar,
                    isRegistered: $0.isRegistered
                )
            },
            contactName: mc.contact?.first?.name,
            contactPhone: mc.contact?.first?.phone,
            isRegistered: mc.contact?.first?.isRegistered,
            pollQuestion: mc.poll?.question,
            pollOptions: mc.poll?.options.map {
                PollOptionModel(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds,
                    voteCount: $0.voteCount
                )
            },
            pollIsMultipleChoice: mc.poll?.isMultipleChoice,
            pollIsClosed: mc.poll?.isClosed,
            // Sans carte, la référence seule : un message antérieur au Bloc 1
            // n'a que `transactionId`. La carte, quand elle existe, est écrite
            // plus bas par `applyFinancial`, qui remplace cette valeur.
            paymentRef: message.transactionId,
            // Réécrite par `applyFinancial` quand la carte existe.
            financialObjectType: mc.financialObjectType?.rawValue,
            callOutcome: mc.call?.outcome,
            callIsVideo: call?.isVideo,
            callConnected: call?.connected,
            groupEventType: mc.groupEvent?.eventType,
            groupTargetUserId: mc.groupEvent?.targetUserId,
            groupTargetName: mc.groupEvent?.targetName,
            groupTitle: mc.groupEvent?.groupTitle,
            mediaBatchId: mc.mediaBatchId,
            pendingUpload: mc.shouldUploadDownload ? true : nil,
            mediaTransferFailed: mc.shouldRetry ? true : nil,
            viewOnceOpenedAt: mc.viewOnceOpenedAt
        )
        if let financial = mc.financial {
            content.applyFinancial(financial)
        }
        return content
    }

    /// The call facts `MessageTypeModel` is too coarse to keep.
    ///
    /// Returns nil for anything that is not a call, so ordinary messages store
    /// no call fields at all.
    private static func callFacts(
        for type: MessageTypeProps
    ) -> (isVideo: Bool, connected: Bool)? {
        switch type {
        case .CALL_AUDIO:         return (isVideo: false, connected: true)
        case .CALL_VIDEO:         return (isVideo: true,  connected: true)
        case .MISSING_CALL_AUDIO: return (isVideo: false, connected: false)
        case .MISSING_CALL_VIDEO: return (isVideo: true,  connected: false)
        default:                  return nil
        }
    }

    /// The message type, with call rows resolved from the content blob.
    ///
    /// `mapMessageType` can only return what the storage enum kept, which loses
    /// two things: `system` becomes `.TEXT`, so a finished call would stop being
    /// a call bubble, and `missedCall` always becomes audio. Rows written before
    /// these fields existed have neither, and keep the old coarse mapping.
    private static func resolveType(
        _ model: MessageModel,
        content: MessageContentModel
    ) -> MessageTypeProps {
        if let raw = content.groupEventType,
           let groupEvent = MessageTypeProps(rawValue: raw),
           groupEvent.isGroupEvent {
            return groupEvent
        }

        guard let isVideo = content.callIsVideo,
              let connected = content.callConnected
        else { return mapMessageType(model.type) }

        if connected {
            return isVideo ? .CALL_VIDEO : .CALL_AUDIO
        }
        return isVideo ? .MISSING_CALL_VIDEO : .MISSING_CALL_AUDIO
    }

    /// Rebuilds the call payload from what storage kept.
    ///
    /// The roster is not persisted, so redial falls back to the other party —
    /// the same path calls recorded before participants existed already take.
    private static func buildCall(from content: MessageContentModel) -> CallContent? {
        guard let isVideo = content.callIsVideo else { return nil }
        return CallContent(
            callType: isVideo ? .video : .audio,
            callScope: .private,
            participants: nil,
            initiator: nil,
            outcome: content.callOutcome
        )
    }

    /// Rebuilds the group event payload from what storage kept.
    ///
    /// Returns nil for anything that is not a group event, so ordinary messages
    /// carry no group fields at all.
    private static func buildGroupEvent(from content: MessageContentModel) -> GroupEventContent? {
        guard let eventType = content.groupEventType, !eventType.isEmpty else { return nil }
        return GroupEventContent(
            eventType: eventType,
            targetUserId: content.groupTargetUserId,
            targetName: content.groupTargetName,
            groupTitle: content.groupTitle
        )
    }

    // MARK: - Conversation preview

    static func buildLastMessagePreview(_ message: MessageDataItem) -> String? {
        if message.isDeleted { return nil }
        // Never the content, opened or not.
        if message.isViewOnce { return "⏱ View once message" }
        let text = message.message.text
        if !text.isEmpty { return text }
        switch message.typeMessage {
        case .IMAGE:         return "📷 Photo"
        case .VIDEO:         return "🎥 Video"
        case .VIDEO_NOTE:    return "🎥 Video note"
        case .STATUS:        return "Status"
        case .AUDIO, .VOICE: return "🎵 Audio"
        case .DOCUMENT:      return "📄 Document"
        case .LOCATION:      return "📍 Location"
        case .CONTACT:       return "👤 Contact"
        case .POLL:          return "📊 Poll"
        case .ISMONEY:       return "💰 Payment"
        default:             return nil
        }
    }

    // MARK: - Private helpers

    /// Plain text for previews and list rows, decrypted from the embedded `content.text`.
    private static func resolvedPlainText(
        from model: MessageModel,
        content: MessageContentModel,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> String {
        content.text.map { fieldCrypto.decrypt($0) } ?? ""
    }

    /// - Parameter sentAt: when the message was sent, used to derive a deadline
    ///   for a live share that arrived with a duration but no `expiresAt`.
    private static func buildLocation(
        from content: MessageContentModel,
        sentAt: Date
    ) -> ChatLocationItem? {
        guard let lat = content.latitude, let lng = content.longitude else { return nil }
        return ChatLocationItem(
            coords: CoordsLocation(lat: lat, lng: lng),
            title: content.locationName,
            address: content.locationAddress,
            duration: content.liveDurationSeconds.map { Double($0) },
            distance: nil,
            isLive: content.isLiveLocation,
            shareId: content.liveShareId,
            expiresAt: liveExpiry(from: content, sentAt: sentAt)
        )
    }

    /// The deadline of a live share, derived when it was not stored.
    ///
    /// A share with no deadline at all reads as ended, so a sender that sent a
    /// duration and nothing else would have its bubble die on arrival. The
    /// duration plus the send time says the same thing, and is the only other
    /// record of how long the share was meant to run.
    private static func liveExpiry(from content: MessageContentModel, sentAt: Date) -> Date? {
        if let stored = content.liveExpiresAt {
            return Date(timeIntervalSince1970: stored)
        }
        guard content.isLiveLocation == true, let seconds = content.liveDurationSeconds else {
            return nil
        }
        return sentAt.addingTimeInterval(TimeInterval(seconds))
    }

    /// Epoch millis or epoch seconds → seconds.
    ///
    /// The contract says millis, and every other timestamp in this feature
    /// arrives that way, but a value already in seconds must not be pushed
    /// 50,000 years into the future by a blind divide.
    /// Every shared contact in the message, from whichever shape carried them.
    ///
    /// The `contacts` array is what this app sends. A sender that predates it —
    /// Android, today — sends one contact as flat `contactName` / `contactPhone`
    /// / `isRegistered` fields with the account id under `userId` and the photo
    /// under `avatar`, and those two used to be dropped here: the array stayed
    /// nil, and `buildContact` rebuilt the contact with `userId: ""` and no
    /// avatar. The card then rendered without a photo and could not open a chat,
    /// and forwarding it published the loss onward — the copy is built from what
    /// this mapper kept, so an id dropped on the way in is an id gone for good.
    private static func contactModels(from dto: MessageContentDTO) -> [MessageContactModel]? {
        if let contacts = dto.contacts, !contacts.isEmpty {
            return contacts.map {
                MessageContactModel(
                    id: $0.id ?? $0.phone,
                    idContact: nil,
                    userId: $0.userId ?? "",
                    phone: $0.phone,
                    name: $0.name,
                    avatar: normalizedAvatar($0.avatar),
                    isRegistered: $0.isRegistered
                )
            }
        }

        guard let phone = dto.contactPhone, !phone.isEmpty else { return nil }

        return [
            MessageContactModel(
                id: phone,
                idContact: nil,
                userId: dto.userId ?? "",
                phone: phone,
                name: dto.contactName,
                avatar: normalizedAvatar(dto.avatar),
                isRegistered: dto.isRegistered
            )
        ]
    }

    /// Drops an avatar URL that names no file.
    ///
    /// A sender with no photo for the contact sends its bucket root — base URL
    /// plus an empty key, `https://…amazonaws.com/`. Left in place it reaches
    /// the image view as a real URL, which fails to load rather than falling
    /// back to the initials placeholder an absent avatar gets.
    private static func normalizedAvatar(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let components = URLComponents(string: trimmed) else { return trimmed }
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return path.isEmpty ? nil : trimmed
    }

    private static func normalizedEpochSeconds(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        return raw > 10_000_000_000 ? raw / 1000 : raw
    }

    private static func buildContact(from content: MessageContentModel) -> [ContactItem]? {
        if let contacts = content.contacts, !contacts.isEmpty {
            return contacts.map {
                ContactItem(
                    id: $0.id,
                    idContact: $0.idContact,
                    userId: $0.userId,
                    phone: $0.phone,
                    name: $0.name,
                    avatar: $0.avatar,
                    isRegistered: $0.isRegistered
                )
            }
        }
        guard let name = content.contactName, let phone = content.contactPhone else { return nil }
        return [ContactItem(idContact: nil, userId: "", phone: phone, name: name, avatar: nil, isRegistered: content.isRegistered)]
    }

    /// Rebuilds the poll from what storage kept.
    ///
    /// A poll needs a question and at least two options to be one; anything less
    /// is a malformed payload, and returning nil sends it down the text renderer
    /// rather than drawing an empty poll.
    private static func buildPoll(from content: MessageContentModel) -> PollContent? {
        guard let question = content.pollQuestion, !question.isEmpty,
              let options = content.pollOptions, options.count >= 2
        else { return nil }

        return PollContent(
            question: question,
            options: options.map {
                PollOption(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds,
                    voteCount: $0.voteCount
                )
            },
            isMultipleChoice: content.pollIsMultipleChoice ?? false,
            isClosed: content.pollIsClosed ?? false
        )
    }

    private static func buildReply(from model: MessageModel) -> MessageReply? {
        guard let replyId = model.replyToMessageId, !replyId.isEmpty else { return nil }

        // Message cité supprimé pour tous : la citation ne montre plus rien de lui (B44).
        if model.replyToIsDeleted == true {
            var deleted = MessageDataItem(
                codeMessage: replyId,
                senderId: "",
                senderName: model.replyToSenderName ?? "",
                typeMessage: .TEXT,
                message: MessageContent(text: ""),
                createdAt: model.timestamp
            )
            deleted.isDeleted = true
            return .message(deleted)
        }

        let replyType = model.replyToMessageType.map { mapMessageType($0) } ?? .TEXT
        let preview = model.replyToMessagePreview ?? ""
        let thumb = model.replyToThumbnailURL

        var content = MessageContent(text: preview)
        switch replyType {
        case .IMAGE:
            content.image = thumb
            content.thumbnail = thumb
        case .STATUS:
            if let thumb, !thumb.isEmpty {
                content.image = thumb
                content.thumbnail = thumb
            }
        case .VIDEO, .VIDEO_NOTE:
            content.video = thumb
            content.thumbnail = thumb
        case .AUDIO, .VOICE:
            content.audio = thumb
        case .DOCUMENT:
            content.file = thumb
        default:
            break
        }
        if content.thumbnail == nil {
            content.thumbnail = thumb
        }

        let snapshot = MessageDataItem(
            codeMessage: replyId,
            senderId: "",
            senderName: model.replyToSenderName ?? "",
            typeMessage: replyType,
            message: content,
            createdAt: model.timestamp
        )
        return .message(snapshot)
    }

    private static func replyMetadata(from reply: MessageReply?) -> (
        messageId: String?,
        senderName: String?,
        messageType: MessageTypeModel?,
        preview: String?,
        thumbnailURL: String?
    ) {
        guard case .message(let item?) = reply else {
            return (nil, nil, nil, nil, nil)
        }
        return (
            item.codeMessage,
            item.senderName.isEmpty ? nil : item.senderName,
            mapType(item.typeMessage),
            MessageReplyWireCodec.replyPreview(for: item) ?? buildLastMessagePreview(item),
            item.message.thumbnail ?? item.message.image
        )
    }

    private static func isType(_ type: MessageTypeModel, _ target: MessageTypeModel) -> Bool {
        type == target
    }

    // MARK: - Enum mapping

    static func mapType(_ props: MessageTypeProps) -> MessageTypeModel {
        switch props {
        case .TEXT:               return .text
        case .IMAGE:              return .image
        case .VIDEO:              return .video
        case .VIDEO_NOTE:         return .videoNote
        case .AUDIO:              return .audio
        case .VOICE:              return .voice
        case .DOCUMENT:           return .document
        case .CONTACT:            return .contact
        case .LOCATION:           return .location
        case .POLL:               return .poll
        case .ISMONEY:            return .payment
        case .MISSING_CALL_AUDIO: return .missedCall
        case .MISSING_CALL_VIDEO: return .missedCall
        case .CALL_AUDIO:         return .system
        case .CALL_VIDEO:         return .system
        case .GROUP_CREATED,
             .GROUP_UPDATED,
             .USER_ADDED_TO_GROUP,
             .USER_JOINED_GROUP,
             .USER_LEFT_GROUP,
             .USER_REMOVED_FROM_GROUP,
             .USER_PROMOTED_TO_ADMIN,
             .USER_DEMOTED_FROM_ADMIN: return .system
        case .STATUS:             return .status
        case .CHANNEL_INVITE:     return .system
        }
    }

    static func mapMessageType(_ type: MessageTypeModel) -> MessageTypeProps {
        switch type {
        case .text:        return .TEXT
        case .image:       return .IMAGE
        case .video:       return .VIDEO
        case .videoNote:   return .VIDEO_NOTE
        case .voice:       return .VOICE
        case .audio:       return .AUDIO
        case .document:    return .DOCUMENT
        case .sticker:     return .TEXT
        case .gif:         return .IMAGE
        case .location:    return .LOCATION
        case .contact:     return .CONTACT
        case .poll:        return .POLL
        case .payment:     return .ISMONEY
        case .missedCall:  return .MISSING_CALL_AUDIO
        case .system:      return .TEXT
        case .deleted:     return .TEXT
        case .encrypted:   return .TEXT
        case .status:      return .STATUS
        default:           return .TEXT
        }
    }

    static func mapStatus(_ status: MessageDeliveryStatusModel) -> MessageStatus {
        switch status {
        case .pending:   return .PENDING
        case .sent:      return .SENT
        case .delivered: return .DELIVERED
        case .read:      return .SEEN
        case .failed:    return .FAILED
        }
    }

    static func mapToDeliveryStatus(_ status: MessageStatus) -> MessageDeliveryStatusModel {
        switch status {
        case .PENDING:   return .pending
        case .SENT:      return .sent
        case .DELIVERED: return .delivered
        case .UNSEEN:    return .delivered
        case .SEEN:      return .read
        case .FAILED:    return .failed
        case .MODIFY:    return .delivered
        }
    }

    // MARK: - InboundMessageDTO → MessageModel

    static func toModel(
        from dto: InboundMessageDTO,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> MessageModel? {
        let codeMessage = dto.codeMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !codeMessage.isEmpty else {
            return nil
        }

        // Asked of the whole message, not of `typeMessage` alone: the kind and the
        // actor have moved between the envelope and the content across contract
        // revisions, and every inbound path — MQTT, pull-events, inbox summary —
        // has to reach the same answer.
        let groupEvent = dto.resolvedGroupEvent
        let type = groupEvent.map { mapType($0.type) } ?? mapInboundType(dto.typeMessage)
        let content = mapInboundContent(
            dto.messageContent,
            type: type,
            groupEvent: groupEvent,
            fieldCrypto: fieldCrypto
        )
        let replyType = dto.replyToMessageType.flatMap { mapInboundType($0) }
        let timestamp = dto.resolvedTimestamp

        // The envelope around a group event is sent by `"system"`. Left alone it
        // would make the checkpoint read "System created the group" — and, since
        // it is nobody's own id, never resolve to "You".
        let senderId = groupEvent.map { $0.actorId.isEmpty ? dto.senderId : $0.actorId }
            ?? dto.senderId
        let senderName = groupEvent.map { $0.actorName.isEmpty ? dto.senderName : $0.actorName }
            ?? dto.senderName
        let senderPhone = groupEvent.map { $0.actorPhone.isEmpty ? (dto.senderPhone ?? "") : $0.actorPhone }
            ?? (dto.senderPhone ?? "")

        return MessageModel(
            id: codeMessage,
            conversationId: dto.conversationId ?? "",  // Default to empty string, will be overwritten in sync context
            groupId: dto.groupId.flatMap { $0.isEmpty ? nil : $0 },
            senderId: senderId,
            senderName: fieldCrypto.encrypt(senderName),
            senderPhone: senderPhone,
            receiverId: dto.receiverId ?? "",
            type: type,
            content: content,
            timestamp: Date(timeIntervalSince1970: timestamp),
            deliveryStatus: .delivered,
            replyToMessageId: dto.replyToMessageId,
            replyToSenderName: dto.replyToSenderName,
            replyToMessageType: replyType,
            replyToMessagePreview: dto.replyToMessagePreview,
            replyToThumbnailURL: dto.replyToThumbnailURL,
            isForwarded: dto.forwarded ?? false,
            isDeleted: false,
            deletedAt: nil,
            isViewOnce: dto.viewOnce ?? false,
            isStarred: false,
            createdAt: Date(timeIntervalSince1970: timestamp),
            updatedAt: Date()
        )
    }

    static func mapInboundType(_ raw: String) -> MessageTypeModel {
        switch raw.uppercased() {
        case "TEXT": return .text
        case "IMAGE": return .image
        case "VIDEO": return .video
        case "VIDEO_NOTE": return .videoNote
        case "VOICE": return .voice
        case "AUDIO": return .audio
        case "DOCUMENT": return .document
        case "CONTACT": return .contact
        case "LOCATION": return .location
        case "PAYMENT", "ISMONEY": return .payment
        case "POLL": return .poll
        case "STICKER": return .sticker
        case "STATUS": return .status
        case "CALL_AUDIO", "CALL_VIDEO": return .system
        case "MISSING_CALL_AUDIO", "MISSING_CALL_VIDEO", "MISSED_CALL": return .missedCall
        case "GROUP_CREATED", "GROUP_UPDATED", "USER_ADDED_TO_GROUP", "USER_JOINED_GROUP",
             "USER_LEFT_GROUP", "USER_REMOVED_FROM_GROUP", "USER_PROMOTED_TO_ADMIN",
             "USER_DEMOTED_FROM_ADMIN":
            return .system
        // What the wire calls a group event before the normalizer names it. Also
        // covers system records that are not group events at all — either way
        // nothing was sent, so it must not collect ticks or read receipts.
        case "SYSTEM": return .system
        default: return .text
        }
    }

    static func mapInboundContent(
        _ dto: MessageContentDTO,
        type: MessageTypeModel,
        groupEvent: ResolvedGroupEvent? = nil,
        fieldCrypto: any FieldEncryptionServiceProtocol
    ) -> MessageContentModel {
        let outcome = dto.callOutcome.flatMap { CallOutcome(rawValue: $0) }
        return MessageContentModel(
            text: dto.text.map { fieldCrypto.encrypt($0) },
            url: dto.url,
            thumbnailURL: dto.thumbnailURL,
            localPath: nil,
            mimeType: dto.mimeType,
            fileSize: dto.fileSize,
            fileName: dto.fileName,
            width: dto.width,
            height: dto.height,
            durationSeconds: dto.durationSeconds,
            waveform: dto.waveform,
            // The nested object wins where it exists — it is the only shape
            // carrying the live share — and the flat fields stand in for every
            // sender that predates it.
            latitude: dto.location?.latitude ?? dto.latitude,
            longitude: dto.location?.longitude ?? dto.longitude,
            locationName: dto.location?.title ?? dto.locationName,
            locationAddress: dto.location?.address ?? dto.locationAddress,
            liveDurationSeconds: dto.liveDurationSeconds
                ?? dto.location?.durationMinutes.map { $0 * 60 },
            isLiveLocation: dto.location?.isLive,
            liveShareId: dto.location?.shareId,
            liveExpiresAt: normalizedEpochSeconds(dto.location?.expiresAt),
            contacts: contactModels(from: dto),
            contactName: dto.contactName,
            contactPhone: dto.contactPhone,
            isRegistered: dto.isRegistered,
            pollQuestion: dto.pollQuestion,
            pollOptions: dto.pollOptions?.map {
                PollOptionModel(
                    id: $0.id,
                    text: $0.text,
                    voterIds: $0.voterIds ?? [],
                    // A count the server omitted is derived from the voters it
                    // did name, so a sparse payload still renders real bars.
                    voteCount: $0.voteCount ?? ($0.voterIds?.count ?? 0)
                )
            },
            pollIsMultipleChoice: dto.pollIsMultipleChoice,
            pollIsClosed: dto.pollIsClosed,
            // Gardés tels que l'expéditeur les a publiés, pour que le
            // destinataire voie la bonne carte tout de suite. Rien n'est marqué
            // vérifié : `financialVerification` reste nil, lu « non vérifié » par
            // `buildFinancial`, et la carte dit « vérification » jusqu'à ce qu'une
            // relecture du backend réécrive la ligne.
            paymentAmount: dto.paymentAmount,
            paymentCurrency: dto.paymentCurrency,
            paymentStatus: dto.paymentStatus,
            paymentRef: dto.paymentRef,
            financialObjectType: dto.financialObjectType,
            financialObjectVersion: dto.financialObjectVersion,
            callOutcome: dto.callOutcome,
            callIsVideo: dto.callType.map { $0.lowercased().contains("video") },
            // Only an outcome tells us whether it connected; the duration cannot,
            // since a projected record may carry none either way.
            callConnected: outcome?.didConnect,
            groupEventType: groupEvent?.type.rawValue,
            groupTargetUserId: groupEvent?.primaryTarget?.userId,
            groupTargetName: groupEvent?.primaryTarget?.displayName,
            groupTitle: groupEvent?.title,
            // Carried through so a batch the sender grouped arrives grouped. Left
            // nil here, every photo of a multi-send rendered as its own row on the
            // receiving side while the sender saw one group.
            mediaBatchId: dto.mediaBatchId.flatMap { $0.isEmpty ? nil : $0 },
            pendingUpload: nil,
            // Transfer state is this device's business, never the sender's: a
            // message just off the wire has not tried anything yet.
            mediaTransferFailed: nil
        )
    }
}


// MARK: - Carte financière (Bloc 1)

extension MessageModelMapper {

    /// Reconstruit la carte financière depuis la ligne stockée.
    ///
    /// Retourne `nil` — et non une carte partielle — dès qu'un élément d'identité
    /// manque. Une carte sans référence ne peut ni être rafraîchie, ni être
    /// comparée en version : elle afficherait un montant que rien ne permet de
    /// corriger ensuite. La bulle préfère la carte d'attente.
    ///
    /// Les lignes écrites avant le Bloc 1 n'ont ni `financialObjectType` ni
    /// `financialObjectVersion` ; elles retombent donc ici sur `nil`, ce qui est
    /// le comportement voulu : elles seront réconciliées à la première lecture.
    static func buildFinancial(from content: MessageContentModel) -> FinancialCardPayload? {
        guard
            let rawType = content.financialObjectType,
            let type = FinancialObjectType(rawValue: rawType),
            let objectId = content.paymentRef,
            let version = content.financialObjectVersion,
            let currency = content.paymentCurrency
        else {
            return nil
        }

        // Le décimal fait autorité ; le `Double` n'est lu que pour les lignes
        // écrites avant la tâche 4.3b.
        //
        // Hors du `guard` : une closure trailing y serait prise pour le corps du
        // `guard` par le parseur.
        let decimalAmount = content.paymentAmountDecimal.flatMap { Decimal(string: $0) }
        let legacyAmount = content.paymentAmount.map { Decimal($0) }
        guard let amount = decimalAmount ?? legacyAmount else { return nil }

        let reference = FinancialReference(
            type: type,
            id: objectId,
            version: version,
            // Voir `FinancialEventDTO.toReference()` : jamais de repli sur
            // `objectId`, qui se retrouverait en clair dans les logs.
            correlationID: content.financialCorrelationId
                .map(CorrelationId.init(value:)) ?? CorrelationId()
        )

        return FinancialCardPayload(
            reference: reference,
            // Un statut illisible devient `unknown`, jamais `failed` : la ligne
            // peut avoir été écrite par une version connaissant un statut que
            // celle-ci ignore.
            status: content.paymentStatus.flatMap { PaymentStatus(rawValue: $0) } ?? .unknown,
            amount: amount,
            currency: currency,
            feeAmount: content.financialFeeAmountDecimal.flatMap { Decimal(string: $0) }
                ?? content.financialFeeAmount.map { Decimal($0) },
            counterpartyName: content.financialCounterpartyName,
            note: nil,
            lastRefreshedAt: content.financialRefreshedAt
                .map { Date(timeIntervalSince1970: $0) } ?? .distantPast,
            // Une vérification absente vaut « non vérifié », jamais « vérifié ».
            verification: content.financialVerification
                .flatMap { FinancialCardVerification(rawValue: $0) } ?? .unverified
        )
    }
}
