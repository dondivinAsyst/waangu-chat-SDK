import Foundation

struct ContactResponse: Codable {
    let contactId: String
    let userId: String
    let userName: String
    let bio: String?
    let email: String
    let image: String?
    let phone: String
    let typeUser: String?
    let code: String?
    let settings: SettingsUser?
    let isDeleted: Bool?
    let isBlocked: Bool?
    let createdAt: String?
    let updatedAt: String?
//    let version: Int
    let groups:[AnyCodable]?          // use AnyCodable if you want to decode unknown JSON

  
}


struct SettingsUser: Codable {
    let showLastSeen: Bool?                   // show_last_seen
    let showSecurityNotification: Bool?       // show_security_notification
    let themeImage: String?                  // theme_image
    let showProfilePhotoTo: Int?             // show_profile_photo_to
    let showProfileBio: Bool?                // show_profile_bio
    let showMessageReaded: Bool?            // show_message_readed
    let themeColor: String?                  // theme_color
    let whoCanAddMeToGroup: Int?             // who_can_add_me_to_group
    let language: String?

    enum CodingKeys: String, CodingKey {
        case showLastSeen = "show_last_seen"
        case showSecurityNotification = "show_security_notification"
        case themeImage = "theme_image"
        case showProfilePhotoTo = "show_profile_photo_to"
        case showProfileBio = "show_profile_bio"
        case showMessageReaded = "show_message_readed"
        case themeColor = "theme_color"
        case whoCanAddMeToGroup = "who_can_add_me_to_group"
        case language
    }
}

// MARK: - AnyCodable helper for arbitrary JSON values
struct AnyCodable: Codable, Equatable, Hashable {

    
    let value: Any

    init(_ value: Any) { self.value = value }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = Optional<Any>.none as Any
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            var result: [String: Any] = [:]
            for (k, v) in dict { result[k] = v.value }
            self.value = result
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case Optional<Any>.none:
            try container.encodeNil()
        case let v as Bool:
            try container.encode(v)
        case let v as Int:
            try container.encode(v)
        case let v as Double:
            try container.encode(v)
        case let v as String:
            try container.encode(v)
        case let v as [Any]:
            let encodableArray = v.map { AnyCodable($0) }
            try container.encode(encodableArray)
        case let v as [String: Any]:
            let encodableDict = Dictionary(uniqueKeysWithValues: v.map { key, value in (key, AnyCodable(value)) })
            try container.encode(encodableDict)
        default:
            // Attempt to handle numeric types bridged from JSON
            if let number = value as? NSNumber {
                // NSNumber can represent Bool as well; check explicitly
                if CFGetTypeID(number) == CFBooleanGetTypeID() {
                    try container.encode(number.boolValue)
                } else {
                    try container.encode(number.doubleValue)
                }
            } else {
                let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "Unsupported JSON value: \(type(of: value))")
                throw EncodingError.invalidValue(value, context)
            }
        }
    }

    // MARK: - Equatable
    static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        return AnyCodable.areEqual(lhs.value, rhs.value)
    }

    // MARK: - Hashable
    func hash(into hasher: inout Hasher) {
        AnyCodable.hash(value, into: &hasher)
    }

    // MARK: - Helpers for Equatable/Hashable
    private static func areEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        // Handle optionals explicitly by unwrapping
        let l = unwrapOptional(lhs)
        let r = unwrapOptional(rhs)

        switch (l, r) {
        case (let lb as Bool, let rb as Bool):
            return lb == rb
        case (let ln as NSNumber, let rn as NSNumber) where isBooleanNumber(ln) || isBooleanNumber(rn):
            // If either is a boolean NSNumber, compare as Bool
            return ln.boolValue == rn.boolValue
        case (let ln as NSNumber, let rn as NSNumber):
            // Compare numeric values via doubleValue to coerce Int/Double
            return ln.doubleValue == rn.doubleValue
        case (let li as Int, let ri as Int):
            return li == ri
        case (let ld as Double, let rd as Double):
            return ld == rd
        case (let ls as String, let rs as String):
            return ls == rs
        case (let la as [Any], let ra as [Any]):
            guard la.count == ra.count else { return false }
            for (le, re) in zip(la, ra) {
                if !areEqual(le, re) { return false }
            }
            return true
        case (let ld as [String: Any], let rd as [String: Any]):
            guard ld.count == rd.count else { return false }
            for (k, lv) in ld {
                guard let rv = rd[k], areEqual(lv, rv) else { return false }
            }
            return true
        case (_ as NSNull, _ as NSNull):
            return true
        default:
            return false
        }
    }

    private static func hash(_ value: Any, into hasher: inout Hasher) {
        let v = unwrapOptional(value)
        switch v {
        case let b as Bool:
            hasher.combine(0)
            hasher.combine(b)
        case let n as NSNumber where isBooleanNumber(n):
            hasher.combine(0)
            hasher.combine(n.boolValue)
        case let n as NSNumber:
            hasher.combine(1)
            hasher.combine(n.doubleValue)
        case let i as Int:
            hasher.combine(2)
            hasher.combine(i)
        case let d as Double:
            hasher.combine(3)
            hasher.combine(d)
        case let s as String:
            hasher.combine(4)
            hasher.combine(s)
        case let a as [Any]:
            hasher.combine(5)
            for e in a { hash(e, into: &hasher) }
        case let dict as [String: Any]:
            hasher.combine(6)
            // To make hashing order-independent, sort keys
            for key in dict.keys.sorted() {
                hasher.combine(key)
                if let val = dict[key] { hash(val, into: &hasher) }
            }
        case _ as NSNull:
            hasher.combine(7)
        default:
            // Fallback to type name so different unsupported types don't collide entirely
            hasher.combine(String(describing: type(of: v)))
        }
    }

    private static func unwrapOptional(_ any: Any) -> Any {
        let mirror = Mirror(reflecting: any)
        if mirror.displayStyle == .optional {
            if let child = mirror.children.first { return child.value }
            return NSNull()
        }
        return any
    }

    private static func isBooleanNumber(_ number: NSNumber) -> Bool {
        return CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
