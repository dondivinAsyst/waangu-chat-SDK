//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation

public struct GetBalance: Equatable {
    public let id: String
    public let userId: String
    public let client: String
    public let name: String
    public let category: String
    public let type: String
    public let isDefault: Bool
    public let balance: Double
    public let currency: String
    
    public init(id: String, userId: String, client: String, name: String, category: String, type: String, isDefault: Bool, balance: Double, currency: String) {
        self.id = id
        self.userId = userId
        self.client = client
        self.name = name
        self.category = category
        self.type = type
        self.isDefault = isDefault
        self.balance = balance
        self.currency = currency
    }
}


//MARK: USER PROFILE PUBLIC MODEL

public struct UserProfile: Equatable, Sendable {
    public let name: String
    
    public init(name: String) {
        self.name = name
    }
}

//MARK: USERINFOS PUBLIC MODEL

public struct UserInfos: Equatable {
    public let code: String
    public let name: String
    public let phone: String
    public let gender: String
    public let email: String
    public let address: String
    public let city: String
    public let birth: String
    // nric: optional (null in Postman)
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
    // passportInfo: optional (null in Postman)
    public let passportInfo: PassportInfoEntity?
    // nricImages: optional (null in Postman)
    public let nricImages: [String]?
    public let kycType: String
    public let accountType: AccountTypeEntity
    public let favoritesCorporate: [String]
    // documents: optional (null in Postman)
    public let documents: [String]?
    public let kycConfig: KycConfigEntity
    public let level: Int
    public let document: String
    public let link: String

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
        passportInfo: PassportInfoEntity?,
        nricImages: [String]?,
        kycType: String,
        accountType: AccountTypeEntity,
        favoritesCorporate: [String],
        documents: [String]?,
        kycConfig: KycConfigEntity,
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
}

public struct AccountTypeEntity: Equatable {
    public let type: String

    public init(type: String) {
        self.type = type
    }
}

public struct KycConfigEntity: Equatable {
    public let alertUpgrade: Bool
    public let existingUser: Bool
    public let noFaceID: Bool
    public let isLv1: Bool
    public let requiredUpdate: Bool

    public init(
        alertUpgrade: Bool,
        existingUser: Bool,
        noFaceID: Bool,
        isLv1: Bool,
        requiredUpdate: Bool
    ) {
        self.alertUpgrade = alertUpgrade
        self.existingUser = existingUser
        self.noFaceID = noFaceID
        self.isLv1 = isLv1
        self.requiredUpdate = requiredUpdate
    }
}

public struct PassportInfoEntity: Equatable {
    // Placeholder when API returns object; extend when needed
    public init() {}
}

public struct CountNewNotification {
    public let totalNew: Int
    
    public init(totalNew: Int) {
        self.totalNew = totalNew
    }
}
