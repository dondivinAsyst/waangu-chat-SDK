//
//  FeatureCatalogMappers.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import WaanguCoreKit


import Foundation

enum FeatureCatalogMappers {
    
    // MARK: - Public
    
    static func toDomain(_ dto: FeatureCatalogDTO) -> FeatureCatalog {
        FeatureCatalog(
            serviceState: dto.serviceState,
            id: dto.id,
            name: toLocalizedStringEntity(dto.name),
            shortName: toLocalizedStringEntity(dto.shortName),
            logo: dto.logo,
            form: dto.form,
            data: dto.data,
            lever: dto.lever,
            serviceId: dto.serviceId,
            type: dto.type,
            subMenu: dto.subMenu.map { toSubMenuDomain($0) },
            fetchFieldForm: toFetchFieldFormEntity(dto.fetchFieldForm),
            message: toLocalizedStringEntity(dto.message)
        )
    }
    
    // MARK: - SubMenu Mapper
    
    private static func toSubMenuDomain(_ dto: FeatureCatalogSubMenuDTO) -> FeatureCatalogSubMenu {
        FeatureCatalogSubMenu(
            iconId: dto.iconId,
            name: toLocalizedStringEntity(dto.name),
            shortName: toLocalizedStringEntity(dto.shortName),
            logo: dto.logo,
            type: dto.type,
            form: dto.form,
            fetchFieldForm: toFetchFieldFormEntity(dto.fetchFieldForm),
            data: parseBillerFormData(dto.data),
            serviceId: dto.serviceId,
            message: toLocalizedStringEntity(dto.message),
            serviceState: dto.serviceState
        )
    }
    
    // MARK: - Embedded JSON Parsing (String → Entity)
    
    private static func parseBillerFormData(_ raw: String) -> BillerFormDataFeatureCatalogEntity {
        
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard !trimmed.isEmpty,
              let jsonData = trimmed.data(using: .utf8),
              let dto = try? JSONDecoder().decode(BillerFormDataDTO.self, from: jsonData)
        else {
            return .empty
        }
        
        return toBillerFormEntity(dto)
    }
    
    // MARK: - DTO → Entity
    
    private static func toBillerFormEntity(_ dto: BillerFormDataDTO) -> BillerFormDataFeatureCatalogEntity {
        BillerFormDataFeatureCatalogEntity(
            billerFormId: dto.billerFormId
        )
    }
    
    // MARK: - Localized String Mapper
    
    private static func toLocalizedStringEntity(_ dto: LocalizedStringDTO) -> LocalizedStringEntity {
        var translations: [AppLanguage: String] = [:]
        
        for language in AppLanguage.allCases {
            let value = dto.value(for: language)
            if !value.isEmpty {
                translations[language] = value
            }
        }
        
        return LocalizedStringEntity(translations)
    }
    
    // MARK: - FetchFieldForm Mapper
    
    private static func toFetchFieldFormEntity(_ dto: FetchFieldFormDTO) -> FetchFieldFormEntity {
        switch dto {
        case .empty:
            return .empty
            
        case .form(let value):
            return .form(toFetchFieldFormValueEntity(value))
        }
    }
    
    private static func toFetchFieldFormValueEntity(_ dto: FetchFieldFormValueDTO) -> FetchFieldFormValueEntity {
        FetchFieldFormValueEntity(
            url: dto.url,
            data: dto.data.map {
                FetchFieldFormDataEntity(group: $0.group)
            }
        )
    }
}
