//
//  VoucherType.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Type de voucher selon son cycle de vie.
public enum VoucherType: String, Sendable, Codable, CaseIterable {
    case active = "active"
    case past   = "past"
}
