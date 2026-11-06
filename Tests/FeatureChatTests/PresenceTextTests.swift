//
//  PresenceTextTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.15 — « vu … à … » dans la langue de l'app, avec une heure
//  après « à », jamais une date.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Interpole `%1$s`, `%2$s`… dans le modèle donné pour une clé.
private final class TemplateTranslationService: TranslationServiceProtocol {
    private let templates: [String: String]

    init(templates: [String: String]) { self.templates = templates }

    func resolve(key: String, module: String, args: [String]) -> TranslationResult {
        var value = templates[key] ?? key
        for (index, arg) in args.enumerated() {
            value = value.replacingOccurrences(of: "%\(index + 1)$s", with: arg)
        }
        return TranslationResult(key: key, module: module, locale: activeLocale,
                                 value: value, resolution: templates[key] == nil ? .keyFallback : .module)
    }

    func resolveAll(keys: [String], module: String, args: [String]) -> [TranslationResult] {
        keys.map { resolve(key: $0, module: module, args: args) }
    }

    func resolveRequests(_ requests: [(key: String, args: [String])], module: String) -> [TranslationResult] {
        requests.map { resolve(key: $0.key, module: module, args: $0.args) }
    }

    func updatePayload(_ payload: TranslationPayload) {}
    func updatePayload(from data: Data, using mapper: ([String: Any]) -> TranslationPayload?) {}
    func reloadPayload(for locale: String) {}
    var activePayloadVersion: Int { 1 }
    var activeLocale: String { "en" }
}

final class PresenceTextTests: XCTestCase {

    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    private func translator(_ template: String) -> TemplateTranslationService {
        TemplateTranslationService(templates: [ChatTranslationKeys.CHAT_LAST_SEEN_AT: template])
    }

    func test_usesTheLastSeenKey_withDayThenTime() {
        let text = ChatRoomPresenceText.lastSeenText(
            at: Date(), translator: translator("<%1$s|%2$s>"), locale: english)

        XCTAssertTrue(text.hasPrefix("<Today|"), text)
        XCTAssertTrue(text.contains(":"), "la deuxième partie est une heure : \(text)")
    }

    func test_yesterday_isSaidAsYesterday() {
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let text = ChatRoomPresenceText.lastSeenText(
            at: yesterday, translator: translator("%1$s"), locale: english)

        XCTAssertEqual(text, "Yesterday")
    }

    /// La version anglaise remplacée écrivait une date après « at » pour tout jour passé.
    func test_anOlderDay_isFollowedByATime_notADate() {
        let older = Calendar.current.date(byAdding: .day, value: -10, to: Date())!
        let text = ChatRoomPresenceText.lastSeenText(
            at: older, translator: translator("%2$s"), locale: english)

        XCTAssertTrue(text.contains(":"), text)
        XCTAssertFalse(text.contains("/"), text)
    }

    func test_dayFollowsTheLocale() {
        let text = ChatRoomPresenceText.lastSeenText(
            at: Date(), translator: translator("%1$s"), locale: french)

        XCTAssertEqual(text.lowercased(), "aujourd’hui")
    }

    func test_withoutATranslator_keepsTheEnglishSentence() {
        let text = ChatRoomPresenceText.lastSeenText(at: Date(), translator: nil, locale: english)

        XCTAssertTrue(text.hasPrefix("last seen Today at "), text)
    }
}
