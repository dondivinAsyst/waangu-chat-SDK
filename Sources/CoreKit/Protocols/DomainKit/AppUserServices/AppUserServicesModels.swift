//
//  AppUserServicesModels.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

//MARK: TYPE

public enum TypeService : String {
    case all
}


// Enum métier pour les channels
public enum Channel: String, Sendable {
    case mobile
    case web
    case unknown
}

// Enum métier pour le status
public enum ServiceStatus: Int, Sendable {
    case inactive = 0
    case active = 1
    case unknown
}

// Entité métier
// CoreKit/Models/AppUserService.swift
public struct AppUserService: Sendable {
    public let id: String
    public let code: String
    public let name: String
    public let desc: String
    public let channels: [Channel]
    public let status: ServiceStatus
    public let version: Int?

    public init(
        id: String,
        code: String,
        name: String,
        desc: String,
        channels: [Channel],
        status: ServiceStatus,
        version: Int?
    ) {
        self.id = id
        self.code = code
        self.name = name
        self.desc = desc
        self.channels = channels
        self.status = status
        self.version = version
    }
}
