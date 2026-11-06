import Contacts
import Foundation

enum DeviceContactWriter {

    /// Writes a contact to the device address book.
    ///
    /// With `replacingExistingNumber` the number is looked up first and the
    /// matching contact is renamed in place — an edit that added a second
    /// address book entry for the same person would leave the user with a
    /// duplicate and no visible change once contacts re-sync.
    static func saveContact(
        givenName: String,
        familyName: String,
        nationalNumber: String,
        countryDialCode: String,
        replacingExistingNumber: Bool = false
    ) async throws {
        let granted = await requestAccessIfNeeded()
        guard granted else {
            throw NSError(domain: "DeviceContactWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Contacts access denied"])
        }

        let digits = nationalNumber.filter { $0.isNumber }
        let dialDigits = countryDialCode.filter { $0.isNumber }
        let full = "+\(dialDigits)\(digits)"

        let store = CNContactStore()
        let request = CNSaveRequest()

        if replacingExistingNumber,
           let existing = try findContact(matching: full, in: store),
           let mutable = existing.mutableCopy() as? CNMutableContact {
            mutable.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            mutable.familyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            mutable.phoneNumbers = [
                CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: full))
            ]
            request.update(mutable)
        } else {
            let contact = CNMutableContact()
            contact.givenName = givenName.trimmingCharacters(in: .whitespacesAndNewlines)
            contact.familyName = familyName.trimmingCharacters(in: .whitespacesAndNewlines)
            let phone = CNPhoneNumber(stringValue: full)
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: phone)]
            request.add(contact, toContainerWithIdentifier: nil)
        }

        try store.execute(request)
    }

    /// Finds the device contact holding this number, comparing on digits so
    /// formatting differences ("+257 68 22 51 92" vs "+25768225192") still match.
    private static func findContact(
        matching phoneNumber: String,
        in store: CNContactStore
    ) throws -> CNContact? {
        let wanted = phoneNumber.filter(\.isNumber)
        guard !wanted.isEmpty else { return nil }

        let keys: [CNKeyDescriptor] = [
            CNContactGivenNameKey as CNKeyDescriptor,
            CNContactFamilyNameKey as CNKeyDescriptor,
            CNContactPhoneNumbersKey as CNKeyDescriptor
        ]

        var match: CNContact?
        let fetch = CNContactFetchRequest(keysToFetch: keys)
        try store.enumerateContacts(with: fetch) { contact, stop in
            let hit = contact.phoneNumbers.contains {
                $0.value.stringValue.filter(\.isNumber) == wanted
            }
            if hit {
                match = contact
                stop.pointee = true
            }
        }
        return match
    }

    /// Appends a number to a contact the user already has on the device.
    ///
    /// Backs the "Add to existing contact" row: the picker hands back the chosen
    /// contact, this attaches the number to it.
    static func addPhoneNumber(_ phoneNumber: String, to contact: CNContact) async throws {
        let granted = await requestAccessIfNeeded()
        guard granted else {
            throw NSError(
                domain: "DeviceContactWriter",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Contacts access denied"]
            )
        }

        let trimmed = phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NSError(
                domain: "DeviceContactWriter",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "No phone number to add"]
            )
        }

        // Already on the contact — treat as a no-op rather than creating a duplicate row.
        let existingDigits = contact.phoneNumbers.map { $0.value.stringValue.filter(\.isNumber) }
        guard !existingDigits.contains(trimmed.filter(\.isNumber)) else { return }

        guard let mutable = contact.mutableCopy() as? CNMutableContact else {
            throw NSError(
                domain: "DeviceContactWriter",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Contact could not be edited"]
            )
        }

        mutable.phoneNumbers.append(
            CNLabeledValue(
                label: CNLabelPhoneNumberMobile,
                value: CNPhoneNumber(stringValue: trimmed)
            )
        )

        let request = CNSaveRequest()
        request.update(mutable)
        try CNContactStore().execute(request)
    }

    private static func requestAccessIfNeeded() async -> Bool {
        let store = CNContactStore()
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                store.requestAccess(for: .contacts) { ok, _ in
                    cont.resume(returning: ok)
                }
            }
        default:
            return false
        }
    }
}
