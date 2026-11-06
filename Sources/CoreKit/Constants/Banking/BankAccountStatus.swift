//
//  BankAccountStatus.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Statut de liaison d'un compte bancaire.
public enum BankAccountStatus: String, Sendable, Codable, CaseIterable {
    case linked  = "linked"
    case pending = "pending"
    case expired = "expired"

    public var isActive: Bool { self == .linked }
}
