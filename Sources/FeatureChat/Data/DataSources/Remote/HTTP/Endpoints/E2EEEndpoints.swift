import Foundation
import WaanguCoreKit
import WaanguNetworkKit

enum E2EEEndpoints: APIEndpoint {
    case registerKeys(E2EEKeyRegistrationRequest)
    case fetchKeyBundle(userId: String)

    var path: String {
        switch self {
        case .registerKeys:
            return "/api/v1/e2ee/keys/register"
        case .fetchKeyBundle(let userId):
            return "/api/v1/e2ee/keys/\(userId)"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .registerKeys:  return .post
        case .fetchKeyBundle: return .get
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .registerKeys(let request):
            return (try? request.toDictionary()) ?? [:]
        case .fetchKeyBundle:
            return nil
        }
    }

    var headers: [String: String]? {
        return [
            "Content-Type": "application/json",
            "X-Correlation-Id": CorrelationId().value,  // B59 — même règle que ChatFinanceEndpoints
        ]
    }
}

struct E2EEKeyRegistrationRequest: Codable {
    let userId: String
    let identityKey: String       // base64
    let signedPreKey: String      // base64
    let signedPreKeySignature: String // base64
    let oneTimePreKeys: [String]  // array of base64

    func toDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}

struct E2EEKeyBundleResponse: Codable {
    let userId: String
    let identityKey: String
    let signedPreKey: String
    let signedPreKeySignature: String
    let oneTimePreKeys: [String]

    func toPublicKeyBundle() -> PublicKeyBundle? {
        guard let idKey = Data(base64Encoded: identityKey),
              let spk = Data(base64Encoded: signedPreKey),
              let sig = Data(base64Encoded: signedPreKeySignature)
        else { return nil }

        let otpks = oneTimePreKeys.compactMap { Data(base64Encoded: $0) }

        return PublicKeyBundle(
            userId: userId,
            identityKey: idKey,
            signedPreKey: spk,
            signedPreKeySignature: sig,
            oneTimePreKeys: otpks
        )
    }
}
