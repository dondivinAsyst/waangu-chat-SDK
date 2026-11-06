//
//  FetchFieldFormResponseDTO.swift
//  DomainKit — réponse enveloppe du fetch dynamique (2C2B / field form).
//

import Foundation

private enum FetchFieldJSONScalar: Decodable {
    case text(String)

    var displayString: String {
        switch self {
        case .text(let s): return s
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .text(s)
            return
        }
        if let i = try? c.decode(Int.self) {
            self = .text(String(i))
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .text(String(d))
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .text(b ? "true" : "false")
            return
        }
        self = .text("")
    }
}

struct FetchFieldFormResponseDTO: Decodable {
    let err: Int
    let message: String
    let data: [String: String]

    enum CodingKeys: String, CodingKey {
        case err, message, data
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        err = try c.decode(Int.self, forKey: .err)
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        if let dict = try c.decodeIfPresent([String: FetchFieldJSONScalar].self, forKey: .data) {
            data = dict.mapValues(\.displayString)
        } else {
            data = [:]
        }
    }
}
