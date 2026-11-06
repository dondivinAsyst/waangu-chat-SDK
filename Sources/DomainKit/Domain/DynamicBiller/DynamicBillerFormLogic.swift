//
//  DynamicBillerFormLogic.swift
//  DomainKit — validation / formatage des formulaires biller dynamiques (server-driven).
//

import WaanguCoreKit
import Foundation

public enum DynamicBillerFormLogic {

    /// Valeur initiale selon `valueRange` (fixed / profile / hardware).
    public static func initialValue(
        for field: DynamicBillerField,
        user: UserInfos?,
        deviceId: String?
    ) -> String? {
        switch field.valueRange.lowercased() {
        case "fixed":
            return field.value.isEmpty ? nil : field.value
        case "profile":
            return profileValue(profileKey: field.value, user: user)
        case "hardware":
            if field.value.lowercased() == "deviceid" || field.value.lowercased() == "device_id" {
                return deviceId
            }
            return nil
        default:
            return nil
        }
    }

    private static func profileValue(profileKey: String, user: UserInfos?) -> String? {
        guard let user else { return nil }
        let k = profileKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch k {
        case "phone", "msisdn", "mobile": return user.phone
        case "name", "fullname": return user.name
        case "email": return user.email
        case "code": return user.code
        case "address": return user.address
        case "city": return user.city
        case "gender": return user.gender
        case "qrcode", "qr_code": return user.qrcode
        case "referralcode", "referral_code": return user.referralCode
        default:
            return nil
        }
    }

    public static func formattedDataRequest(
        dataRequest: [String: String],
        fieldList: [DynamicBillerField]
    ) -> [String: String] {
        var out = dataRequest
        for field in fieldList where field.isMapping {
            let parts = field.fieldMapping.split(separator: ".").map(String.init)
            if parts.count > 1, let v = nestedValue(parts: parts, in: out) {
                out[field.fieldName] = v
            } else if parts.count == 1, let v = out[field.fieldMapping] {
                out[field.fieldName] = v
            }
        }
        return out
    }

    private static func nestedValue(parts: [String], in dict: [String: String]) -> String? {
        guard let first = parts.first else { return nil }
        guard let next = dict[first] else { return nil }
        if parts.count == 1 { return next }
        return next
    }

    /// La règle : requis, longueurs, motif. Rend **la raison**, sans texte —
    /// chaque écran la formule dans sa langue.
    public static func issue(
        field: DynamicBillerField,
        formated: [String: String]
    ) -> BillFieldIssue? {
        guard field.isRequired else { return nil }
        let raw = formated[field.fieldName]
        let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty || value.lowercased() == "none" { return .required }
        let len = value.count
        if let minL = field.minLength, len < minL { return .tooShort(min: minL) }
        if let maxL = field.maxLength, len > maxL { return .tooLong(max: maxL) }
        let regex = field.regex.trimmingCharacters(in: .whitespacesAndNewlines)
        if !regex.isEmpty {
            guard let re = try? NSRegularExpression(pattern: regex, options: []) else { return nil }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            if re.firstMatch(in: value, options: [], range: range) == nil { return .invalidFormat }
        }
        return nil
    }

    /// La même règle, formulée comme avant — le Wallet l'affiche telle quelle.
    /// Le message du facturier, s'il en donne un, l'emporte.
    public static func validationError(
        field: DynamicBillerField,
        formated: [String: String]
    ) -> String? {
        guard let issue = issue(field: field, formated: formated) else { return nil }
        if !field.message.isEmpty { return field.message }
        switch issue {
        case .required:              return "Champ requis : \(field.label)"
        case .tooShort(let minL):    return "\(field.label) : minimum \(minL) caractères"
        case .tooLong(let maxL):     return "\(field.label) : maximum \(maxL) caractères"
        case .invalidFormat:         return "Format invalide pour \(field.label)"
        }
    }

    public static func validateBeforeFetch(
        fieldList: [DynamicBillerField],
        childs: [String],
        formated: [String: String]
    ) -> String? {
        let targets = Set(childs)
        for field in fieldList where targets.contains(field.fieldName) {
            if let err = validationError(field: field, formated: formated) { return err }
        }
        return nil
    }

    public static func validateBeforeRequest(
        fieldList: [DynamicBillerField],
        formated: [String: String]
    ) -> String? {
        for field in fieldList {
            if let err = validationError(field: field, formated: formated) { return err }
        }
        return nil
    }

    /// Après un fetch 2C2B réussi : remplit les champs `valueRange == fetch` (hors `$packages`) depuis `fetchPayload`.
    public static func dataRequestMergingFetchPayload(
        biller: DynamicBiller,
        current: [String: String],
        fetchPayload: [String: String]
    ) -> [String: String] {
        var next = current
        for field in biller.fieldList where field.valueRange.lowercased() == "fetch" && field.value != "$packages" {
            let key = field.fieldMapping.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, let val = fetchPayload[key] else { continue }
            next[field.fieldName] = val
        }
        return next
    }
}
