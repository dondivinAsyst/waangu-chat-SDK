////
////  AuthResponse.swift
////  AppModules
////
////  Created by Don divin on 5/20/26.
////
//
import Foundation
import WaanguCoreKit

// MARK: - Auth Session Data (the object inside "data")
public struct AuthSessionData: Codable {
    let redirectUrl: String
    let sessionId: String
    let appId: String
    let userId: String
    let email: String
    let name: String
    let tenantId: String
    let organisationId: String
    let country: String
    let phone: String
    let expiresAt: String
    
    enum CodingKeys: String, CodingKey {
        case redirectUrl
        case sessionId
        case appId
        case userId
        case email
        case name
        case tenantId
        case organisationId
        case country
        case phone
        case expiresAt
    }
}

extension AuthSessionData {
    func toAuthInfo() -> AuthSessionInfo {
        return AuthSessionInfo(
            redirectUrl: redirectUrl,
            sessionId: sessionId,
            appId: appId,
            userId: userId,
            email: email,
            name: name,
            tenantId: tenantId,
            organisationId: organisationId,
            country: country,
            phone: phone,
            expiresAt: DateFormatterProvider.iso8601Date(from: expiresAt) ?? .now
        )
    }
  static  func toFakeAuthInfo() -> AuthSessionInfo {
        return AuthSessionInfo(
            redirectUrl: "",
            sessionId: "924f17af-ff8d-4521-ad4f-079a6b8055e8",
            appId: "",
            userId: "645a3503ddb88a00085da11b", // Sarah mwamba
            email: "",
            name: "Sarah Mwamba",
            tenantId: "",
            organisationId: "",
            country: "",
            phone: "0922222222",
            expiresAt: .now
        )
    }
    
}

// MARK: - API Auth Response
public struct APIAuthResponse: Codable {
    let message: String
    let status: Int
    let data: AuthSessionData
    
    enum CodingKeys: String, CodingKey {
        case message
        case status
        case data
    }
}


// MARK: - Legacy Support (Commented out for reference)
/*
// MARK: - User Data (the object inside "data")
public struct AuthData: Codable {
    let id: String
    let code: String
    let tenantId: String
    let organisationId: String
    let username: String
    let email: String
    let firstName: String
    let lastName: String
    let fullName: String
    let avatar: String
    let phone: String
    let firebaseToken: [String]          // Empty array in example
    let typeUser: String
    let status: String
    let province: String
    let country: String
    let township: String
    let coordinates: Coordinates
    let isBanned: Bool
    let warningCount: Int
    let reportCount: Int
    let trustScore: Int
    let isDeleted: Bool
    let socialAccounts: [String]         // Assuming array of objects or strings
    let moduleContext: [String]          // Adjust if needed
    let createdAt: String
    let updatedAt: String
    let currentlyBanned: Bool
    let active: Bool
    let canLogin: Bool
    let merchant: Bool
    let agent: Bool
    let doctor: Bool
    let driver: Bool
    let customer: Bool
    let admin: Bool
}

extension AuthData {
    func mapper() -> AuthInfo {
        return AuthInfo(
            id: id,
            code: code,
            tenantId: tenantId,
            organisationId: organisationId,
            username: username,
            email: email,
            firstName: firstName,
            lastName: lastName,
            fullName: fullName,
            avatar: avatar,
            phone: phone,
            firebaseToken: firebaseToken,
            typeUser: typeUser,
            status: status,
            province: province,
            country: country,
            township: township,
            coordinates: CoordinatesInfo(
                type: coordinates.type,
                lat: coordinates.lat,
                lng: coordinates.lng,
                name: coordinates.name
            ),
            isBanned: isBanned,
            warningCount: warningCount,
            reportCount: reportCount,
            trustScore: trustScore,
            isDeleted: isDeleted,
            socialAccounts: socialAccounts,
            moduleContext: moduleContext,
            createdAt: createdAt,
            updatedAt: updatedAt,
            currentlyBanned: currentlyBanned,
            active: active,
            canLogin: canLogin,
            merchant: merchant,
            agent: agent,
            doctor: doctor,
            driver: driver,
            customer: customer,
            admin: admin
        )
    }
}

// MARK: - Main API Response
public struct APIAuthResponse: Codable {
    let statusCode: Int
    let message: String
    let data: AuthData
    let metadata: [String: AnyCodable]?   // Handles null or object
    let timestamp: String
}
*/

