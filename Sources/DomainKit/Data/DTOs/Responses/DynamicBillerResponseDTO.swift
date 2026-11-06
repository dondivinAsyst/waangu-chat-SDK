//
//  DynamicBillerResponseDTO.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation

// MARK: - Int souple (API hétérogène : bool / int / string)

private enum FlexibleIntDecoding {
    /// Décode un entier métier : accepte `Bool`, `Int`, `String`, `Double` (JSON backend incohérent).
    static func decode<K: CodingKey>(from c: KeyedDecodingContainer<K>, key: K, default defaultValue: Int = 0) -> Int {
        guard c.contains(key) else { return defaultValue }
        if let b = try? c.decode(Bool.self, forKey: key) {
            return b ? 1 : 0
        }
        if let i = try? c.decode(Int.self, forKey: key) {
            return i
        }
        if let s = try? c.decode(String.self, forKey: key) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int(t) { return v }
            switch t.lowercased() {
            case "true", "yes", "1": return 1
            case "false", "no", "0": return 0
            default: return defaultValue
            }
        }
        if let d = try? c.decode(Double.self, forKey: key) {
            return Int(d)
        }
        return defaultValue
    }
}

// MARK: - fetchFieldForm (string ou objet)

private enum LossyJSONValue: Codable {
    case string(String)

    var stringValue: String {
        switch self {
        case .string(let s): return s
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            self = .string(s)
            return
        }
        if let i = try? c.decode(Int.self) {
            self = .string(String(i))
            return
        }
        if let d = try? c.decode(Double.self) {
            self = .string(String(d))
            return
        }
        if let b = try? c.decode(Bool.self) {
            self = .string(b ? "true" : "false")
            return
        }
        throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value"))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        }
    }
}

private struct DynamicBillerFetchFieldFormDTO: Codable {
    let url: String
    let method: String
    let data: [String: String]?
    let childs: [String]?

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        method = try c.decode(String.self, forKey: .method)
        childs = try c.decodeIfPresent([String].self, forKey: .childs)
        if let plain = try? c.decode([String: String].self, forKey: .data) {
            data = plain
        } else if let anyDict = try? c.decode([String: LossyJSONValue].self, forKey: .data) {
            data = anyDict.mapValues(\.stringValue)
        } else {
            data = nil
        }
    }

    enum CodingKeys: String, CodingKey {
        case url, method, data, childs
    }

    func serializedJSONString() -> String {
        var dict: [String: Any] = ["url": url, "method": method]
        if let data { dict["data"] = data }
        if let childs { dict["childs"] = childs }
        guard JSONSerialization.isValidJSONObject(dict),
              let d = try? JSONSerialization.data(withJSONObject: dict, options: []) else { return "" }
        return String(data: d, encoding: .utf8) ?? ""
    }
}

struct DynamicBillerResponseDTO: Codable {
    let err: Int
    let message: String
    let data: DynamicBillerDTO
}

struct DynamicBillerDTO: Codable {
    let id: String
    let name: String
    let shortName: String
    let description: String
    let logo: String
    let status: Int
    let serviceId: String
    let biller: String
    let fieldList: [DynamicBillerFieldDTO]
    /// JSON string ou objet décodé puis resérialisé pour le mapper domaine.
    let fetchFieldFormRaw: String
    let paymentDetail: [DynamicBillerPaymentDetailDTO]
    let paymentResult: [DynamicBillerPaymentResultDTO]
    let type: String
    let requireQuery: Int

    enum CodingKeys: String, CodingKey {
        case id, name, shortName, description, logo, status, serviceId, biller
        case fieldList, fetchFieldForm, paymentDetail, paymentResult, type, requireQuery
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        shortName = try c.decode(String.self, forKey: .shortName)
        description = try c.decode(String.self, forKey: .description)
        logo = try c.decode(String.self, forKey: .logo)
        status = try c.decode(Int.self, forKey: .status)
        serviceId = try c.decode(String.self, forKey: .serviceId)
        biller = try c.decode(String.self, forKey: .biller)
        fieldList = try c.decode([DynamicBillerFieldDTO].self, forKey: .fieldList)
        paymentDetail = try c.decode([DynamicBillerPaymentDetailDTO].self, forKey: .paymentDetail)
        paymentResult = try c.decode([DynamicBillerPaymentResultDTO].self, forKey: .paymentResult)
        type = try c.decode(String.self, forKey: .type)
        requireQuery = FlexibleIntDecoding.decode(from: c, key: .requireQuery, default: 0)

        if let str = try? c.decode(String.self, forKey: .fetchFieldForm) {
            fetchFieldFormRaw = str
        } else if c.contains(.fetchFieldForm),
                  let obj = try? c.decode(DynamicBillerFetchFieldFormDTO.self, forKey: .fetchFieldForm) {
            fetchFieldFormRaw = obj.serializedJSONString()
        } else {
            fetchFieldFormRaw = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(shortName, forKey: .shortName)
        try c.encode(description, forKey: .description)
        try c.encode(logo, forKey: .logo)
        try c.encode(status, forKey: .status)
        try c.encode(serviceId, forKey: .serviceId)
        try c.encode(biller, forKey: .biller)
        try c.encode(fieldList, forKey: .fieldList)
        try c.encode(fetchFieldFormRaw, forKey: .fetchFieldForm)
        try c.encode(paymentDetail, forKey: .paymentDetail)
        try c.encode(paymentResult, forKey: .paymentResult)
        try c.encode(type, forKey: .type)
        try c.encode(requireQuery, forKey: .requireQuery)
    }
}

struct DynamicBillerFieldDTO: Codable {
    let fieldName: String
    let label: String
    let dataType: String
    let inputType: String
    let minLength: Int?
    let maxLength: Int?
    let isRequired: Bool
    let regex: String
    let value: String
    let viewDisplay: String
    let valueRange: String
    let keyName: String
    let placeholder: String
    let fieldMapping: String
    let parent: String
    let minBy: String
    let mask: String
    let err: Int
    let message: String
    let isMapping: Bool
    let valueMask: String
    let priority: Int
    let children: [String]?

    enum CodingKeys: String, CodingKey {
        case fieldName, label, dataType, inputType, minLength, maxLength, isRequired, regex, value
        case viewDisplay, valueRange, keyName, placeholder, fieldMapping, parent, minBy, mask
        case err, message, isMapping, valueMask, priority, children
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        fieldName = try c.decode(String.self, forKey: .fieldName)
        label = try c.decode(String.self, forKey: .label)
        dataType = try c.decode(String.self, forKey: .dataType)
        inputType = try c.decode(String.self, forKey: .inputType)
        minLength = try c.decodeIfPresent(Int.self, forKey: .minLength)
        maxLength = try c.decodeIfPresent(Int.self, forKey: .maxLength)
        isRequired = try c.decode(Bool.self, forKey: .isRequired)
        regex = try c.decode(String.self, forKey: .regex)
        value = try c.decode(String.self, forKey: .value)
        viewDisplay = try c.decode(String.self, forKey: .viewDisplay)
        valueRange = try c.decode(String.self, forKey: .valueRange)
        keyName = try c.decode(String.self, forKey: .keyName)
        placeholder = try c.decode(String.self, forKey: .placeholder)
        fieldMapping = try c.decode(String.self, forKey: .fieldMapping)
        parent = try c.decode(String.self, forKey: .parent)
        minBy = try c.decode(String.self, forKey: .minBy)
        mask = try c.decode(String.self, forKey: .mask)
        err = try c.decode(Int.self, forKey: .err)
        message = try c.decode(String.self, forKey: .message)
        isMapping = try c.decode(Bool.self, forKey: .isMapping)
        valueMask = try c.decode(String.self, forKey: .valueMask)
        priority = FlexibleIntDecoding.decode(from: c, key: .priority, default: 0)
        children = try c.decodeIfPresent([String].self, forKey: .children)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(fieldName, forKey: .fieldName)
        try c.encode(label, forKey: .label)
        try c.encode(dataType, forKey: .dataType)
        try c.encode(inputType, forKey: .inputType)
        try c.encodeIfPresent(minLength, forKey: .minLength)
        try c.encodeIfPresent(maxLength, forKey: .maxLength)
        try c.encode(isRequired, forKey: .isRequired)
        try c.encode(regex, forKey: .regex)
        try c.encode(value, forKey: .value)
        try c.encode(viewDisplay, forKey: .viewDisplay)
        try c.encode(valueRange, forKey: .valueRange)
        try c.encode(keyName, forKey: .keyName)
        try c.encode(placeholder, forKey: .placeholder)
        try c.encode(fieldMapping, forKey: .fieldMapping)
        try c.encode(parent, forKey: .parent)
        try c.encode(minBy, forKey: .minBy)
        try c.encode(mask, forKey: .mask)
        try c.encode(err, forKey: .err)
        try c.encode(message, forKey: .message)
        try c.encode(isMapping, forKey: .isMapping)
        try c.encode(valueMask, forKey: .valueMask)
        try c.encode(priority, forKey: .priority)
        try c.encodeIfPresent(children, forKey: .children)
    }
}

struct DynamicBillerPaymentDetailDTO: Codable {
    let name: String
    let value: String
    let dataType: String
    let priority: Int
    let inputType: String
    let action: String

    enum CodingKeys: String, CodingKey {
        case name, value, dataType, priority, inputType, action
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        value = try c.decode(String.self, forKey: .value)
        dataType = try c.decode(String.self, forKey: .dataType)
        inputType = try c.decode(String.self, forKey: .inputType)
        priority = FlexibleIntDecoding.decode(from: c, key: .priority, default: 0)
        action = try c.decodeIfPresent(String.self, forKey: .action) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(value, forKey: .value)
        try c.encode(dataType, forKey: .dataType)
        try c.encode(priority, forKey: .priority)
        try c.encode(inputType, forKey: .inputType)
        try c.encode(action, forKey: .action)
    }
}

struct DynamicBillerPaymentResultDTO: Codable {}



struct BillerCategoriesResponseDTO: Codable {
    let err: Int
    let message: String
    let data: [BillerCategoryDTO]
}

struct BillerCategoryDTO: Codable {
    let id: String
    let name: String
    let logo: String
    let icon: String
    let shortName: String
    let billerForms: [BillerFormDTO]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case logo
        case icon
        case shortName = "shortName"
        case billerForms = "billerForms"
    }
}

struct BillerFormDTO: Codable {
    let billerFormId: String
    let name: String
    let shortName: String
    let logo: String
    let type: String
    let form: String

    enum CodingKeys: String, CodingKey {
        case billerFormId = "billerFormId"
        case name
        case shortName = "shortName"
        case logo
        case type
        case form
    }
    
}
