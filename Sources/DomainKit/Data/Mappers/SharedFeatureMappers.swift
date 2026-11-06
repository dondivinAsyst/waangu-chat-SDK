//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 3/31/26.
//

import Foundation
import WaanguCoreKit

enum SharedFeatureMappers {
    static func map(responseDTO: GetBalanceResponseDTO) -> GetBalance? {
        guard let dto = responseDTO.data else { return nil }
        return map(dto: dto)
    }
    
    // MARK: - GetBalance
    static func map(dto: GetBalanceDTO) -> GetBalance {
        GetBalance(
            id: dto.id,
            userId: dto.user,
            client: dto.client,
            name: dto.name,
            category: dto.category,
            type: dto.type,
            isDefault: dto.isDefault,
            balance: dto.balance,
            currency: dto.currency
        )
    }
    
    static func map(entity: GetBalance) -> GetBalanceDTO {
        GetBalanceDTO(
            id: entity.id,
            user: entity.userId,
            client: entity.client,
            name: entity.name,
            category: entity.category,
            type: entity.type,
            isDefault: entity.isDefault,
            balance: entity.balance,
            currency: entity.currency
        )
    }
    
    static func toEntity(dto: UserProfileDataDTO) -> UserProfile {
        UserProfile(name: dto.name)
    }

    // MARK: - UserInfos

    static func toEntity(dto: UserInfosDataDTO) -> UserInfos {
        UserInfos(
            code: dto.code,
            name: dto.name,
            phone: dto.phone,
            gender: dto.gender,
            email: dto.email,
            address: dto.address,
            city: dto.city,
            birth: dto.birth,
            nric: dto.nric,
            qrcode: dto.qrcode,
            referralCode: dto.referralCode,
            type: dto.type,
            company: dto.company,
            avatar: dto.avatar,
            regAt: dto.regAt,
            status: dto.status,
            offer: dto.offer,
            nricType: dto.nricType,
            oldNric: dto.oldNric,
            passportInfo: dto.passportInfo.map { _ in PassportInfoEntity() },
            nricImages: dto.nricImages,
            kycType: dto.kycType,
            accountType: AccountTypeEntity(type: dto.accountType.type),
            favoritesCorporate: dto.favoritesCorporate,
            documents: dto.documents,
            kycConfig: KycConfigEntity(
                alertUpgrade: dto.kycConfig.alertUpgrade,
                existingUser: dto.kycConfig.existingUser,
                noFaceID: dto.kycConfig.noFaceID,
                isLv1: dto.kycConfig.isLv1,
                requiredUpdate: dto.kycConfig.requiredUpdate
            ),
            level: dto.level,
            document: dto.document,
            link: dto.link
        )
    }
    
    static func map(responseDTO: CountNewNotificationResponseDTO) -> CountNewNotification? {
        guard let dto = responseDTO.data else { return nil }
        return map(dto: dto)
    }
    
    static func map(dto: CountNewNotificationDTO) -> CountNewNotification {
        return CountNewNotification(
            totalNew: dto.totalNew
        )
    }
    
    static func map(entity: CountNewNotification) -> CountNewNotificationDTO {
        return CountNewNotificationDTO(
            totalNew: entity.totalNew
        )
    }
}
