//
//  DisappearingDuration.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//

import Foundation

public enum DisappearingDuration: Int, CaseIterable, Codable {
    case off = 0
    case twentyFourHours = 86400
    case sevenDays = 604800
    case ninetyDays = 7776000

    var displayName: String {
        switch self {
        case .off: return "Off"
        case .twentyFourHours: return "24 hours"
        case .sevenDays: return "7 days"
        case .ninetyDays: return "90 days"
        }
    }

    var shortLabel: String {
        switch self {
        case .off: return "Off"
        case .twentyFourHours: return "24h"
        case .sevenDays: return "7d"
        case .ninetyDays: return "90d"
        }
    }
}
