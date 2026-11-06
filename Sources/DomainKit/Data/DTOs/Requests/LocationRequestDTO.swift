//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/9/26.
//

import Foundation

public struct FindLocationRequestDTO: Codable {
    
    public let distance: Double?
    public let search: String?
    public let start: Int?
    public let number: Int?
    public let type: String?
}
