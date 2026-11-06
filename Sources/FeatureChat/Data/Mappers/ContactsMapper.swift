import Foundation
import Contacts
import WaanguCoreKit

protocol ContactsMappersProtocol {
    func toDomain(from deviceContact: CNContact) -> WaanguContact
    func toGRDB(_ contact: WaanguContact) -> ContactModel
    func toDomain(_ grdb: ContactModel) -> WaanguContact
    func toContactItem(_ model: ContactModel) -> ContactItem
    func toUserContactProps(from contact: WaanguContact) -> UserContactProps
    func toUserContactPropsDevice(from deviceContact: FormattedContact) -> UserContactProps
}

final class ContactsMappers: ContactsMappersProtocol {

    private let fieldEncryptionService: any FieldEncryptionServiceProtocol

    init(fieldEncryptionService: any FieldEncryptionServiceProtocol) {
        self.fieldEncryptionService = fieldEncryptionService
    }

    // MARK: - WaanguContact → ContactModel (new schema)

    func toGRDB(_ contact: WaanguContact) -> ContactModel {
        ContactModel(
            id: contact.id,
            userId: contact.userId,
            phone: contact.phone,
            name: fieldEncryptionService.encrypt(contact.name),
            username: nil,
            avatarURL: contact.image,
            bio: contact.bio.map { fieldEncryptionService.encrypt($0) },
            lastSeenAt: nil,
            isRegistered: contact.isWaanguUser,
            isVerified: false,
            isBlocked: contact.isBlocked,
            isFavorite: false,
            isSavedContact: false,
            showLastSeen: true,
            showProfilePhoto: true,
            showStatus: true
        )
    }

    // MARK: - ContactModel (new schema) → WaanguContact

    func toDomain(_ grdb: ContactModel) -> WaanguContact {
        let livePresence = UserPresenceStore.shared.presence(for: grdb.userId)
        let status: UserStatus
        let lastSeen: String

        if let livePresence {
            status = UserStatus(rawValue: livePresence.status.rawValue) ?? .offline
            lastSeen = livePresence.lastSeen ?? ""
        } else {
            status = .offline
            lastSeen = grdb.lastSeenAt.map {
                ISO8601DateFormatter().string(from: $0)
            } ?? ""
        }

        return WaanguContact(
            id: grdb.id,
            userId: grdb.userId,
            contactName: "",          // contactName removed from model; default to empty
            isWaanguUser: grdb.isRegistered,
            isTitle: false,
            onlineStatus: UserOnline(
                status: status,
                lastSeen: lastSeen,
                userId: grdb.userId
            ),
            image: grdb.avatarURL,
            bio: grdb.bio.map { fieldEncryptionService.decrypt($0) },
            name: fieldEncryptionService.decrypt(grdb.name),
            phone: grdb.phone,
            isBlocked: grdb.isBlocked
        )
    }

    // MARK: - ContactModel → ContactItem

    func toContactItem(_ model: ContactModel) -> ContactItem {
        ContactItem(
            idContact: model.id,
            userId: model.userId,
            phone: model.phone,
            name: fieldEncryptionService.decryptOptional(model.name),
            avatar: model.avatarURL,
            isRegistered: model.isRegistered
        )
    }

    // MARK: - CNContact → WaanguContact

    func toDomain(from deviceContact: CNContact) -> WaanguContact {
        let phone = deviceContact.phoneNumbers
            .first?.value.stringValue
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .joined() ?? "Unknown"
        return WaanguContact(
            id: deviceContact.identifier,
            userId: "",
            contactName: "",
            isWaanguUser: false,
            isTitle: false,
            onlineStatus: UserOnline(status: .offline, lastSeen: "", userId: deviceContact.identifier),
            image: nil,
            bio: nil,
            name: deviceContact.givenName,
            phone: phone,
            isBlocked: false
        )
    }

    // MARK: - WaanguContact → UserContactProps

    func toUserContactProps(from contact: WaanguContact) -> UserContactProps {
        UserContactProps(
            idContact: contact.id,
            userId: contact.userId,
            name: !contact.name.isEmpty ? contact.name : contact.phone,
            avatar: contact.image,
            phone: contact.phone,
            description: contact.bio ?? "",
            isBlocked: contact.isBlocked
        )
    }

    // MARK: - FormattedContact → UserContactProps

    func toUserContactPropsDevice(from deviceContact: FormattedContact) -> UserContactProps {
        UserContactProps(
            idContact: deviceContact.id,
            userId: "",
            name: deviceContact.name,
            avatar: deviceContact.imageData?.description,
            phone: deviceContact.phoneNumbers.first ?? "",
            description: "",
            isBlocked: false
        )
    }
}
