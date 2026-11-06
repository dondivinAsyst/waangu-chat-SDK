import SwiftUI
import Combine
import WaanguCoreKit

@available(iOS 17.0, *)
struct CreateGroupView: View {

    @StateObject private var viewModel: CreateGroupViewModel
    @Environment(\.dismiss) private var dismiss
    let translationService: (any TranslationServiceProtocol)?

    init(
        contacts: [WaanguContact],
        groupUseCases: GroupUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        onGroupCreated: @escaping (GroupChat) -> Void,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: CreateGroupViewModel(
            contacts: contacts,
            groupUseCases: groupUseCases,
            discussionUseCases: discussionUseCases,
            onGroupCreated: onGroupCreated
        ))
        self.translationService = translationService
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                groupInfoSection
                selectedMembersSection
                contactListSection
            }
            .navigationTitle(t(ChatTranslationKeys.CREATE_GROUP_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t(ChatTranslationKeys.NEW_GROUP_CREATE)) {
                        Task {
                            await viewModel.createGroup()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canCreate)
                    .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Group Info

    private var groupInfoSection: some View {
        HStack(spacing: 16) {
            Button {
                viewModel.showImagePicker = true
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 64, height: 64)
                    if let image = viewModel.groupAvatar {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 64, height: 64)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            VStack(spacing: 8) {
                TextField(t(ChatTranslationKeys.CREATE_GROUP_NAME), text: $viewModel.groupName)
                    .textFieldStyle(.roundedBorder)
                TextField(t(ChatTranslationKeys.CREATE_GROUP_DESCRIPTION), text: $viewModel.groupDescription)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
            }
        }
        .padding()
    }

    // MARK: - Selected Members

    private var selectedMembersSection: some View {
        Group {
            if !viewModel.selectedContacts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(viewModel.selectedContacts, id: \.phone) { contact in
                            VStack(spacing: 4) {
                                ZStack(alignment: .topTrailing) {
                                    Circle()
                                        .fill(Color(.systemGray4))
                                        .frame(width: 48, height: 48)
                                        .overlay {
                                            Text(String(contact.name.prefix(1)).uppercased())
                                                .font(.title3.weight(.semibold))
                                                .foregroundStyle(.white)
                                        }
                                    Button {
                                        viewModel.toggleSelection(contact)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.caption)
                                            .foregroundStyle(.white, .gray)
                                    }
                                }
                                Text(contact.name.components(separatedBy: " ").first ?? "")
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                .frame(height: 80)

                Divider()

                Text(t(ChatTranslationKeys.CREATE_GROUP_MEMBERS_SELECTED, args: ["\(viewModel.selectedContacts.count)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
            }
        }
    }

    // MARK: - Contacts List

    private var contactListSection: some View {
        List {
            ForEach(viewModel.filteredContacts, id: \.phone) { contact in
                Button {
                    viewModel.toggleSelection(contact)
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(contact.name.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(contact.name)
                                .font(.subheadline.weight(.medium))
                            Text(contact.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if viewModel.isSelected(contact) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .searchable(text: $viewModel.searchText, prompt: t(ChatTranslationKeys.CREATE_GROUP_SEARCH_CONTACTS))
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - ViewModel

@MainActor
final class CreateGroupViewModel: ObservableObject {

    @Published var groupName = ""
    @Published var groupDescription = ""
    @Published var groupAvatar: UIImage?
    @Published var showImagePicker = false
    @Published var searchText = ""
    @Published var selectedContacts: [WaanguContact] = []
    @Published var isCreating = false

    private let contacts: [WaanguContact]
    private let groupUseCases: GroupUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let onGroupCreated: (GroupChat) -> Void

    var canCreate: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
        && selectedContacts.count >= 1
        && !isCreating
    }

    var filteredContacts: [WaanguContact] {
        if searchText.isEmpty { return contacts }
        return contacts.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
            || $0.phone.contains(searchText)
        }
    }

    init(
        contacts: [WaanguContact],
        groupUseCases: GroupUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        onGroupCreated: @escaping (GroupChat) -> Void
    ) {
        self.contacts = contacts
        self.groupUseCases = groupUseCases
        self.discussionUseCases = discussionUseCases
        self.onGroupCreated = onGroupCreated
    }

    func toggleSelection(_ contact: WaanguContact) {
        if let index = selectedContacts.firstIndex(where: { $0.phone == contact.phone }) {
            selectedContacts.remove(at: index)
        } else {
            selectedContacts.append(contact)
        }
    }

    func isSelected(_ contact: WaanguContact) -> Bool {
        selectedContacts.contains(where: { $0.phone == contact.phone })
    }

    func createGroup() async {
        isCreating = true
        defer { isCreating = false }

        let invitedMembers = selectedContacts.map { contact in
            UserContactProps(
                idContact: contact.id,
                userId: contact.userId,
                name: contact.name,
                avatar: contact.image,
                phone: contact.phone,
                description: contact.bio ?? "",
                isBlocked: contact.isBlocked
            )
        }

        do {
            let input = CreateGroupWithDiscussionInput(
                groupName: groupName.trimmingCharacters(in: .whitespacesAndNewlines),
                invitedMembers: invitedMembers
            )
            let result = try await groupUseCases.createGroup.execute(input)
            onGroupCreated(result.group)
        } catch {
            debugLog("Failed to create group: \(error)")
        }
    }
}
