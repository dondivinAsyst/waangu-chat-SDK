import Foundation
import Contacts
import Combine
import WaanguCoreKit

class ContactsRepository: ContactsRepositoryProtocol, ObservableObject {

    @Published private(set) var ContactsUpdated: WaanguContact?
    let BATCH_SIZE = 100
    let DELAY_BETWEEN_BATCHES = 1000

    private let localDataSource: LocalContactsDataSourceProtocol
    private let httpDataSource: HTTPContactsDataSourceProtocol
    private let mapper: ContactsMappersProtocol
    private let ContactManager: ContactsManagerProtocol
    private let syncStateDataSource: LocalContactSyncStateDataSourceProtocol
    private let retryPolicy = RetryPolicy(maxAttempts: 3, baseDelay: 1.0, maxDelay: 10.0)

    init(
        localDataSource: LocalContactsDataSourceProtocol,
        httpDataSource: HTTPContactsDataSourceProtocol,
        mapper: ContactsMappersProtocol,
        ContactManager: ContactsManagerProtocol,
        syncStateDataSource: LocalContactSyncStateDataSourceProtocol
    ) {
        self.localDataSource = localDataSource
        self.httpDataSource = httpDataSource
        self.mapper = mapper
        self.ContactManager = ContactManager
        self.syncStateDataSource = syncStateDataSource
//        let contacts: [WaanguContact] = [
//            WaanguContact(
//                       id: "686fc3495948e8846cde8e18",
//                       contactName: "DON KAVUMU",
//                       isWaanguUser: true,
//                       isTitle: nil,
//                       onlineStatus: UserOnline(
//                           status: .offline,
//                           lastSeen: "2026-01-09T09:15:00Z",
//                           userId: "686fc3495948e8846cde8e18"
//                       ),
//                       image: "https://randomuser.me/api/portraits/men/1.jpg",
//                       bio: "Hey there! I am using Waangu Chat",
//                       name: "DON KAVUMU",
//                       phone: "097777885"
//                   ),
//
//            WaanguContact(
//                       id:"691586a017cd1eef5dae219d",
//                       contactName: "PAUL LAURENT",
//                       isWaanguUser: true,
//                       isTitle: false,
//                       onlineStatus: UserOnline(
//                           status: .offline,
//                           lastSeen: "2026-01-08T22:40:00Z",
//                           userId: "691586a017cd1eef5dae219d"
//                       ),
//                       image: "https://randomuser.me/api/portraits/men/2.jpg",
//                       bio: "Hey there! I am using Waangu Chat",
//                       name: "PAUL LAURENT",
//                       phone: "098741203"
//                   ),
//
//            WaanguContact(
//                       id:"6901db47428244ce01b15167",
//                       contactName: "DANI ESCROC",
//                       isWaanguUser: true,
//                       isTitle: true,
//                       onlineStatus: UserOnline(
//                           status: .online,
//                           lastSeen: "2026-01-09T10:02:00Z",
//                           userId: "6901db47428244ce01b15167"
//                       ),
//                       image: "https://randomuser.me/api/portraits/men/4.jpg",
//                       bio: "Hey there! I am using Waangu Chat",
//                       name: "DANI ESCROC",
//                       phone: "098741202"
//                   ),
//
//          
//               ]
//        for contact in contacts {
//            try! localDataSource.saveContact(contact)
//               }
//               print("finished inserting")
    }

    // MARK: - Public API

    func fetchContacts() async throws -> (waanguContacts: [WaanguContact], UserContactProps: [UserContactProps]) {
        let fetchedContacts = try await localDataSource.fetchContacts()
        let userContactProps = fetchedContacts.map { mapper.toUserContactProps(from: $0) }
        return (fetchedContacts, userContactProps)
    }

    func fetchDevicesContacts() async throws -> [UserContactProps] {
      
        let cnContacts = await ContactManager.getContacts()
        return cnContacts.map { mapper.toUserContactPropsDevice(from: $0) }
    }

    func fetchAndUpdateContacts() async throws -> (waanguContacts: [WaanguContact], UserContactProps: [UserContactProps]) {
        let newContacts = await sendContactsInBatches(contacts: ContactManager.getContacts())
        
        // Convert server response to WaanguContact entities
        let serverContacts = newContacts.fetchedContacts.map { contact in
            WaanguContact(
                id: contact.contactId,
                userId: contact.userId,
                contactName: contact.userName,
                isWaanguUser: true,
                isTitle: false,
                onlineStatus: UserOnline(status: .offline, lastSeen: "Never", userId: contact.userId),
                image: nil,
                bio: contact.bio ?? "Hey there! I am using Waangu Chat",
                name: contact.userName,
                phone: contact.phone,
                isBlocked: contact.isBlocked ?? false
            )
        }
      
        // Replace all local contacts with server response (server is source of truth)
        try await localDataSource.replaceAllContacts(serverContacts)

        return try await fetchContacts()
    }
    
    // MARK: - Incremental Sync (WhatsApp-like)
    
    func fetchAndUpdateContactsIncremental() async throws -> (waanguContacts: [WaanguContact], UserContactProps: [UserContactProps]) {
        
        // 1. Get current device contacts
        let currentContacts = await ContactManager.getContacts()
        
        // 2. Get last sync state
        let lastSyncState = try await syncStateDataSource.fetchAllSyncStates()
        
        // 3. Detect changes
        let changes = ContactChangeDetector.detectChanges(
            currentContacts: currentContacts,
            lastSyncState: lastSyncState
        )
        
        debugLog("📊 Contact Changes Detected:")
        debugLog("📊   Added: \(changes.added.count)")
        debugLog("📊   Updated: \(changes.updated.count)")
        debugLog("📊   Deleted: \(changes.deleted.count)")
        debugLog("📊   Unchanged: \(changes.unchanged.count)")
        
        // 4. If no changes, return cached contacts
        if !changes.hasChanges {
            
            let contacts = try await fetchContacts()
            debugLog("✅ No contact changes detected, using cache  \(contacts)")
            return contacts
        }
        
        // 5. Prepare contacts to sync (added + updated)
        let contactsToSync = changes.added + changes.updated
        
        // 6. Sync with retry
        return try await retryPolicy.execute {
            // Send changed contacts to server
            let serverResponse = await self.sendContactsInBatches(contacts: contactsToSync)
            
            // Convert server response to WaanguContact entities
            let serverContacts = serverResponse.fetchedContacts.map { contact in
                WaanguContact(
                    id: contact.contactId,
                    userId: contact.userId,
                    contactName: contact.userName,
                    isWaanguUser: true,
                    isTitle: false,
                    onlineStatus: UserOnline(status: .offline, lastSeen: "Never", userId: contact.userId),
                    image: nil,
                    bio: contact.bio ?? "Hey there! I am using Waangu Chat",
                    name: contact.userName,
                    phone: contact.phone,
                    isBlocked: contact.isBlocked ?? false
                )
            }
            
            // 7. ✅ Use incremental update instead of replaceAll
            try await self.localDataSource.updateContactsIncremental(
                toAddOrUpdate: serverContacts,
                toDeleteIds: changes.deleted
            )
            
            // 8. Persist sync state ONLY for contacts that were successfully synced.
            // Failed contacts stay dirty so the next refresh will retry them.
            if !serverResponse.successfulContacts.isEmpty {
                let newSyncStates = serverResponse.successfulContacts.map { contact in
                    ContactSyncState(
                        contactId: contact.id,
                        rawPhone: contact.phoneNumbers.first ?? "",
                        normalizedPhone: contact.normalizedPhones.first ?? "",
                        contactHash: ContactHashGenerator.generateHash(for: contact),
                        lastSyncedAt: Date()
                    )
                }
                try await self.syncStateDataSource.saveSyncStates(newSyncStates)
            }
            
            if !changes.deleted.isEmpty {
                try await self.syncStateDataSource.deleteSyncStates(contactIds: changes.deleted)
            }
            
            if serverResponse.failed > 0 {
                throw NSError(
                    domain: "ContactsSync",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            String(format: ChatErrorStrings.contactSyncFailed, serverResponse.failed)
                    ]
                )
            }
            
            debugLog("✅ Incremental sync completed successfully")
            
            return try await self.fetchContacts()
        }
    }

    func isContactPersisted(phone: String) async throws -> Bool {
        try await localDataSource.isContactPersisted(phone: phone)
    }

    func deleteAllNumbers() async throws {
        try await localDataSource.deleteAllContacts()
    }
    
    // MARK: - Block/Unblock Contact
    
    func toggleBlockContact(contactId: String, blocked: Bool) async throws -> Bool {
        let request = BlockContactRequest(contactId: contactId, blocked: blocked)
        let endpoint = ContactsEndpoints.blockOrUnblockContact(request)
        
        let response: BlockContactResponse = try await httpDataSource.blockOrUnblockContact(endpoint: endpoint)
        
        // Treat 200...299 as success. Prefer `status` if available; otherwise try `code`. Adjust if your model differs.
        let statusCode: Int = response.status
            ?? -1

        if (200...299).contains(statusCode) {
            // Update local GRDB store
            try await updateContactBlockStatus(contactId: contactId, isBlocked: blocked)
   
            return blocked
        } else {
            let message: String = (response as AnyObject).value(forKey: "message") as? String ?? ChatErrorStrings.blockStatusFailed

            throw NSError(domain: "ContactBlocking", code: statusCode == -1 ? 400 : statusCode, userInfo: [
                NSLocalizedDescriptionKey: message
            ])
        }
    }
    
    func updateContactBlockStatus(contactId: String, isBlocked: Bool) async throws {
        try await localDataSource.updateContactBlockStatus(contactId: contactId, isBlocked: isBlocked)
    }

    // MARK: - Private helpers

    private func sendContactsInBatches(
        contacts: [FormattedContact]
    ) async -> (
        fetchedContacts: [ContactResponse],
        total: Int,
        successful: Int,
        failed: Int,
        successfulContacts: [FormattedContact],
        failedContacts: [FormattedContact]
    ) {
        let totalContacts = contacts.count
        var successfulContacts: [FormattedContact] = []
        var failedContacts: [FormattedContact] = []
        var fetchedContacts: [ContactResponse] = []
        var index = 0

        while index < totalContacts {
            let endIndex = min(index + BATCH_SIZE, totalContacts)
            let batch = Array(contacts[index..<endIndex])

            do {
                let contactReq = ContactRequest(from: batch)
                let response = try await httpDataSource.getContacts(contactReq)
               
                if response.status == 200 {
                    successfulContacts.append(contentsOf: batch)
                    let contactsRes: [ContactResponse] = response.data ?? []
                   
                    fetchedContacts.append(contentsOf: contactsRes)
                } else {
                    failedContacts.append(contentsOf: batch)
                }
            } catch {
                failedContacts.append(contentsOf: batch)
                // Remaining batches were not attempted — keep them dirty as well.
                if endIndex < totalContacts {
                    failedContacts.append(contentsOf: contacts[endIndex..<totalContacts])
                }
                debugLog("this contacts that was fetched failed \(error)")
                break
            }

            if endIndex < totalContacts {
                try? await Task.sleep(nanoseconds: UInt64(DELAY_BETWEEN_BATCHES))
            }

            index += BATCH_SIZE
        }
       
        return (
            fetchedContacts,
            totalContacts,
            successfulContacts.count,
            failedContacts.count,
            successfulContacts,
            failedContacts
        )
    }
}

