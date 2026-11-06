import Foundation
import Contacts

struct ContactRequest: Codable {
    let ownerId: String = CurrentSessionInfo.shared.currentUid
    let contacts: [ContactInfoReq]

    init(from contacts: [FormattedContact]) {
        self.contacts = contacts.compactMap { contact in
            guard let phone = contact.phoneNumbers.first,
                  !phone.isEmpty
            else {
                return nil
            }

            return ContactInfoReq(
                codeCountry: "-",
                phoneNumber: phone
            )
        }
    }
}

struct ContactInfoReq: Codable {
    let codeCountry: String?
    let phoneNumber: String
}
struct myProfileUpdateReq: Codable {
    let username: String
    let avatar: String?
    let bio: String?
}
