import Foundation
import WaanguCoreKit

/// Parses inbound MQTT JSON payloads into `ChatSyncEventDTO` for `ChatSyncDelegate`.
/// All chat + story events arrive on `waangu-chat/{userId}` — dispatch by `eventType` only.
/// Typing / presence are handled separately by `PresenceRepository` and ignored here.
enum ChatMqttEventParser {

    /// The `eventType` of a frame, for logging only.
    ///
    /// Normalised exactly as `parse` normalises it, so a log line names the
    /// event under the same spelling the switch matched on — reading one and
    /// grepping the other for it must not disagree.
    ///
    /// Deliberately a second pass over the JSON rather than a value threaded
    /// out of `parse`: the caller needs this on the drop path, which is rare,
    /// and on the success path only under a `.debug` level that ships disabled.
    static func peekEventType(data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (json["eventType"] as? String)?
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
    }

    static func parse(data: Data) -> ChatSyncEventDTO? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // §11.1 — un pointeur finance peut aussi se reconnaître à `payload.action`.
        if (json["payload"] as? [String: Any])?["action"] as? String == "OBJECT_CHANGED" {
            let at = isoTimestamp(json["timestamp"] as? String) ?? Date().timeIntervalSince1970
            return parseFinanceObjectChanged(json: json, at: at)
        }

        let eventType = (json["eventType"] as? String)?
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")
        let at = normalizedTimestamp(numericTimestamp(json["timestamp"]))
            ?? isoTimestamp(json["timestamp"] as? String)
            ?? normalizedTimestamp(numericTimestamp(json["at"]))
            ?? isoTimestamp(json["at"] as? String)
            ?? Date().timeIntervalSince1970
        switch eventType {
        case ChatMqttEvents.typing:
            return nil
        case ChatMqttEvents.ack:
            return parseAck(json: json, at: at)
        case ChatMqttEvents.sessionRevoked:
            return ChatSyncEventDTO(
                type: ChatSyncEventDTO.sessionRevokedType,
                referenceId: nil,
                conversationId: nil,
                payload: nil,
                at: at
            )
        case ChatMqttEvents.messageDelivered:
            let source = nestedPayload(json) ?? json
            guard let messageId = messageId(from: source) else { return nil }
            return ChatSyncEventDTO(
                type: "delivery_receipt",
                referenceId: messageId,
                conversationId: conversationId(from: source),
                payload: payloadData(from: json),
                at: deliveryTimestamp(from: source) ?? at
            )
        case ChatMqttEvents.messageRead:
            let source = nestedPayload(json) ?? json
            guard let messageId = messageId(from: source) else { return nil }
            return ChatSyncEventDTO(
                type: "read_receipt",
                referenceId: messageId,
                conversationId: conversationId(from: source),
                payload: payloadData(from: json),
                at: at
            )
        case ChatMqttEvents.messageDeleted:
            return parseDeleteEvent(json: json, at: at)
        case ChatMqttEvents.messageModified:
            return makeMessageDTO(json: json, type: "message_edited", at: at, data: data)
        case ChatMqttEvents.messageReactionAdded, "MESSAGE_REACTED":
            return parseReactionEvent(json: json, at: at, removing: false)
        case ChatMqttEvents.messageReactionRemoved:
            return parseReactionEvent(json: json, at: at, removing: true)
        case ChatMqttEvents.pollVoted, ChatMqttEvents.pollVote:
            return parsePollVoteEvent(json: json, at: at)
        case ChatMqttEvents.financeObjectChanged, ChatMqttEvents.chatCoreFinancialObjectChanged:
            return parseFinanceObjectChanged(json: json, at: at)
        case ChatMqttEvents.financialDisputeOpened, ChatMqttEvents.financialDisputeClosed:
            return parseFinancialDisputeChanged(json: json, at: at)
        // A group event arrives wrapped in an ordinary MESSAGE_SENT envelope with
        // the event nested in `content`, and needs nothing special here — the
        // mapper reads the content and recognises it on every inbound path, not
        // just this one.
        case ChatMqttEvents.messageSent, .none:
            return makeMessageDTO(json: json, type: "message", at: at, data: data)

        // MARK: Group lifecycle
        // The unwrapped form: no message envelope at all, so it has to be given
        // one before anything downstream can decode it.
        case let type? where ChatMqttEvents.Group.all.contains(type):
            let source = nestedPayload(json) ?? json
            guard let normalized = GroupSystemEventNormalizer.normalize(source, eventType: type) else {
                return nil
            }
            return makeMessageDTO(json: normalized, type: "message", at: at, data: data)

        // MARK: Live location
        // Ephemeral by contract — these move a pin and are never persisted, so
        // they carry no message body for the message branch to build on.
        case ChatMqttEvents.liveLocationUpdate:
            return parseLiveLocationEvent(json: json, at: at, stopping: false)
        case ChatMqttEvents.liveLocationStop:
            return parseLiveLocationEvent(json: json, at: at, stopping: true)

        // MARK: Stories
        case ChatMqttEvents.storyCreated:
            return makeStoryDTO(json: json, type: "story_created", at: at, data: data)
        case ChatMqttEvents.storyViewed:
            return makeStoryDTO(json: json, type: "story_viewed", at: at, data: data)
        case ChatMqttEvents.storyDeleted:
            return makeStoryDTO(json: json, type: "story_deleted", at: at, data: data)
        case ChatMqttEvents.storyReacted:
            return makeStoryDTO(json: json, type: "story_reacted", at: at, data: data)
        case ChatMqttEvents.storyExpired:
            return makeStoryDTO(json: json, type: "story_expired", at: at, data: data)
        default:
            return nil
        }
    }

    /// Server ACK for outbound ops — e.g. MESSAGESENT → one-tick (`.sent`).
    ///
    /// New backend shape keeps `operation` / `status` on the **root**, while
    /// `payload` is the full message body (multi-device sync).
    private static func parseAck(json: [String: Any], at: Double) -> ChatSyncEventDTO? {
        let nested = nestedPayload(json)
        let envelope = nested.map { _ in json } ?? json
        let messageBody = nested ?? json

        let operation = (
            (envelope["operation"] as? String)
                ?? (messageBody["operation"] as? String)
        )?
            .uppercased()
            .replacingOccurrences(of: "_", with: "")

        let status = (
            (envelope["status"] as? String)
                ?? (messageBody["status"] as? String)
        )?.uppercased()

        guard let codeMessage = messageId(from: envelope) ?? messageId(from: messageBody) else {
            return nil
        }

        let payloadAt = normalizedTimestamp(envelope["timestamp"] as? Double)
            ?? normalizedTimestamp(messageBody["timestamp"] as? Double)
            ?? at

        // Persist the message body so `sent_receipt` can insert-if-missing.
        let storedPayload: AnyCodablePayload? = {
            guard let data = try? JSONSerialization.data(withJSONObject: messageBody) else {
                return nil
            }
            return AnyCodablePayload(rawData: data)
        }()

        switch (operation, status) {
        case (ChatMqttEvents.AckOperation.messageSent, ChatMqttEvents.AckStatus.success):
            return ChatSyncEventDTO(
                type: "sent_receipt",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageSent, ChatMqttEvents.AckStatus.failed),
             (ChatMqttEvents.AckOperation.messageSent, ChatMqttEvents.AckStatus.failure):
            return ChatSyncEventDTO(
                type: "send_failed",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageRead, ChatMqttEvents.AckStatus.success):
            return ChatSyncEventDTO(
                type: "read_ack",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageModified, ChatMqttEvents.AckStatus.success):
            return ChatSyncEventDTO(
                type: "modify_ack",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageModified, ChatMqttEvents.AckStatus.failed),
             (ChatMqttEvents.AckOperation.messageModified, ChatMqttEvents.AckStatus.failure):
            return ChatSyncEventDTO(
                type: "modify_failed",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageDeleted, ChatMqttEvents.AckStatus.success):
            return ChatSyncEventDTO(
                type: "delete_ack",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        case (ChatMqttEvents.AckOperation.messageDeleted, ChatMqttEvents.AckStatus.failed),
             (ChatMqttEvents.AckOperation.messageDeleted, ChatMqttEvents.AckStatus.failure):
            return ChatSyncEventDTO(
                type: "delete_failed",
                referenceId: codeMessage,
                conversationId: conversationId(from: envelope) ?? conversationId(from: messageBody),
                payload: storedPayload,
                at: payloadAt
            )
        default:
            return nil
        }
    }

    private static func parseDeleteEvent(
        json: [String: Any],
        at: Double
    ) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json
        guard let messageId = messageId(from: source) else { return nil }
        return ChatSyncEventDTO(
            type: "message_deleted",
            referenceId: messageId,
            conversationId: conversationId(from: source),
            payload: payloadData(from: json),
            at: at
        )
    }

    private static func parseReactionEvent(
        json: [String: Any],
        at: Double,
        removing: Bool
    ) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json
        guard let codeMessage = messageId(from: source) else { return nil }

        var payloadObject = source
        if payloadObject["eventType"] == nil {
            payloadObject["eventType"] = removing
                ? ChatMqttEvents.messageReactionRemoved
                : ChatMqttEvents.messageReactionAdded
        }
        // Normalize alternate key so Codable decode always sees `reaction`.
        if payloadObject["reaction"] == nil, let emoji = payloadObject["emoji"] as? String {
            payloadObject["reaction"] = emoji
        }
        if payloadObject["codeMessage"] == nil {
            payloadObject["codeMessage"] = codeMessage
        }
        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObject)) ?? Data()
        let reactedAt = isoTimestamp(source["reactedAt"] as? String) ?? at
        #if DEBUG
        print(
            "[Reaction] mqtt parse remove=\(removing) codeMessage=\(codeMessage) userId=\(payloadObject["userId"] ?? "nil") senderId=\(payloadObject["senderId"] ?? "nil") reaction=\(payloadObject["reaction"] ?? "nil")"
        )
        #endif
        return ChatSyncEventDTO(
            type: removing ? "reaction_removed" : "reaction",
            referenceId: codeMessage,
            conversationId: conversationId(from: source),
            payload: AnyCodablePayload(rawData: payloadData),
            at: reactedAt
        )
    }

    /// A poll vote patches a message that already exists, exactly as a reaction
    /// does, so it is normalised the same way: the message id is lifted onto
    /// `codeMessage` whichever name it arrived under, and the DTO decode never
    /// has to care which one that was.
    private static func parsePollVoteEvent(
        json: [String: Any],
        at: Double
    ) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json
        guard let codeMessage = messageId(from: source) else { return nil }

        var payloadObject = source
        payloadObject["codeMessage"] = codeMessage

        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObject)) ?? Data()
        return ChatSyncEventDTO(
            type: "poll_vote",
            referenceId: codeMessage,
            conversationId: conversationId(from: source),
            payload: AnyCodablePayload(rawData: payloadData),
            at: isoTimestamp(source["votedAt"] as? String) ?? at
        )
    }

    /// A live location tick, or the end of a share.
    ///
    /// Normalises the payload into the single shape `InboundLiveLocationDTO`
    /// decodes, the way `parseReactionEvent` lifts `emoji` onto `reaction`.
    /// Two shapes reach this: the egress contract's nested `location` object,
    /// and the flat `lat` / `lng` of an ingress tick fanned out as it arrived.
    ///
    /// A stop is allowed to carry no position — it then simply ends the share
    /// and the last pin stays where it was. An update without one is nothing
    /// at all, and is dropped.
    /// Notification d'évolution d'un objet financier.
    ///
    /// Ne lit **aucune** donnée financière du payload — ni montant, ni statut, ni
    /// contrepartie — même si le backend en envoyait. Seules l'identité et la
    /// révision annoncée sont retenues, et elles ne servent qu'à décider s'il
    /// faut interroger le serveur.
    private static func parseFinanceObjectChanged(
        json: [String: Any],
        at: Double
    ) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json

        // Pointeur Chat Core (§11.2) : `subject.financialIntentRef`, sinon le
        // dernier segment de `refetchPath`. Aucun type n'y figure — toutes les
        // cartes FCO se relisent par la même route — d'où `PAYMENT` par défaut.
        // Les montants que le pointeur ne doit pas porter ne sont jamais lus.
        let subject = source["subject"] as? [String: Any]
        let pointerRef = (subject?["financialIntentRef"] as? String)
            ?? (source["refetchPath"] as? String).flatMap { $0.split(separator: "/").last.map(String.init) }

        guard
            let objectId = (source["objectId"] as? String) ?? (source["financialObjectId"] as? String) ?? pointerRef,
            !objectId.isEmpty,
            let objectType = (source["objectType"] as? String) ?? (source["financialObjectType"] as? String)
                ?? (pointerRef != nil ? "PAYMENT" : nil)
        else {
            // Un événement financier sans identité ne peut pas être requêté :
            // le laisser passer produirait une réconciliation sur rien.
            return nil
        }

        let version = (source["version"] as? Int)
            ?? (source["financialObjectVersion"] as? Int)
            ?? FinanceCoreRevision.parse(source["objectVersion"] as? String)
            ?? 0

        // La corrélation absente reste absente : `FinancialEventDTO.toReference()`
        // en frappera une neuve. La faire retomber sur `objectId` republierait
        // l'identifiant en clair dans les logs, que `FinanceLogContext` hache
        // précisément pour l'éviter.
        var payload: [String: Any] = [
            "objectType": objectType,
            "objectId": objectId,
            "version": version
        ]
        if let correlationId = source["correlationId"] as? String {
            payload["correlationId"] = correlationId
        }

        return ChatSyncEventDTO(
            type: "finance_object_changed",
            referenceId: objectId,
            conversationId: conversationId(from: source),
            payload: (try? JSONSerialization.data(withJSONObject: payload))
                .map { AnyCodablePayload(rawData: $0) },
            at: at
        )
    }

    /// Un litige a changé. Rien n'est lu du payload au-delà de son identité : le
    /// dossier se relit au serveur, la carte ne reçoit pas son statut par le fil.
    private static func parseFinancialDisputeChanged(json: [String: Any], at: Double) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json
        let subject = source["subject"] as? [String: Any]
        let disputeId = (source["disputeId"] as? String) ?? (subject?["disputeId"] as? String)
        return ChatSyncEventDTO(
            type: "finance_dispute_changed",
            referenceId: disputeId,
            conversationId: conversationId(from: source),
            payload: nil,
            at: at
        )
    }

    private static func parseLiveLocationEvent(
        json: [String: Any],
        at: Double,
        stopping isStop: Bool
    ) -> ChatSyncEventDTO? {
        let source = nestedPayload(json) ?? json
        guard let shareId = liveShareId(from: source) ?? liveShareId(from: json) else {
            return nil
        }

        var payloadObject: [String: Any] = [
            "shareId": shareId,
            "codeMessage": (source["codeMessage"] as? String) ?? shareId
        ]
        let conversation = conversationId(from: source) ?? conversationId(from: json)
        if let conversation {
            payloadObject["conversationId"] = conversation
        }
        if let senderId = (source["senderId"] as? String) ?? (source["userId"] as? String) {
            payloadObject["senderId"] = senderId
        }
        let position = livePosition(from: source)
        if let position {
            payloadObject["location"] = position
        }
        if let expiresAt = normalizedTimestamp(doubleValue(source["expiresAt"])) {
            payloadObject["expiresAt"] = expiresAt
        }

        guard isStop || position != nil else { return nil }
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payloadObject) else {
            return nil
        }

        // The payload timestamp is when the position was measured; the envelope
        // one is when it was fanned out. The pin should follow the former.
        let measuredAt = normalizedTimestamp(numericTimestamp(source["timestamp"]))
            ?? isoTimestamp(source["timestamp"] as? String)
            ?? at

        return ChatSyncEventDTO(
            type: isStop ? "live_location_stop" : "live_location_update",
            referenceId: shareId,
            conversationId: conversation,
            payload: AnyCodablePayload(rawData: payloadData),
            at: measuredAt
        )
    }

    /// The share's id, which the sender sets to the anchor message's
    /// `codeMessage` — so either name identifies the same share.
    private static func liveShareId(from json: [String: Any]) -> String? {
        (json["shareId"] as? String) ?? (json["codeMessage"] as? String)
    }

    /// Reads the position from either the nested `location` object or the
    /// flat coordinate keys, and hands back the nested form.
    private static func livePosition(from json: [String: Any]) -> [String: Any]? {
        let source = (json["location"] as? [String: Any]) ?? json
        guard
            let latitude = doubleValue(source["latitude"]) ?? doubleValue(source["lat"]),
            let longitude = doubleValue(source["longitude"]) ?? doubleValue(source["lng"])
        else {
            return nil
        }
        var position: [String: Any] = ["latitude": latitude, "longitude": longitude]
        if let accuracy = doubleValue(source["accuracy"]) {
            position["accuracy"] = accuracy
        }
        return position
    }

    /// `numericTimestamp` widened to accept a quoted number.
    ///
    /// Same reason `InboundContentJSONRepair` exists: other platforms on this
    /// wire quote their numbers, and a coordinate lost to a type mismatch
    /// strands the pin with no error anywhere.
    private static func doubleValue(_ value: Any?) -> Double? {
        if let number = numericTimestamp(value) { return number }
        guard let text = value as? String else { return nil }
        return Double(text)
    }

    private static func makeStoryDTO(
        json: [String: Any],
        type: String,
        at: Double,
        data: Data
    ) -> ChatSyncEventDTO? {
        let payloadObject = nestedPayload(json) ?? json
        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObject)) ?? data
        let referenceId = storyId(from: payloadObject) ?? storyId(from: json)
        let rawAt = payloadObject["timestamp"] as? Double
            ?? numericTimestamp(payloadObject["deletedAt"])
            ?? numericTimestamp(payloadObject["viewedAt"])
            ?? numericTimestamp(payloadObject["reactedAt"])
            ?? numericTimestamp(payloadObject["expiredAt"])
            ?? isoTimestamp(payloadObject["timestamp"] as? String)
        return ChatSyncEventDTO(
            type: type,
            referenceId: referenceId,
            conversationId: nil,
            payload: AnyCodablePayload(rawData: payloadData),
            at: normalizedTimestamp(rawAt) ?? at
        )
    }

    private static func makeMessageDTO(
        json: [String: Any],
        type: String,
        at: Double,
        data: Data
    ) -> ChatSyncEventDTO? {
        let payloadObject = nestedPayload(json) ?? json
        let payloadData = (try? JSONSerialization.data(withJSONObject: payloadObject)) ?? data
        let referenceId = messageId(from: payloadObject) ?? messageId(from: json)
        let rawAt = payloadObject["timestamp"] as? Double
        return ChatSyncEventDTO(
            type: type,
            referenceId: referenceId,
            conversationId: conversationId(from: payloadObject) ?? conversationId(from: json),
            payload: AnyCodablePayload(rawData: payloadData),
            at: normalizedTimestamp(rawAt) ?? at
        )
    }

    private static func nestedPayload(_ json: [String: Any]) -> [String: Any]? {
        json["payload"] as? [String: Any]
    }

    private static func storyId(from json: [String: Any]) -> String? {
        (json["storyId"] as? String)
            ?? (json["codeStatus"] as? String)
            ?? (json["statusId"] as? String)
            ?? (json["id"] as? String)
            ?? (json["referenceId"] as? String)
    }

    private static func messageId(from json: [String: Any]) -> String? {
        (json["codeMessage"] as? String)
            ?? (json["messageId"] as? String)
            ?? (json["id"] as? String)
            ?? (json["referenceId"] as? String)
    }

    private static func conversationId(from json: [String: Any]) -> String? {
        json["conversationId"] as? String
    }

    private static func payloadData(from json: [String: Any]) -> AnyCodablePayload? {
        let object = nestedPayload(json) ?? json
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return AnyCodablePayload(rawData: data)
    }

    /// Prefer `deliveredAt` (epoch ms) then `deliveredTimestamp` (ISO-8601).
    private static func deliveryTimestamp(from source: [String: Any]) -> Double? {
        if let raw = numericTimestamp(source["deliveredAt"]) {
            return normalizedTimestamp(raw)
        }
        guard let iso = source["deliveredTimestamp"] as? String, !iso.isEmpty else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: iso)?.timeIntervalSince1970
    }

    private static func numericTimestamp(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber:
            return number.doubleValue
        case let value as Double:
            return value
        case let value as Int:
            return Double(value)
        case let value as Int64:
            return Double(value)
        default:
            return nil
        }
    }

    /// Server often sends epoch millis; store seconds for Date(timeIntervalSince1970:).
    private static func normalizedTimestamp(_ raw: Double?) -> Double? {
        guard let raw else { return nil }
        return raw > 10_000_000_000 ? raw / 1000 : raw
    }

    private static func isoTimestamp(_ raw: String?) -> Double? {
        guard let raw, !raw.isEmpty else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: raw) {
            return date.timeIntervalSince1970
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: raw)?.timeIntervalSince1970
    }
}

/// Decodes any MQTT JSON object so we can re-parse with `JSONSerialization`.
struct ChatMqttJSONBox: Decodable, Sendable {
    let data: Data

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let dict = try? container.decode([String: ChatMqttJSONValue].self) {
            let object = dict.mapValues { $0.foundationValue }
            data = try JSONSerialization.data(withJSONObject: object)
            return
        }
        if let array = try? container.decode([ChatMqttJSONValue].self) {
            data = try JSONSerialization.data(withJSONObject: array.map(\.foundationValue))
            return
        }
        if let string = try? container.decode(String.self) {
            data = Data(string.utf8)
            return
        }
        data = Data()
    }
}

private enum ChatMqttJSONValue: Decodable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([ChatMqttJSONValue])
    case object([String: ChatMqttJSONValue])
    case null

    var foundationValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        case .array(let values): return values.map(\.foundationValue)
        case .object(let values): return values.mapValues(\.foundationValue)
        case .null: return NSNull()
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .bool(value); return }
        if let value = try? container.decode(Int.self) { self = .int(value); return }
        if let value = try? container.decode(Double.self) { self = .double(value); return }
        if let value = try? container.decode(String.self) { self = .string(value); return }
        if let value = try? container.decode([ChatMqttJSONValue].self) { self = .array(value); return }
        if let value = try? container.decode([String: ChatMqttJSONValue].self) { self = .object(value); return }
        if container.decodeNil() { self = .null; return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
    }
}
