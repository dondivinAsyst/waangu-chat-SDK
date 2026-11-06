//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/9/26.
//

public protocol FindLocationUseCaseProtocol {
    func execute(request: FindLocation) async -> Result<LocationResponseData, AppError>
}

//MARK: FACTORY

public struct LocationUsecases: Sendable {
    public let findLocation: any FindLocationUseCaseProtocol

    public init(
        findLocation: any FindLocationUseCaseProtocol
    ) {
        self.findLocation = findLocation
    }
   
}

