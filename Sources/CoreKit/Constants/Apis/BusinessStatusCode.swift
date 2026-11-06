//
//  BusinessStatusCode.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Codes de statut métier retournés par le backend.
///
/// Distincts des codes HTTP standard (200, 401, etc.) qui vivent dans NetworkKit.
/// Ces codes sont spécifiques à la logique métier Waangu.
public enum BusinessStatusCode: Int, Sendable {
    case success      = 200
    case registerUser = 8001
    case registered   = 8004
}
