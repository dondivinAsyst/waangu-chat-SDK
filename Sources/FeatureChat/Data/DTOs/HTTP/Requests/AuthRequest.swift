////
////  AuthRequest.swift
////  AppModules
////
////  Created by Don divin on 5/20/26.
////
//
//import Foundation
//import CoreKit
//
//// MARK: - Coordinates DTO
//public struct Coordinates: Codable {
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
//// MARK: - User DTO
//public struct AuthRequest: Codable {
//    let id: String
//    let username: String
//    let email: String
//    let firstName: String
//    let lastName: String
//    let phone: String
//    let typeUser: String
//    let code: String
//    let tenantId: String
//    let organisationId: String
//    let avatar: String
//    let province: String
//    let country: String
//    let township: String
//    let coordinates: Coordinates
//    let gender: String
//    
//   public init(id: String, username: String, email: String, firstName: String, lastName: String, phone: String, typeUser: String, code: String, tenantId: String, organisationId: String, avatar: String, province: String, country: String, township: String, coordinates: Coordinates, gender: String) {
//        self.id = id
//        self.username = username
//        self.email = email
//        self.firstName = firstName
//        self.lastName = lastName
//        self.phone = phone
//        self.typeUser = typeUser
//        self.code = code
//        self.tenantId = tenantId
//        self.organisationId = organisationId
//        self.avatar = avatar
//        self.province = province
//        self.country = country
//        self.township = township
//        self.coordinates = coordinates
//        self.gender = gender
//    }
//    
//}
//
//extension AuthRequest {
//    static func mapper(_ userInfo: UserInfos) -> AuthRequest {
//        return AuthRequest(
//            id: userInfo.code,
//            username: userInfo.name,
//            email: userInfo.email,
//            firstName: extractFirstName(from: userInfo.name),
//            lastName: extractLastName(from: userInfo.name),
//            phone: userInfo.phone,
//            typeUser: userInfo.type,
//            code: userInfo.code,
//            tenantId: "", // Not available in UserInfos
//            organisationId: "", // Not available in UserInfos
//            avatar: userInfo.avatar,
//            province: "", // Not available in UserInfos
//            country: "", // Not available in UserInfos
//            township: userInfo.city,
//            coordinates: Coordinates(type: "Point", lat: 0.0, lng: 0.0, name: nil),
//            gender: userInfo.gender
//        )
//    }
//    
//    private static func extractFirstName(from fullName: String) -> String {
//        let components = fullName.split(separator: " ")
//        return components.first.map(String.init) ?? fullName
//    }
//    
//    private static func extractLastName(from fullName: String) -> String {
//        let components = fullName.split(separator: " ")
//        return components.count > 1 ? components.dropFirst().joined(separator: " ") : ""
//    }
//    
//    
//    // MARK: - Example Usage
//   static let fakeUser = AuthRequest(
//        id: "645a3503ddb88a00085da11a",
//        username: "JEAN_DOE",
//        email: "jeandoe@gmail.com",
//        firstName: "Jean",
//        lastName: "Doe",
//        phone: "0911111111",
//        typeUser: "CUSTOMER",
//        code: "10000001",
//        tenantId: "",
//        organisationId: "",
//        avatar: "https://digital-wallet-sandbox-bucket.s3.us-east-1.amazonaws.com/Uploads/customer/avatar-user.png",
//        province: "Kinshasa",
//        country: "RDC",
//        township: "Gombe",
//        coordinates: Coordinates(
//            type: "Point",
//            lat: -4.3026,
//            lng: 15.3072,
//            
//        ),
//        gender: "Male"
//    )
//}

import WaanguCoreKit
public struct AuthRequest: Codable {
    let device: Device
    /// Optional and, by Identity's answer of 2026-11-05, only a fallback display name: the
    /// session's user is the `appUserId` that the app's `verify-user` webhook returns for the
    /// Bearer token. Left `nil`, the key is not sent.
    let userIdentifier: String?

    enum CodingKeys: String, CodingKey {
        case device
        case userIdentifier = "user_identifier"
    }
}

public struct Device: Codable {
    let deviceId: String
    let platform: String
    let model: String
    let appVersion: String
    let ip: String
    let city: String
}

extension AuthRequest {
    static func mapper(deviceInfo:DeviceContext,userIdentifier:String? = nil) -> AuthRequest {
        .init(device: .init(deviceId: deviceInfo.deviceId, platform: deviceInfo.platformOS, model: deviceInfo.deviceModel, appVersion: deviceInfo.appVersion, ip: "", city: ""), userIdentifier: userIdentifier)
    }
}
