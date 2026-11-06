//
//  VoiceMessageTests.swift
//  FeatureChatTests
//
//  Harness 360 — matrice miroir : message vocal.
//  OpusKit enregistre un fichier .opus (Ogg Opus) ; ChatRoomVoiceMessageFlow en
//  fait un contenu à téléverser avant publication ; OutgoingMessageBuilder en
//  garde une copie sous l'identifiant du message. L'enregistrement lui-même
//  (micro, encodeur) n'est pas couvert ici.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class VoiceMessageTests: XCTestCase {

    private var tempFiles: [URL] = []

    override func tearDown() {
        tempFiles.forEach { try? FileManager.default.removeItem(at: $0) }
        super.tearDown()
    }

    // MARK: - Contenu construit depuis l'enregistrement

    func test_recording_becomesAnUploadFirstOggContent() throws {
        let url = URL(fileURLWithPath: "/tmp/voice-123.opus")
        let result = VoiceRecordingResult(url: url, duration: 4.2, fileSize: 2048, waveform: [0.1, 0.8, 0.3])

        let content = try XCTUnwrap(
            ChatRoomVoiceMessageFlow.makeMessageContent(from: ChatRoomVoiceMessageFlow.makeAttachment(from: result))
        )

        XCTAssertEqual(content.audio, url.path)
        XCTAssertEqual(content.audioDuration, 4.2)
        XCTAssertEqual(content.waveform, [0.1, 0.8, 0.3])
        XCTAssertEqual(content.fileName, "voice-123.opus")
        XCTAssertEqual(content.mimeType, "audio/ogg")
        XCTAssertTrue(content.shouldUploadDownload, "a voice note uploads before it is published")
        XCTAssertFalse(content.shouldRetry)
    }

    /// Le fichier doit être téléversé avant la publication MQTT / outbox.
    func test_voiceContent_requiresUploadBeforePublish() throws {
        let result = VoiceRecordingResult(url: URL(fileURLWithPath: "/tmp/v.opus"), duration: 1, fileSize: 1)
        let content = try XCTUnwrap(
            ChatRoomVoiceMessageFlow.makeMessageContent(from: ChatRoomVoiceMessageFlow.makeAttachment(from: result))
        )

        let message = MessageDataItem(codeMessage: "m", typeMessage: .VOICE, message: content, createdAt: Date())

        XCTAssertTrue(OutgoingMessageBuilder.requiresUploadBeforePublish(message))
    }

    func test_photoAttachment_isNotAVoiceContent() {
        let photo = MediaAttachment(id: "p", type: .photo(UIImage()))

        XCTAssertNil(ChatRoomVoiceMessageFlow.makeMessageContent(from: photo))
    }

    // MARK: - Arrêt et envoi

    @MainActor
    func test_stopAndSend_sendsAVoiceMessage_andClearsTheTray() async {
        let tray = Tray()
        let result = VoiceRecordingResult(url: URL(fileURLWithPath: "/tmp/v.opus"), duration: 2, fileSize: 10)

        await ChatRoomVoiceMessageFlow.stopAndSend(result: result, handlers: tray.handlers(sendSucceeds: true))

        XCTAssertEqual(tray.sentTypes, [.VOICE])
        XCTAssertTrue(tray.attachments.isEmpty)
        XCTAssertTrue(tray.errors.isEmpty)
    }

    /// Un envoi refusé le dit, et garde la pièce jointe pour réessayer.
    @MainActor
    func test_stopAndSend_failure_showsTheError_andKeepsTheAttachment() async {
        let tray = Tray()
        let result = VoiceRecordingResult(url: URL(fileURLWithPath: "/tmp/v.opus"), duration: 2, fileSize: 10)

        await ChatRoomVoiceMessageFlow.stopAndSend(result: result, handlers: tray.handlers(sendSucceeds: false))

        XCTAssertEqual(tray.errors, [ChatErrorStrings.sendVoiceFailed])
        XCTAssertEqual(tray.attachments.count, 1)
    }

    @MainActor
    func test_stopAndSend_withoutRecording_doesNothing() async {
        let tray = Tray()

        await ChatRoomVoiceMessageFlow.stopAndSend(result: nil, handlers: tray.handlers(sendSucceeds: true))

        XCTAssertTrue(tray.sentTypes.isEmpty)
        XCTAssertTrue(tray.attachments.isEmpty)
    }

    // MARK: - Préparation avant envoi (chemin réel : ConversationRoomUseCases)

    func test_prepareAudio_copiesTheFileUnderTheMessageId() throws {
        let bytes = Data("OggS-fake-opus".utf8)
        let source = try writeTemp(bytes, ext: "opus")
        let code = "voice-\(UUID().uuidString.lowercased())"
        var content = WaanguFeatureChat.MessageContent()
        content.audio = source.path

        let result = OutgoingMessageBuilder.prepareAudio(content: content, baseMessage: base(code: code))

        guard case .ready(let message, let readyCode) = result else { return XCTFail("expected ready, got \(result)") }
        let saved = URL(fileURLWithPath: try XCTUnwrap(message.message.audio))
        tempFiles.append(saved)
        XCTAssertEqual(readyCode, code)
        XCTAssertEqual(message.message.fileName, "\(code).opus")
        XCTAssertNotEqual(saved.path, source.path, "a copy, so the recorder's temp file can go")
        XCTAssertEqual(try Data(contentsOf: saved), bytes)
        XCTAssertEqual(message.typeMessage, .VOICE)
    }

    func test_prepareAudio_acceptsAFileURLString() throws {
        let source = try writeTemp(Data("x".utf8), ext: "opus")
        var content = WaanguFeatureChat.MessageContent()
        content.audio = source.absoluteString

        let result = OutgoingMessageBuilder.prepareAudio(content: content, baseMessage: base(code: "c-\(UUID().uuidString)"))

        guard case .ready(let message, _) = result else { return XCTFail("expected ready") }
        tempFiles.append(URL(fileURLWithPath: message.message.audio ?? ""))
    }

    func test_prepareAudio_withoutPath_fails() {
        let result = OutgoingMessageBuilder.prepareAudio(content: WaanguFeatureChat.MessageContent(), baseMessage: base(code: "c"))

        guard case .failed = result else { return XCTFail("expected failure") }
    }

    /// Fichier disparu entre l'arrêt et l'envoi : refus, pas de message vide.
    func test_prepareAudio_missingFile_fails() {
        var content = WaanguFeatureChat.MessageContent()
        content.audio = "/tmp/does-not-exist-\(UUID().uuidString).opus"

        let result = OutgoingMessageBuilder.prepareAudio(content: content, baseMessage: base(code: "c"))

        guard case .failed = result else { return XCTFail("expected failure") }
    }

    // MARK: - Passage par la base

    func test_voiceMessage_survivesStorageRoundTrip() {
        var content = WaanguFeatureChat.MessageContent()
        content.audio = "/tmp/v.opus"
        content.audioDuration = 7.5
        content.fileName = "v.opus"
        let message = MessageDataItem(codeMessage: "v-1", senderId: "me", senderName: "Me", typeMessage: .VOICE,
                                      message: content, createdAt: Date(timeIntervalSince1970: 1_791_000_000))
        let crypto = PassthroughFieldCrypto()

        let back = MessageModelMapper.toDomain(
            MessageModelMapper.toModel(from: message, conversationId: "c", fieldCrypto: crypto), fieldCrypto: crypto
        )

        XCTAssertEqual(back.typeMessage, .VOICE)
        XCTAssertEqual(back.message.audioDuration, 7.5)
        XCTAssertEqual(back.message.fileName, "v.opus")
    }

    // MARK: - Outils

    private func base(code: String) -> MessageDataItem {
        MessageDataItem(codeMessage: code, senderId: "me", senderName: "Me", typeMessage: .VOICE,
                        message: WaanguFeatureChat.MessageContent(), createdAt: Date())
    }

    private func writeTemp(_ data: Data, ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        tempFiles.append(url)
        return url
    }
}

/// Barre de pièces jointes de la salle, réduite à ce que le flux appelle.
@MainActor
private final class Tray {
    var attachments: [MediaAttachment] = []
    var sentTypes: [MessageTypeProps] = []
    var errors: [String] = []

    func handlers(sendSucceeds: Bool) -> ChatRoomVoiceMessageFlow.SendHandlers {
        ChatRoomVoiceMessageFlow.SendHandlers(
            appendAttachment: { self.attachments.append($0) },
            firstAudioAttachment: { self.attachments.first { $0.audioDuration != nil } },
            sendMessage: { _, type, _ in
                self.sentTypes.append(type)
                return sendSucceeds ? "code" : nil
            },
            showError: { self.errors.append($0) },
            clearAttachments: { self.attachments.removeAll() }
        )
    }
}

private struct PassthroughFieldCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}
