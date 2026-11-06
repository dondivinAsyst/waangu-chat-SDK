////
////  AuthEntity.swift
////  AppModules
////
////  Created by Don divin on 5/20/26.
////
//
import Foundation
import WaanguCoreKit

public struct AuthSessionInfo: Equatable, Sendable {
    public let redirectUrl: String
    public let sessionId: String
    public let appId: String
    public let userId: String
    public let email: String
    public let name: String
    public let tenantId: String
    public let organisationId: String
    public let country: String
    public let phone: String
    public let expiresAt: Date

    public init(
        redirectUrl: String,
        sessionId: String,
        appId: String,
        userId: String,
        email: String,
        name: String,
        tenantId: String,
        organisationId: String,
        country: String,
        phone: String,
        expiresAt: Date
    ) {
        self.redirectUrl = redirectUrl
        self.sessionId = sessionId
        self.appId = appId
        self.userId = userId
        self.email = email
        self.name = name
        self.tenantId = tenantId
        self.organisationId = organisationId
        self.country = country
        self.phone = phone
        self.expiresAt = expiresAt
    }
}
//
//public struct CoordinatesInfo:Equatable {
//    let type: String
//    let lat: Double
//    let lng: Double
//    let name: String?
//    public init(type: String, lat: Double, lng: Double, name: String? = nil) {
//        self.type = type
//        self.lat = lat
//        self.lng = lng
//        self.name = name
//    }
//}
//
//public struct AuthInfo: Identifiable, Equatable {
//    public let id: String
//    let code: String
//    let tenantId: String
//    let organisationId: String
//    let username: String
//    let email: String
//    let firstName: String
//    let lastName: String
//    let fullName: String
//    let avatar: String
//    let phone: String
//    let firebaseToken: [String]          // Empty array in example
//    let typeUser: String
//    let status: String
//    let province: String
//    let country: String
//    let township: String
//    let coordinates: CoordinatesInfo
//    let isBanned: Bool
//    let warningCount: Int
//    let reportCount: Int
//    let trustScore: Int
//    let isDeleted: Bool
//    let socialAccounts: [String]         // Assuming array of objects or strings
//    let moduleContext: [String]          // Adjust if needed
//    let createdAt: String
//    let updatedAt: String
//    let currentlyBanned: Bool
//    let active: Bool
//    let canLogin: Bool
//    let merchant: Bool
//    let agent: Bool
//    let doctor: Bool
//    let driver: Bool
//    let customer: Bool
//    let admin: Bool
//
//}
//
//


