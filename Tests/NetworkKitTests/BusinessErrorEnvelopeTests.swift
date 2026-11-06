//
//  BusinessErrorEnvelopeTests.swift
//  NetworkKitTests
//
//  Le corps d'une erreur métier n'est remis qu'aux endpoints qui le demandent.
//

import XCTest
@testable import WaanguNetworkKit

final class BusinessErrorEnvelopeTests: XCTestCase {

    func test_envelopeWithCode_isRecognised() {
        let body = Data(#"{"success":false,"data":null,"error":{"code":"CF_005","message":"x"}}"#.utf8)
        XCTAssertTrue(BusinessErrorEnvelope.carriesBusinessCode(body))
    }

    /// Un 4xx ordinaire — sans code métier — garde l'erreur habituelle.
    func test_plainErrorBodies_areNotPassedThrough() {
        XCTAssertFalse(BusinessErrorEnvelope.carriesBusinessCode(Data(#"{"message":"Forbidden"}"#.utf8)))
        XCTAssertFalse(BusinessErrorEnvelope.carriesBusinessCode(Data(#"{"error":{"code":""}}"#.utf8)))
        XCTAssertFalse(BusinessErrorEnvelope.carriesBusinessCode(Data("<html>502</html>".utf8)))
    }

    /// 401 garde le rafraîchissement de jeton, 429 la limitation. Un 5xx
    /// n'est admis que pour être lu avec son code — voir le test suivant.
    func test_onlyBusinessStatuses_passThrough() {
        XCTAssertTrue(BusinessErrorEnvelope.passesThrough(statusCode: 403))
        XCTAssertTrue(BusinessErrorEnvelope.passesThrough(statusCode: 409))
        XCTAssertTrue(BusinessErrorEnvelope.passesThrough(statusCode: 410))
        XCTAssertTrue(BusinessErrorEnvelope.passesThrough(statusCode: 422))
        XCTAssertTrue(BusinessErrorEnvelope.passesThrough(statusCode: 503))
        XCTAssertFalse(BusinessErrorEnvelope.passesThrough(statusCode: 401))
        XCTAssertFalse(BusinessErrorEnvelope.passesThrough(statusCode: 429))
        XCTAssertFalse(BusinessErrorEnvelope.passesThrough(statusCode: 200))
    }

    /// `CF_052` arrive en 503 : c'est une réponse, remise une fois, sans retry.
    /// Une vraie panne 5xx — sans code — garde le retry et le disjoncteur.
    func test_serverErrors_areDeliveredOnlyWithABusinessCode() {
        let biller = Data(#"{"success":false,"statusCode":0,"error":{"code":"CF_052","message":"Biller Hub is not wired","details":null}}"#.utf8)
        XCTAssertTrue(BusinessErrorEnvelope.delivers(statusCode: 503, body: biller))

        XCTAssertFalse(BusinessErrorEnvelope.delivers(statusCode: 503, body: Data()))
        XCTAssertFalse(BusinessErrorEnvelope.delivers(statusCode: 502, body: Data("<html>502</html>".utf8)))
        XCTAssertFalse(BusinessErrorEnvelope.delivers(statusCode: 500, body: Data(#"{"message":"Internal"}"#.utf8)))
        // 401 et 429 gardent leur traitement, même avec un code.
        XCTAssertFalse(BusinessErrorEnvelope.delivers(statusCode: 401, body: biller))
        XCTAssertFalse(BusinessErrorEnvelope.delivers(statusCode: 429, body: biller))
    }
}
