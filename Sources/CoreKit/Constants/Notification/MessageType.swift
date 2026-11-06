//
//  MessageType.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

/// Origine d'un message : Front Office (client) ou Back Office (système).
public enum MessageType: String, Sendable, Codable, CaseIterable {
    case frontOffice = "FO"
    case backOffice  = "BO"
}
