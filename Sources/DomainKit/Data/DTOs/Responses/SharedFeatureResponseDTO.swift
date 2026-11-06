//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguNetworkKit

public typealias GetBalanceResponseDTO = APIResponseDTO<GetBalanceDTO>

public struct GetBalanceDTO: Codable {
    let id: String
    let user: String
    let client: String
    let name: String
    let category: String
    let type: String
    let isDefault: Bool
    let balance: Double
    let currency: String
}

public typealias UserProfileResponseDTO = APIResponseDTO<UserProfileDataDTO>

public struct UserProfileDataDTO: Codable {
    let name: String
    let phone: String?
}

// MARK: - UserInfos (getProfile)

public typealias UserInfosResponseDTO = APIResponseDTO<UserInfosDataDTO>

public struct UserInfosDataDTO: Codable {
    public let code: String
    public let name: String
    public let phone: String
    public let gender: String
    public let email: String
    public let address: String
    public let city: String
    public let birth: String
    public let nric: String?
    public let qrcode: String
    public let referralCode: String
    public let type: String
    public let company: String
    public let avatar: String
    public let regAt: String
    public let status: String
    public let offer: String
    public let nricType: String
    public let oldNric: String
    public let passportInfo: UserInfosPassportInfoDTO?
    public let nricImages: [String]?
    public let kycType: String
    public let accountType: UserInfosAccountTypeDTO
    public let favoritesCorporate: [String]
    public let documents: [String]?
    public let kycConfig: UserInfosKycConfigDTO
    public let level: Int
    public let document: String
    public let link: String

    enum CodingKeys: String, CodingKey {
        case code, name, phone, gender, email, address, city, birth, nric
        case qrcode
        case referralCode
        case type
        case company, avatar, regAt, status, offer, nricType, oldNric
        case passportInfo, nricImages, kycType
        case accountType, favoritesCorporate, documents, kycConfig, level, document, link
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        phone = try c.decodeIfPresent(String.self, forKey: .phone) ?? ""
        gender = try c.decodeIfPresent(String.self, forKey: .gender) ?? ""
        email = try c.decodeIfPresent(String.self, forKey: .email) ?? ""
        address = try c.decodeIfPresent(String.self, forKey: .address) ?? ""
        city = try c.decodeIfPresent(String.self, forKey: .city) ?? ""
        birth = try c.decodeIfPresent(String.self, forKey: .birth) ?? ""
        nric = try c.decodeIfPresent(String.self, forKey: .nric)
        qrcode = try c.decodeIfPresent(String.self, forKey: .qrcode) ?? ""
        referralCode = try c.decodeIfPresent(String.self, forKey: .referralCode) ?? ""
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
        company = try c.decodeIfPresent(String.self, forKey: .company) ?? ""
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar) ?? ""
        regAt = try c.decodeIfPresent(String.self, forKey: .regAt) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? ""
        offer = try c.decodeIfPresent(String.self, forKey: .offer) ?? ""
        nricType = try c.decodeIfPresent(String.self, forKey: .nricType) ?? ""
        oldNric = try c.decodeIfPresent(String.self, forKey: .oldNric) ?? ""
        passportInfo = try? c.decodeIfPresent(UserInfosPassportInfoDTO.self, forKey: .passportInfo)
        nricImages = try? c.decodeIfPresent([String].self, forKey: .nricImages)
        kycType = try c.decodeIfPresent(String.self, forKey: .kycType) ?? ""
        accountType = (try? c.decodeIfPresent(UserInfosAccountTypeDTO.self, forKey: .accountType)) ?? UserInfosAccountTypeDTO(type: "")
        favoritesCorporate = (try? c.decodeIfPresent([String].self, forKey: .favoritesCorporate)) ?? []
        documents = try? c.decodeIfPresent([String].self, forKey: .documents)
        kycConfig = (try? c.decodeIfPresent(UserInfosKycConfigDTO.self, forKey: .kycConfig)) ?? UserInfosKycConfigDTO.fallback
        level = Self.decodeFlexibleInt(from: c, forKey: .level)
        document = try c.decodeIfPresent(String.self, forKey: .document) ?? ""
        link = try c.decodeIfPresent(String.self, forKey: .link) ?? ""
    }

    public init(
        code: String,
        name: String,
        phone: String,
        gender: String,
        email: String,
        address: String,
        city: String,
        birth: String,
        nric: String?,
        qrcode: String,
        referralCode: String,
        type: String,
        company: String,
        avatar: String,
        regAt: String,
        status: String,
        offer: String,
        nricType: String,
        oldNric: String,
        passportInfo: UserInfosPassportInfoDTO?,
        nricImages: [String]?,
        kycType: String,
        accountType: UserInfosAccountTypeDTO,
        favoritesCorporate: [String],
        documents: [String]?,
        kycConfig: UserInfosKycConfigDTO,
        level: Int,
        document: String,
        link: String
    ) {
        self.code = code
        self.name = name
        self.phone = phone
        self.gender = gender
        self.email = email
        self.address = address
        self.city = city
        self.birth = birth
        self.nric = nric
        self.qrcode = qrcode
        self.referralCode = referralCode
        self.type = type
        self.company = company
        self.avatar = avatar
        self.regAt = regAt
        self.status = status
        self.offer = offer
        self.nricType = nricType
        self.oldNric = oldNric
        self.passportInfo = passportInfo
        self.nricImages = nricImages
        self.kycType = kycType
        self.accountType = accountType
        self.favoritesCorporate = favoritesCorporate
        self.documents = documents
        self.kycConfig = kycConfig
        self.level = level
        self.document = document
        self.link = link
    }

    private static func decodeFlexibleInt<K: CodingKey>(
        from c: KeyedDecodingContainer<K>,
        forKey key: K
    ) -> Int {
        if let v = try? c.decodeIfPresent(Int.self, forKey: key) { return v }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return Int(d) }
        if let s = try? c.decodeIfPresent(String.self, forKey: key), let v = Int(s) { return v }
        return 0
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        try c.encode(name, forKey: .name)
        try c.encode(phone, forKey: .phone)
        try c.encode(gender, forKey: .gender)
        try c.encode(email, forKey: .email)
        try c.encode(address, forKey: .address)
        try c.encode(city, forKey: .city)
        try c.encode(birth, forKey: .birth)
        try c.encodeIfPresent(nric, forKey: .nric)
        try c.encode(qrcode, forKey: .qrcode)
        try c.encode(referralCode, forKey: .referralCode)
        try c.encode(type, forKey: .type)
        try c.encode(company, forKey: .company)
        try c.encode(avatar, forKey: .avatar)
        try c.encode(regAt, forKey: .regAt)
        try c.encode(status, forKey: .status)
        try c.encode(offer, forKey: .offer)
        try c.encode(nricType, forKey: .nricType)
        try c.encode(oldNric, forKey: .oldNric)
        try c.encodeIfPresent(passportInfo, forKey: .passportInfo)
        try c.encodeIfPresent(nricImages, forKey: .nricImages)
        try c.encode(kycType, forKey: .kycType)
        try c.encode(accountType, forKey: .accountType)
        try c.encode(favoritesCorporate, forKey: .favoritesCorporate)
        try c.encodeIfPresent(documents, forKey: .documents)
        try c.encode(kycConfig, forKey: .kycConfig)
        try c.encode(level, forKey: .level)
        try c.encode(document, forKey: .document)
        try c.encode(link, forKey: .link)
    }
}

public struct UserInfosAccountTypeDTO: Codable {
    public let type: String

    public init(type: String) {
        self.type = type
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    enum CodingKeys: String, CodingKey {
        case type
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
    }
}

public struct UserInfosKycConfigDTO: Codable {
    public let alertUpgrade: Bool
    public let existingUser: Bool
    public let noFaceID: Bool
    public let isLv1: Bool
    public let requiredUpdate: Bool

    public static let fallback = UserInfosKycConfigDTO(
        alertUpgrade: false,
        existingUser: false,
        noFaceID: false,
        isLv1: false,
        requiredUpdate: false
    )

    public init(alertUpgrade: Bool, existingUser: Bool, noFaceID: Bool, isLv1: Bool, requiredUpdate: Bool) {
        self.alertUpgrade = alertUpgrade
        self.existingUser = existingUser
        self.noFaceID = noFaceID
        self.isLv1 = isLv1
        self.requiredUpdate = requiredUpdate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        alertUpgrade = try c.decodeIfPresent(Bool.self, forKey: .alertUpgrade) ?? false
        existingUser = try c.decodeIfPresent(Bool.self, forKey: .existingUser) ?? false
        noFaceID = try c.decodeIfPresent(Bool.self, forKey: .noFaceID) ?? false
        isLv1 = try c.decodeIfPresent(Bool.self, forKey: .isLv1) ?? false
        requiredUpdate = try c.decodeIfPresent(Bool.self, forKey: .requiredUpdate) ?? false
    }

    enum CodingKeys: String, CodingKey {
        case alertUpgrade, existingUser, noFaceID, isLv1, requiredUpdate
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(alertUpgrade, forKey: .alertUpgrade)
        try c.encode(existingUser, forKey: .existingUser)
        try c.encode(noFaceID, forKey: .noFaceID)
        try c.encode(isLv1, forKey: .isLv1)
        try c.encode(requiredUpdate, forKey: .requiredUpdate)
    }
}

public struct UserInfosPassportInfoDTO: Codable {
    public init() {}
}

public typealias CountNewNotificationResponseDTO = APIResponseDTO<CountNewNotificationDTO>

public struct CountNewNotificationDTO: Codable {
    let totalNew: Int
}
