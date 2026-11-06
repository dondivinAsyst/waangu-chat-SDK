//
//  NotificationAction.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Action associée à une notification push.
///
/// Détermine le deep link ou le comportement au tap sur la notification.
public enum NotificationAction: String, Sendable, Codable, CaseIterable {
    case request              = "request"
    case none                 = "none"
    case transaction          = "transaction"
    case earnPoint            = "earnPoint"
    case buyVoucher           = "buyVoucher"
    case newPromotion         = "newPromotion"
    case earnPointToNextTier  = "earnPointToNextTier"
    case voucherExpiredSoon   = "voucherExpiredSoon"
    case weeklyPointEarn      = "weeklyPointEarn"
    case pointExpiredSoon     = "pointExpiredSoon"

    /// Actions qui nécessitent une navigation vers un écran spécifique.
    public var requiresNavigation: Bool {
        switch self {
        case .none: return false
        default:    return true
        }
    }
}
