import Foundation
import Contacts
import Combine
import WaanguSharedUI
import WaanguCoreKit

enum ChannelCreationRoute {
    case groupPartnerPicker
    case setUpGroupChat
}

enum ChannelContants {
    static let maxGroupChatMembers = 12
}

enum ChannelCreationError: Error {
    case noChatPartnersSelected
    case failedToCreateUniqueChannelId
}

struct UserContact: Identifiable {
   let id: String?
   let name: String
   let avatar: String?
   let phone: String
   let description: String
}

extension String {
    var onlyDigits: String {
        return self.filter { $0.isWholeNumber }
    }
}



@MainActor
public final class ChatPartnerPickerViewModel: ObservableObject {
    
    
    @Published var navStack = [ChannelCreationRoute]()
    @Published var selectedChatPartners = [UserContactProps]()
    @Published private(set) var users = [UserContactProps]()
    @Published var waanguUsers : [UserContactProps] = []
    @Published var waanguUsersSearch : [UserContactProps] = []
    //CONTACTS
    @Published var deviceContacts: [UserContactProps] = []
    @Published var deviceContactsSearch: [UserContactProps] = []
    @Published var permissionDenied = false
    
    private var subscription: AnyCancellable?
    private var contactsRefreshSubscription: AnyCancellable?
    private let store = CNContactStore()
    private var lastCursor: String?
    private var currentUser: UserItem?
    private var contactUseCases: ContactsUseCasesProtocol
    
    var showSelectedUsers: Bool {
        return !selectedChatPartners.isEmpty
    }
    
    var disableNextButton: Bool {
        return selectedChatPartners.isEmpty
    }
    
    var isPaginatable: Bool {
        return !users.isEmpty
    }
    
    var isDirectChannel: Bool {
        return selectedChatPartners.count == 1
    }
    
    init(
        contactUseCases: ContactsUseCasesProtocol,
    ) {
        self.contactUseCases = contactUseCases

        Task { @MainActor [weak self] in
            await self?.loadLocalContacts()
            debugLog("finished loading local contacts")
        }
        
        observeBlockStatusChanges()
        observeContactsShouldRefresh()
    }

    deinit {
        subscription?.cancel()
        contactsRefreshSubscription?.cancel()
    }

    // MARK: - Observe Contact Edits

    /// Editing or creating a contact writes to the device address book; this
    /// pulls that change back through sync so the new name reaches the lists
    /// without the user having to relaunch.
    private func observeContactsShouldRefresh() {
        contactsRefreshSubscription = NotificationCenter.default
            .publisher(for: .contactsShouldRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.forceSyncContactsFromServer()
                    await self?.loadLocalContacts()
                }
            }
    }
    
    // MARK: - Observe Block Status Changes
    
    private func observeBlockStatusChanges() {
        subscription = NotificationCenter.default.publisher(for: .contactBlockStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let userInfo = notification.userInfo,
                      let contactId = userInfo["contactId"] as? String,
                      let isBlocked = userInfo["isBlocked"] as? Bool else { return }
                self.updateContactBlockStatus(contactId: contactId, isBlocked: isBlocked)
            }
    }
    
    // MARK: - Update Contact Block Status
    
    func updateContactBlockStatus(contactId: String, isBlocked: Bool) {
        // Update in waanguUsers
        if let index = waanguUsers.firstIndex(where: { $0.idContact == contactId }) {
            waanguUsers[index].isBlocked = isBlocked
            debugLog("✅ Updated block status for contact \(contactId) to \(isBlocked) in waanguUsers")
        }
        
        // Update in waanguUsersSearch
        if let index = waanguUsersSearch.firstIndex(where: { $0.idContact == contactId }) {
            waanguUsersSearch[index].isBlocked = isBlocked
        }
        
        // Also update in deviceContacts if present
        if let index = deviceContacts.firstIndex(where: { $0.idContact == contactId }) {
            deviceContacts[index].isBlocked = isBlocked
        }
        
        // Update in deviceContactsSearch
        if let index = deviceContactsSearch.firstIndex(where: { $0.idContact == contactId }) {
            deviceContactsSearch[index].isBlocked = isBlocked
        }
    }
    
    func searchContacts(_ searchText:String){
        debugLog("searching...  \(searchText)")
        if searchText.isEmpty{
            self.deviceContacts = self.deviceContactsSearch
            self.waanguUsers = self.waanguUsersSearch
            return
        }
        
        
      
        self.deviceContacts = self.deviceContactsSearch.filter {
              $0.name.localizedCaseInsensitiveContains(searchText) ||
              $0.phone.contains(searchText)
          }
        self.waanguUsers = self.waanguUsersSearch.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.contains(searchText)
        }
    }
    
    // MARK: - Load Local Contacts (No Server Call)
    
    func loadLocalContacts() async {
        do {
            let contacts = try await contactUseCases.getPersistedContacts.execute()?.UserContactProps
            let device = try await contactUseCases.getDeviceContacts.execute()
            guard let contacts else { return }
            guard let device else { return }
            self.updateWaanguUsers(waanguUsers: contacts, devicesContacts: device)
          
        } catch {
            debugLog("🔥🔥 ❌Failed to load local contacts: \(error)")
        }
    }
    
    //MARK: - force to fetch contacts $
    
    func forceSyncContactsFromServer()async{
        do {
            let res = try await contactUseCases.getUpdatedContacts.execute()
        }catch{
            debugLog("Error occur while fetching contacts :  \(error.localizedDescription)")
        }
    }
    
    // MARK: - Refresh Contacts from Server
    
    func refreshContactsFromServer() async {
        do {
            // ✅ Use incremental sync with proper incremental update method
            // Now safe because we're using updateContactsIncremental() instead of replaceAllContacts()
            let result = try await contactUseCases.getUpdatedContactsIncremental.execute()
            
            guard let contacts = result?.UserContactProps else { return }
            
            let deviceContacts = try await contactUseCases.getDeviceContacts.execute()
            guard let deviceContacts = deviceContacts else { return }
            
            debugLog("🔄 Incremental sync completed - Waangu contacts: \(contacts), Device contacts: \(deviceContacts.count)")
            
            self.updateWaanguUsers(waanguUsers: contacts, devicesContacts: deviceContacts)
            
        } catch {
            // Map CNContactStore authorization errors to UI state when possible
            if let cnError = error as? CNError, cnError.code == .authorizationDenied {
                self.permissionDenied = true
            } else {
                debugLog("❌ Failed to refresh contacts: \(error)")
            }
        }
    }
    
    func getPersitedContacts() async {
        await loadLocalContacts()
    }
    
    func getContacts() async {
        await refreshContactsFromServer()
    }
    
    func updateWaanguUsers(
        waanguUsers: [UserContactProps],
        devicesContacts: [UserContactProps]
    ) {
      
        self.waanguUsers = waanguUsers
        self.waanguUsersSearch = waanguUsers

        let waanguPhoneNumbers = Set(
            waanguUsers
                .map { $0.phone.onlyDigits }
                .filter { !$0.isEmpty }
        )

        let deviceNum = devicesContacts.filter {
            let phone = $0.phone.onlyDigits
            guard !phone.isEmpty else {
                return true // keep contacts without valid phone numbers
            }
            return !waanguPhoneNumbers.contains(phone)
        }
        self.deviceContacts = deviceNum
        self.deviceContactsSearch = deviceNum
        
    }


    
    private func listenForAuthState() {
//        subscription = AuthManager.shared.authState.receive(on: DispatchQueue.main).sink { [weak self] authState in
//            switch authState {
//            case .authenticated(let currentUser):
//                self?.currentUser = currentUser
//                Task {
//                    await self?.fetchUsers()
//                }
//            default:
//                break
//            }
//        }
    }
    
    // MARK: - Public Methods
    
    // MARK: - Navigation Management
    
    /// Clears the navigation stack and resets selection state
    func resetNavigationState() {
        navStack.removeAll()
        selectedChatPartners.removeAll()
    }
    
    /// Clears navigation stack only (keeps selections)
    func clearNavigationStack() {
        navStack.removeAll()
    }
    
    func fetchUsers() async {
//        do {
//            let userNode = try await UserService.paginateUsers(lastCursor: lastCursor, pageSize: 5)
//            var fetchedUsers = userNode.users
//            guard let currentUid = Auth.auth().currentUser?.uid else { return }
//            fetchedUsers = fetchedUsers.filter { $0.uid != currentUid }
//
//            self.users.append(contentsOf: fetchedUsers)
//            self.lastCursor = userNode.currentCursor
//        } catch {
//            print("Failed to fetch users. \(error.localizedDescription)")
//        }
    }
    
    func deSelectAllChatPartners() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.selectedChatPartners.removeAll()
        }
    }
    
    func handleItemSelection(_ item: UserContactProps) {
        if isUserSelected(item) {
            guard let index = selectedChatPartners.firstIndex(where: { $0.id == item.id }) else { return }
            selectedChatPartners.remove(at: index)
        } else {
            guard selectedChatPartners.count < ChannelContants.maxGroupChatMembers else {
                showError("You can't add more than \(ChannelContants.maxGroupChatMembers) members.")
                return
            }
            selectedChatPartners.append(item)
        }
    }
    
    func isUserSelected(_ user: UserContactProps) -> Bool {
        return selectedChatPartners.contains { $0.id == user.id }
    }
    
    func createDirectChannel(_ chatPartner: UserContactProps, completion: @escaping (_ newChannel: ChannelItem) -> Void) {
//        if selectedChatPartners.isEmpty {
//            selectedChatPartners.append(chatPartner)
//        }
//
//        Task {
//            if let channelId = await verifyIfDirectChannelExists(with: chatPartner.uid) {
//                let snapshot = try await FirebaseConstants.ChannelsRef.child(channelId).getData()
//                let channelDict = snapshot.value as! [String: Any]
//                var directChannel = ChannelItem(channelDict)
//                directChannel.members = selectedChatPartners
//                if let currentUser {
//                    directChannel.members.append(currentUser)
//                }
//                completion(directChannel)
//            } else {
//                let channelCreation = createChannel(nil)
//                switch channelCreation {
//                case .success(let channel):
//                    completion(channel)
//                case .failure (let failure):
//                    showError("Failed to create a Direct Channel: \(failure.localizedDescription)")
//                    print("Failed to create a Direct Channel: \(failure.localizedDescription)")
//                }
//            }
//        }
    }

    
    func createGroupChannel(_ groupName: String?, completion: @escaping (_ newChannel: ChannelItem) -> Void) {
//        let channelCreation = createChannel(groupName)
//        switch channelCreation {
//        case .success(let channel):
//            completion(channel)
//        case .failure(let failure):
//            showError("Failed to create a Group Channel: \(failure.localizedDescription)")
//            print("Failed to create a Group Channel: \(failure.localizedDescription)")
//        }
    }
    
    typealias ChannelId = String
    private func verifyIfDirectChannelExists(with chatPartnerId: String) async -> ChannelId? {
//        guard let currentUid = Auth.auth().currentUser?.uid,
//              let snapshot = try? await FirebaseConstants.UserDirectChannels.child(currentUid).child(chatPartnerId).getData(), snapshot.exists()
//
//        else { return nil }
//
//        let directMessageDict = snapshot.value as! [String: Bool]
//        let channelId = directMessageDict.compactMap({ $0.key }).first
        return "channelId"
    }
    
    private func showError(_ errorMessage: String) {
    
    }
    
    private func createChannel(_ channelName: String?) -> Result<ChannelItem, Error> {
//        guard !selectedChatPartners.isEmpty else {
//            return .failure(ChannelCreationError.noChatPartnersSelected)
//        }
//
//        guard
//            let channelId = FirebaseConstants.ChannelsRef.childByAutoId().key,
//            let currentUid = Auth.auth().currentUser?.uid,
//            let messageId = FirebaseConstants.MessagesRef.childByAutoId().key
//        else {
//            return .failure(ChannelCreationError.failedToCreateUniqueChannelId)
//        }
//
//        let timestamp = Date().timeIntervalSince1970
//        var membersUids = selectedChatPartners.compactMap{ $0.uid }
//        membersUids.append(currentUid)
//
//        let newChannelBroadcast = AdminMessageType.channelCreation.rawValue
//
//        var channelDict: [String: Any] = [
//            .id: channelId,
//            .lastMessage: newChannelBroadcast,
//            .lastMessageType: newChannelBroadcast,
//            .creationDate: timestamp,
//            .lastMessageTimestamp: timestamp,
//            .memberUids: membersUids,
//            .membersCount: membersUids.count,
//            .adminUids: [currentUid],
//            .createdBy: currentUid
//        ]
//
//        if let channelName = channelName, !channelName.isEmptyOrWhitespace {
//            channelDict[.name] = channelName
//        }
//
//        let messageDict: [String: Any] = [.type: newChannelBroadcast,
//                                          .timeStamp: timestamp,
//                                          .ownerUid: currentUid]
//
//        FirebaseConstants.ChannelsRef.child(channelId).setValue(channelDict)
//        FirebaseConstants.MessagesRef.child(channelId).child(messageId).setValue(messageDict)
//
//        membersUids.forEach { userId in
//            FirebaseConstants.UserChannelsRef.child(userId).child(channelId).setValue(true)
//        }
//
//        if isDirectChannel {
//            let chatPartner = selectedChatPartners[0]
//            FirebaseConstants.UserDirectChannels.child(currentUid).child(chatPartner.uid).setValue([channelId: true])
//            FirebaseConstants.UserDirectChannels.child(chatPartner.uid).child(currentUid).setValue([channelId: true])
//        }
//
//        var newChannelItem = ChannelItem(channelDict)
//        newChannelItem.members = selectedChatPartners
//        if let currentUser {
//            newChannelItem.members.append(currentUser)
//        }
        return .success(.placeholder)
    }
}








