//
//  LoyaltyRank.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Rangs du programme de fidélité.
///
/// Chaque `rawValue` correspond au code backend identifiant le tier.
/// L'ordre des cases reflète la hiérarchie (standard → platinum).
public enum LoyaltyRank: String, Sendable, Codable, CaseIterable, Comparable {
    case standard = "052276205774"
    case silver   = "053727057624"
    case gold     = "054432050427"
    case platinum = "055628401985"

    public var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .silver:   return "Silver"
        case .gold:     return "Gold"
        case .platinum: return "Platinum"
        }
    }

    public static func < (lhs: LoyaltyRank, rhs: LoyaltyRank) -> Bool {
        let order: [LoyaltyRank] = [.standard, .silver, .gold, .platinum]
        guard let l = order.firstIndex(of: lhs),
              let r = order.firstIndex(of: rhs) else { return false }
        return l < r
    }
}
