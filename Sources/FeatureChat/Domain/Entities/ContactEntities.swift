import Foundation
import Contacts

public struct WaanguContact: Identifiable {
    public var id: String
    var userId:String
    let contactName: String
    let isWaanguUser: Bool
    let isTitle: Bool?          // optional
    var onlineStatus: UserOnline
    let image:String?
    let bio:String?
    let name:String
    let phone : String
    let isBlocked : Bool
    public init(id: String,userId:String, contactName: String, isWaanguUser: Bool, isTitle: Bool? = nil, onlineStatus: UserOnline, image: String?, bio: String?, name: String, phone: String, isBlocked: Bool) {
        self.id = id
        self.userId = userId
        self.contactName = contactName
        self.isWaanguUser = isWaanguUser
        self.isTitle = isTitle
        self.onlineStatus = onlineStatus
        self.image = image
        self.bio = bio
        self.name = name
        self.phone = phone
        self.isBlocked = isBlocked
    }
}

public enum UserStatus: String, Codable {
    case online = "ONLINE"
    case offline = "OFFLINE"
    case busy = "BUSY"
}

public struct UserOnline: Codable {
    let status: UserStatus
    let lastSeen: String
    let userId: String
}

// MARK: - User Contact Props (UI Model)

public struct UserContactProps: Identifiable,Equatable {
    public var id: String { idContact ?? UUID().uuidString }
    public var userId: String
    public var idContact: String?
    public var name: String
    public var avatar: String?
    public var phone: String
    public var description: String
    public var isBlocked: Bool
    
    public init(idContact: String?,userId:String, name: String, avatar: String?, phone: String, description: String,isBlocked:Bool) {
        self.idContact = idContact
        self.userId = userId
        self.name = name
        self.avatar = avatar
        self.phone = phone
        self.description = description
        self.isBlocked = isBlocked
    }
}

// MARK: - Formatted Contact (Device Contact)

public struct FormattedContact: Identifiable {
    public let id: String
    public let name: String
    public let phoneNumbers: [String]          // Raw phone numbers
    public let normalizedPhones: [String]      // E.164 normalized phones
    public let imageData: Data?
    
    public init(id: String, name: String, phoneNumbers: [String], imageData: Data?) {
        self.id = id
        self.name = name
        self.phoneNumbers = phoneNumbers
        self.normalizedPhones = PhoneNumberNormalizer.normalizePhones(phoneNumbers)
        self.imageData = imageData
    }
    
    public init(from cnContact: CNContact) {
        self.id = cnContact.identifier
        self.name = "\(cnContact.givenName) \(cnContact.familyName)".trimmingCharacters(in: .whitespaces)
        let rawPhones = cnContact.phoneNumbers.map { $0.value.stringValue.normalizedPhoneNumber() }
        self.phoneNumbers = rawPhones
        self.normalizedPhones = PhoneNumberNormalizer.normalizePhones(rawPhones)
        self.imageData = cnContact.imageDataAvailable ? cnContact.imageData : nil
    }
}

extension String {
    
    func normalizedPhoneNumber() -> String {
        
        let allowedCharacters = CharacterSet(charactersIn: "+0123456789")
        
        return self.unicodeScalars
            .filter { allowedCharacters.contains($0) }
            .map(String.init)
            .joined()
    }
}
