import Foundation
import CryptoKit

public struct ContactHashGenerator {
    
    /// Generate a hash for a contact to detect changes
    /// Hash includes: name + all phone numbers
    public static func generateHash(for contact: FormattedContact) -> String {
        let phoneString = contact.phoneNumbers.sorted().joined(separator: ",")
        let dataString = "\(contact.name)|\(phoneString)"
        
        let data = Data(dataString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Generate hash from CNContact directly
    public static func generateHash(name: String, phones: [String]) -> String {
        let phoneString = phones.sorted().joined(separator: ",")
        let dataString = "\(name)|\(phoneString)"
        
        let data = Data(dataString.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
}
