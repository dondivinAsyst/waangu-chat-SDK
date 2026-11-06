import Foundation

public struct PhoneNumberNormalizer {
    
    /// Normalize phone number to E.164 format
    /// E.164: +[country code][subscriber number]
    /// Example: +243998741203
    public static func normalizeToE164(_ phoneNumber: String, defaultCountryCode: String = "243") -> String {
        // Remove all non-digit characters except +
        var cleaned = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        // If already starts with +, validate and return
        if cleaned.hasPrefix("+") {
            return cleaned
        }
        
        // If starts with 00, replace with +
        if cleaned.hasPrefix("00") {
            cleaned = "+" + cleaned.dropFirst(2)
            return cleaned
        }
        
        // If starts with 0, remove it (local format)
        if cleaned.hasPrefix("0") {
            cleaned = String(cleaned.dropFirst())
        }
        
        // If doesn't start with country code, add default
        if !cleaned.hasPrefix(defaultCountryCode) {
            cleaned = defaultCountryCode + cleaned
        }
        
        // Add + prefix
        if !cleaned.hasPrefix("+") {
            cleaned = "+" + cleaned
        }
        
        return cleaned
    }
    
    /// Normalize multiple phone numbers
    public static func normalizePhones(_ phones: [String], defaultCountryCode: String = "243") -> [String] {
        return phones.map { normalizeToE164($0, defaultCountryCode: defaultCountryCode) }
    }
    
    /// Extract country code from E.164 number
    public static func extractCountryCode(from e164Number: String) -> String? {
        guard e164Number.hasPrefix("+") else { return nil }
        
        // Common country codes (1-3 digits)
        let cleaned = String(e164Number.dropFirst()) // Remove +
        
        // Try 3-digit codes first
        if cleaned.count >= 3 {
            let threeDigit = String(cleaned.prefix(3))
            if ["243", "254", "255", "256"].contains(threeDigit) { // DRC, Kenya, Tanzania, Uganda
                return threeDigit
            }
        }
        
        // Try 2-digit codes
        if cleaned.count >= 2 {
            let twoDigit = String(cleaned.prefix(2))
            if ["27", "20", "44", "33", "49"].contains(twoDigit) { // SA, Egypt, UK, France, Germany
                return twoDigit
            }
        }
        
        // Try 1-digit codes
        if cleaned.count >= 1 {
            let oneDigit = String(cleaned.prefix(1))
            if ["1", "7"].contains(oneDigit) { // US/Canada, Russia
                return oneDigit
            }
        }
        
        return nil
    }
}
