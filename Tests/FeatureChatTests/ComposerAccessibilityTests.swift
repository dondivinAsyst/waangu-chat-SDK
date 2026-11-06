//
//  ComposerAccessibilityTests.swift
//  FeatureChatTests
//
//  CHAT-FE-SDK-W360-B13 — the message input's icon-only controls and its text field have a
//  spoken name. Says nothing about how VoiceOver reads them on a device.
//

import XCTest
@testable import WaanguFeatureChat

@MainActor
final class ComposerAccessibilityTests: XCTestCase {

    func test_textField_takesThePlaceholderAsItsName_andTheLooseLabelStaysSilent() {
        let toolbar = TextInputToolbarAreaView()

        toolbar.updatePlaceholder("Écrire un message")

        XCTAssertEqual(toolbar.textField.accessibilityLabel, "Écrire un message")
        let loose = toolbar.textField.subviews.compactMap { $0 as? UILabel }.first { $0.text == "Écrire un message" }
        XCTAssertEqual(loose?.isAccessibilityElement, false)
    }

    func test_iconOnlyControls_getTheirLocalizedNames() {
        let toolbar = TextInputToolbarAreaView()

        toolbar.configureAccessibility(camera: "Ouvrir l'appareil photo", attach: "Joindre un élément",
                                       send: "Envoyer le message", voice: "Enregistrer un message vocal")

        XCTAssertEqual(toolbar.cameraButton.accessibilityLabel, "Ouvrir l'appareil photo")
        XCTAssertEqual(toolbar.plusButton.accessibilityLabel, "Joindre un élément")
        XCTAssertEqual(toolbar.actionButton.accessibilityLabel, "Envoyer le message")
    }

    /// The four languages carry the same new keys, so no locale falls back to English by accident.
    func test_newKeysExistInEveryLanguageFile() throws {
        let resources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/TranslationKit/Resources")
        let keys = [ChatTranslationKeys.CHAT_A11Y_OPEN_CAMERA, ChatTranslationKeys.CHAT_A11Y_ATTACH,
                    ChatTranslationKeys.CHAT_A11Y_SEND_MESSAGE,
                    ChatTranslationKeys.CHAT_A11Y_PLAY_VOICE, ChatTranslationKeys.CHAT_A11Y_PAUSE_VOICE,
                    ChatTranslationKeys.CHAT_A11Y_PLAYBACK_SPEED, ChatTranslationKeys.CHAT_A11Y_DOWNLOAD,
                    ChatTranslationKeys.CHAT_A11Y_UPLOAD, ChatTranslationKeys.CHAT_A11Y_RETRY_TRANSFER,
                    ChatTranslationKeys.CHAT_A11Y_CANCEL_TRANSFER]
        for language in ["en", "fr", "es", "de"] {
            let url = resources.appendingPathComponent("translations_\(language).json")
            guard let data = try? Data(contentsOf: url) else {
                throw XCTSkip("Source resources are not readable from the test host")
            }
            let text = String(decoding: data, as: UTF8.self)
            for key in keys {
                XCTAssertTrue(text.contains("\"\(key)\""), "\(key) missing in \(language)")
            }
        }
    }
}
