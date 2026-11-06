//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/10/26.
//

import Foundation
import WaanguCoreKit


public protocol LocationRepositoryProtocol {
    func findLocation(request: FindLocation) async -> Result<LocationResponseData, AppError>
}
