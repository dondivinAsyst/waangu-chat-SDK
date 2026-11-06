import SwiftUI
import Combine
import WaanguSharedUI
import WaanguCoreKit

@MainActor
final class NewCallViewModel: ObservableObject {
    @Published var waanguContacts: [UserContactProps] = []
    @Published var deviceContacts: [UserContactProps] = []
    @Published var isLoading = false
    
    private let contactUseCases: ContactsUseCasesProtocol
    
    init(contactUseCases: ContactsUseCasesProtocol) {
        self.contactUseCases = contactUseCases
        Task { await loadContacts() }
    }
    
    func loadContacts() async {
        isLoading = true
        defer { isLoading = false }
        
        if let persisted = try? await contactUseCases.getPersistedContacts.execute() {
            waanguContacts = persisted.UserContactProps
        }
        
        if let device = try? await contactUseCases.getDeviceContacts.execute() {
            deduplicateDeviceContacts(device)
        }
        
        if let updated = try? await contactUseCases.getUpdatedContacts.execute() {
            waanguContacts = updated.UserContactProps
            if let device = try? await contactUseCases.getDeviceContacts.execute() {
                deduplicateDeviceContacts(device)
            }
        }
    }
    
    private func deduplicateDeviceContacts(_ allDevice: [UserContactProps]) {
        let waanguPhones = Set(waanguContacts.map { $0.phone.onlyDigits }.filter { !$0.isEmpty })
        deviceContacts = allDevice.filter { contact in
            let phone = contact.phone.onlyDigits
            guard !phone.isEmpty else { return true }
            return !waanguPhones.contains(phone)
        }
    }
}

struct NewCallSheet: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: NewCallViewModel
    @State private var searchText = ""
    /// People picked for a group call, in the order they were tapped — the first
    /// is dialled and the rest are invited once the room exists.
    @State private var selected: [UserContactProps] = []
    @State private var isSelecting = false
    let translationService: (any TranslationServiceProtocol)?
    
    init(contactUseCases: ContactsUseCasesProtocol, translationService: (any TranslationServiceProtocol)? = nil) {
        _viewModel = StateObject(wrappedValue: NewCallViewModel(contactUseCases: contactUseCases))
        self.translationService = translationService
    }
    
    private var filteredWaanguContacts: [UserContactProps] {
        if searchText.isEmpty { return viewModel.waanguContacts }
        return viewModel.waanguContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    private var filteredDeviceContacts: [UserContactProps] {
        if searchText.isEmpty { return viewModel.deviceContacts }
        return viewModel.deviceContacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationView {
            List {
                Section {
                    callLinkRow()
                }
                
                if viewModel.isLoading && viewModel.waanguContacts.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    if !filteredWaanguContacts.isEmpty {
                        Section {
                            ForEach(filteredWaanguContacts) { contact in
                                contactCallRow(contact)
                            }
                        } header: {
                            Text(t(ChatTranslationKeys.CALLS_CONTACTS_ON_WAANGU))
                                .textCase(nil)
                        }
                    }
                    
                    if !filteredDeviceContacts.isEmpty {
                        Section {
                            ForEach(filteredDeviceContacts) { contact in
                                deviceContactRow(contact)
                            }
                        } header: {
                            Text(t(ChatTranslationKeys.CALLS_INVITE_TO_WAANGU))
                                .textCase(nil)
                        }
                    }
                    
                    if filteredWaanguContacts.isEmpty && filteredDeviceContacts.isEmpty {
                        Section {
                            VStack(spacing: 8) {
                                Image(systemName: "person.crop.circle.badge.questionmark")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.secondary)
                                Text(t(ChatTranslationKeys.CALLS_NO_CONTACTS))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .navigationTitle(t(ChatTranslationKeys.CALLS_NEW_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: t(ChatTranslationKeys.CALLS_SEARCH_CONTACTS))
            .safeAreaInset(edge: .bottom) {
                if isSelecting && !selected.isEmpty {
                    selectionBar
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(isSelecting
                           ? common("cancel")
                           : t(ChatTranslationKeys.CALLS_NEW_GROUP_CALL)) {
                        isSelecting.toggle()
                        selected.removeAll()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(common("cancel")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Group selection

    private func isSelected(_ contact: UserContactProps) -> Bool {
        selected.contains { $0.phone.onlyDigits == contact.phone.onlyDigits }
    }

    private func toggleSelection(_ contact: UserContactProps) {
        if let index = selected.firstIndex(where: { $0.phone.onlyDigits == contact.phone.onlyDigits }) {
            selected.remove(at: index)
        } else if selected.count < VoipManager.maxParticipants - 1 {
            // The room holds 32 including this device.
            selected.append(contact)
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Text(t(ChatTranslationKeys.CALLS_SELECTED_COUNT, args: ["\(selected.count)"]))
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Button {
                placeGroupCall(hasVideo: false)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(AppColors.primary))
            }
            .buttonStyle(.plain)

            Button {
                placeGroupCall(hasVideo: true)
            } label: {
                Image(systemName: "video.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(AppColors.primary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }

    private func placeGroupCall(hasVideo: Bool) {
        let invitees = selected.map {
            CallInvitee(userId: $0.userId, name: $0.name, phone: $0.phone)
        }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            VoipManager.shared.startGroupCall(invitees, hasVideo: hasVideo)
        }
    }
    
    private func callLinkRow() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "link")
                .font(.system(size: 16))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(AppColors.primary)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(t(ChatTranslationKeys.CALLS_CREATE_LINK))
                    .foregroundStyle(AppColors.primary)
                Text(t(ChatTranslationKeys.CALLS_CREATE_LINK_DESC))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    @ViewBuilder
    private func contactCallRow(_ contact: UserContactProps) -> some View {
        if isSelecting {
            // Picking people for a group: the per-contact call buttons would be
            // two competing ways to start a call from the same row.
            Button {
                toggleSelection(contact)
            } label: {
                HStack(spacing: 12) {
                    CircularProfileImageView(contact.avatar, size: .xSmall)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(.system(size: 16))
                            .foregroundStyle(.primary)

                        if !contact.description.isEmpty {
                            Text(contact.description)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: isSelected(contact) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(isSelected(contact) ? AppColors.primary : Color.secondary.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
        } else {
            singleContactCallRow(contact)
        }
    }

    private func singleContactCallRow(_ contact: UserContactProps) -> some View {
        HStack(spacing: 12) {
            CircularProfileImageView(contact.avatar, size: .xSmall)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 16))
                
                if !contact.description.isEmpty {
                    Text(contact.description)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    VoipManager.shared.startOutgoingCall(
                        to: contact.phone,
                        hasVideo: false,
                        name: contact.name,
                        image: contact.avatar,
                        userId: contact.userId
                    )
                }
            } label: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(AppColors.primary)
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            
            Button {
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    VoipManager.shared.startOutgoingCall(
                        to: contact.phone,
                        hasVideo: true,
                        name: contact.name,
                        image: contact.avatar,
                        userId: contact.userId
                    )
                }
            } label: {
                Image(systemName: "video.fill")
                    .foregroundStyle(AppColors.primary)
                    .font(.system(size: 18))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func deviceContactRow(_ contact: UserContactProps) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 40, height: 40)
                .foregroundStyle(.gray.opacity(0.5))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.system(size: 16))
                
                Text(contact.phone)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            Button {
            } label: {
                Text(t(ChatTranslationKeys.CALLS_INVITE))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }
            .buttonStyle(.plain)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
