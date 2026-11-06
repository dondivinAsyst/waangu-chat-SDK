//
//  FinanceCoreTestDoubles.swift
//  FeatureChatTests
//
//  Doublures partagées des tests Chat Core Finance.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit
@testable import WaanguFeatureChat

/// Client HTTP qui sert le JSON du contrat par route et consigne l'ordre des appels.
///
/// Il se place **sous** `HTTPChatFinanceDataSource` : les tests traversent donc
/// le vrai `ChatFinanceEndpoints` (chemins, corps typés, en-têtes, clé
/// d'idempotence) et le vrai déballage d'enveloppe, et non une copie.
actor ScriptedChatCoreAPIClient: APIClientProtocol {
    struct Call: @unchecked Sendable {
        let route: String
        let body: [String: Any]
        let query: [String: String]
        let headers: [String: String]
    }

    private let routes: [String: String]
    /// Réponses successives d'une même route : la première pour le premier
    /// appel, et ainsi de suite. Une route qui change entre deux lectures —
    /// la sécurité avant et après une reprise de session — ne se décrit pas
    /// autrement.
    private var sequences: [String: [String]]
    private(set) var calls: [Call] = []

    init(routes: [String: String], sequences: [String: [String]] = [:]) {
        self.routes = routes
        self.sequences = sequences
    }

    var isConnected: Bool { get async { true } }

    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        let method = endpoint.method.rawValue.uppercased()
        let route = "\(method) \(endpoint.path)"
        let isGet = method == "GET"
        calls.append(Call(route: route,
                          body: isGet ? [:] : (endpoint.parameters ?? [:]),
                          query: isGet ? (endpoint.parameters ?? [:]).compactMapValues { $0 as? String } : [:],
                          headers: endpoint.headers ?? [:]))

        // Route absente : rien n'est parti, comme sans réseau.
        let scripted = sequences[route]?.isEmpty == false ? sequences[route]?.removeFirst() : nil
        guard let json = scripted ?? routes[route] else { throw APIError.noInternetConnection }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(json.utf8))
    }

    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }

    /// La source de données réelle, posée sur ce client.
    nonisolated var dataSource: HTTPChatFinanceDataSource {
        HTTPChatFinanceDataSource(httpClient: self)
    }
}

/// Enveloppes du contrat §0.4.
enum FinanceCoreJSON {
    static func wrap(_ data: String) -> String {
        #"{ "success": true, "message": null, "statusCode": 200, "data": \#(data), "error": null, "timestamp": "2026-09-09T12:00:00Z" }"#
    }

    static func error(_ code: String) -> String {
        #"{ "success": false, "message": null, "statusCode": 0, "data": null, "error": { "code": "\#(code)", "message": "x", "details": null }, "timestamp": "2026-09-09T12:00:01Z" }"#
    }
}
