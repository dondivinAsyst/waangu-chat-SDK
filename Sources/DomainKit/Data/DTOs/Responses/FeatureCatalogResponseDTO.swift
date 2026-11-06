//
//  FeatureCatalogResponseDTO.swift
//  AppModules
//
//  Created by Asyst on 3/30/26.
//

import Foundation
import WaanguNetworkKit
import WaanguCoreKit

// MARK: - Response wrapper

typealias FeatureCatalogResponseDTO = APIResponseDTO<[FeatureCatalogDTO]>


struct LocalizedStringDTO: Codable {
    private var translations: [AppLanguage: String]
    
    init(_ translations: [AppLanguage: String]) {
        self.translations = translations
    }
    
    // MARK: - Decodable
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let stringDict = try container.decode([String: String].self)
        
        var result = [AppLanguage: String]()
        for (key, value) in stringDict {
            if let language = AppLanguage(rawValue: key) {
                result[language] = value
            }

        }
        self.translations = result
    }
    
    // MARK: - Encodable
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        var stringDict = [String: String]()
        for (language, value) in translations {
            stringDict[language.rawValue] = value
        }
        try container.encode(stringDict)
    }
    
    // MARK: - Accès
    
    func value(for language: AppLanguage) -> String {
        return translations[language] ?? fallbackValue(for: language)
    }
    
    private func fallbackValue(for requestedLanguage: AppLanguage) -> String {
        if let english = translations[.en], !english.isEmpty {
            return english
        }
        if let anyTranslation = translations.first(where: { !$0.value.isEmpty })?.value {
            return anyTranslation
        }
        return ""
    }
    
    var availableLanguages: [AppLanguage] {
        return Array(translations.keys)
    }
    
    func hasTranslation(for language: AppLanguage) -> Bool {
        return translations[language]?.isEmpty == false
    }
}


// MARK: - Fetch Field Form

struct FetchFieldFormDataDTO: Codable {
    /// e.g. "donation" for group
    let group: String?
}

struct FetchFieldFormValueDTO: Codable {
    let url: String
    let data: FetchFieldFormDataDTO?
}

/// API returns fetchFieldForm as either "" or object { url, data }; decoded accordingly.
enum FetchFieldFormDTO: Codable {
    case empty
    case form(FetchFieldFormValueDTO)
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(FetchFieldFormValueDTO.self) {
            self = .form(value)
        } else if (try? container.decode(String.self)) != nil {
            self = .empty
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "fetchFieldForm must be string or object"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .empty:
            try container.encode("")
        case .form(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Feature Catalog Sub Menu DTO

struct FeatureCatalogSubMenuDTO: Codable {
    let iconId: String
    let name: LocalizedStringDTO
    let shortName: LocalizedStringDTO
    let logo: String
    let type: String
    let form: String
    let fetchFieldForm: FetchFieldFormDTO
    let data: String
    let serviceId: String
    let message: LocalizedStringDTO
    let serviceState: Bool
}

// MARK: - Feature Catalog DTO (Response)

struct FeatureCatalogDTO: Codable {
    let serviceState: Bool
    let id: String
    let name: LocalizedStringDTO
    let shortName: LocalizedStringDTO
    let logo: String
    let form: String
    let data: String
    let lever: String
    let serviceId: String
    let type: String
    let subMenu: [FeatureCatalogSubMenuDTO]
    let fetchFieldForm: FetchFieldFormDTO
    let message: LocalizedStringDTO
}


//MARK: HOMEICON VERSION
struct FeatureCatalogVersionResponseDTO: Decodable {
    let err: Int
    let message: String
    let refresh: Bool
    let country: String
    let version: String
}


 struct BillerFormDataDTO : Decodable {
    let billerFormId: String
}
