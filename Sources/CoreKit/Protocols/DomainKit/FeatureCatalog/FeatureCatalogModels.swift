//
//  FeatureCatalog.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//
import Foundation

public struct LocalizedStringEntity: Equatable {
    public private(set) var translations: [AppLanguage: String]
    
    public init(_ translations: [AppLanguage: String]) {
        self.translations = translations
    }
    
    public func value(for language: AppLanguage) -> String {
        return translations[language] ?? translations[.en] ?? ""
    }
    
    public subscript(language: AppLanguage) -> String {
        return value(for: language)
    }
}


public struct FetchFieldFormDataEntity: Equatable {
    public let group: String?
    
    public init(group: String?) {
        self.group = group
    }
}

public struct FetchFieldFormValueEntity: Equatable {
    public let url: String
    public let data: FetchFieldFormDataEntity?
    
    public init(url: String, data: FetchFieldFormDataEntity?) {
        self.url = url
        self.data = data
    }
}

public enum FetchFieldFormEntity: Equatable {
    case empty
    case form(FetchFieldFormValueEntity)
}

public struct FeatureCatalogSubMenu: Equatable {
    public let iconId: String
    public let name: LocalizedStringEntity
    public let shortName: LocalizedStringEntity
    public let logo: String
    public let type: String
    public let form: String
    public let fetchFieldForm: FetchFieldFormEntity
    public let data: BillerFormDataFeatureCatalogEntity
    public let serviceId: String
    public let message: LocalizedStringEntity
    public let serviceState: Bool
    
    public init(iconId: String, name: LocalizedStringEntity, shortName: LocalizedStringEntity,
                logo: String, type: String, form: String, fetchFieldForm: FetchFieldFormEntity,
                data: BillerFormDataFeatureCatalogEntity, serviceId: String, message: LocalizedStringEntity, serviceState: Bool) {
        self.iconId = iconId
        self.name = name
        self.shortName = shortName
        self.logo = logo
        self.type = type
        self.form = form
        self.fetchFieldForm = fetchFieldForm
        self.data = data
        self.serviceId = serviceId
        self.message = message
        self.serviceState = serviceState
    }
}

public struct BillerFormDataFeatureCatalogEntity : Equatable {
    
   public let billerFormId: String
    
   public static let empty = BillerFormDataFeatureCatalogEntity(billerFormId: "")
    
   public init(billerFormId: String){
        self.billerFormId = billerFormId
    }
}

public struct FeatureCatalog: Equatable {
    public let serviceState: Bool
    public let id: String
    public let name: LocalizedStringEntity
    public let shortName: LocalizedStringEntity
    public let logo: String
    public let form: String
    public let data: String
    public let lever: String
    public let serviceId: String
    public let type: String
    public let subMenu: [FeatureCatalogSubMenu]
    public let fetchFieldForm: FetchFieldFormEntity
    public let message: LocalizedStringEntity
    
    public init(serviceState: Bool, id: String, name: LocalizedStringEntity, shortName: LocalizedStringEntity,
                logo: String, form: String, data: String, lever: String, serviceId: String, type: String,
                subMenu: [FeatureCatalogSubMenu], fetchFieldForm: FetchFieldFormEntity, message: LocalizedStringEntity) {
        self.serviceState = serviceState
        self.id = id
        self.name = name
        self.shortName = shortName
        self.logo = logo
        self.form = form
        self.data = data
        self.lever = lever
        self.serviceId = serviceId
        self.type = type
        self.subMenu = subMenu
        self.fetchFieldForm = fetchFieldForm
        self.message = message
    }
}


//MARK: Version Result

public enum FeatureCatalogVersionResult {
    case forceRefreshIcon
    case noNeedToRefreshIcon
}
