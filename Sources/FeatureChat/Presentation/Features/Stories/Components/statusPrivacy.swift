import SwiftUI
import WaanguCoreKit

// MARK: - Models
struct Contact: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let phoneNumber: String
    let avatarColor: Color
    
    var initials: String {
        let components = name.components(separatedBy: " ")
        let firstInitial = components.first?.first.map(String.init) ?? ""
        let lastInitial = components.count > 1 ? components.last?.first.map(String.init) ?? "" : ""
        return firstInitial + lastInitial
    }
}

struct Groups: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let memberCount: Int
    let avatarColor: Color
}

enum StatusPrivacyOption {
    case myContacts
    case myContactsExcept
    case onlyShareWith
}

// MARK: - Status Privacy View
struct StatusPrivacyView: View {
    @State private var selectedOption: StatusPrivacyOption = .onlyShareWith
    @State private var excludedContacts = Set<Contact>()
    @State private var includedContacts: Set<Contact> = [ContactSelectionView.sampleContacts[0]]
    @State private var showExcludeSelection = false
    @State private var showIncludeSelection = false
    @State private var allowSharing = false
    @Environment(\.dismiss) var dismiss
    let translationService: (any TranslationServiceProtocol)?

    init(translationService: (any TranslationServiceProtocol)? = nil) {
        self.translationService = translationService
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.09, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Top Handle
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 40, height: 5)
                    .padding(.top, 8)
                
                // Header
                HStack {
                    Text(t(ChatTranslationKeys.STORIES_STATUS_PRIVACY_TITLE))
                        .font(.title3)
                        .fontWeight(.regular)
                        .foregroundColor(.white)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 32)
                
                // Options
                VStack(spacing: 0) {
                    // My contacts
                    PrivacyOptionRow(
                        isSelected: selectedOption == .myContacts,
                        title: t(ChatTranslationKeys.STORIES_MY_CONTACTS),
                        count: nil,
                        translationService: translationService,
                        onTap: {
                            selectedOption = .myContacts
                        }
                    )
                    
                    // My contacts except
                    PrivacyOptionRow(
                        isSelected: selectedOption == .myContactsExcept,
                        title: t(ChatTranslationKeys.STORIES_MY_CONTACTS_EXCEPT),
                        count: excludedContacts.count,
                        countColor: .green,
                        showExcluded: true,
                        translationService: translationService,
                        onTap: {
                            selectedOption = .myContactsExcept
                            showExcludeSelection = true
                        }
                    )
                    
                    // Only share with
                    PrivacyOptionRow(
                        isSelected: selectedOption == .onlyShareWith,
                        title: t(ChatTranslationKeys.STORIES_ONLY_SHARE_WITH),
                        count: includedContacts.count,
                        countColor: .green,
                        showExcluded: false,
                        translationService: translationService,
                        onTap: {
                            selectedOption = .onlyShareWith
                            showIncludeSelection = true
                        }
                    )
                }
                
//                Spacer()
                // Allow Sharing Section
                     VStack(spacing: 0) {
                         Rectangle()
                             .fill(Color(red: 0.12, green: 0.14, blue: 0.13))
                             .frame(height: 12)
                         
                         AllowSharingRow(isEnabled: $allowSharing, translationService: translationService)
                     }
                     .padding(.top, 24)
                     
                     Spacer()
                 }
            }
        
        .chatAppearanceSheet(isPresented: $showExcludeSelection) {
            ContactSelectionView(
                mode: .exclude,
                selectedContacts: $excludedContacts,
                translationService: translationService
            )
        }
        .chatAppearanceSheet(isPresented: $showIncludeSelection) {
            ContactSelectionView(
                mode: .include,
                selectedContacts: $includedContacts,
                translationService: translationService
            )
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct AllowSharingRow: View {
    @Binding var isEnabled: Bool
    let translationService: (any TranslationServiceProtocol)?

    init(
        isEnabled: Binding<Bool>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._isEnabled = isEnabled
        self.translationService = translationService
    }

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "arrowshape.turn.up.right")
                .foregroundColor(.gray)
                .font(.system(size: 24))
                .frame(width: 30)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(t(ChatTranslationKeys.STORIES_ALLOW_SHARING))
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                
                Text(t(ChatTranslationKeys.STORIES_ALLOW_SHARING_DESC))
                    .font(.system(size: 14))
                    .foregroundColor(.gray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            // Toggle
            Toggle("", isOn: $isEnabled)
                           .labelsHidden()
                           .tint(isEnabled ? .green : Color(red: 0.3, green: 0.3, blue: 0.3))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}



struct PrivacyOptionRow: View {
    let isSelected: Bool
    let title: String
    let count: Int?
    var countColor: Color = .green
    var showExcluded: Bool = false
    let translationService: (any TranslationServiceProtocol)?
    let onTap: () -> Void

    init(
        isSelected: Bool,
        title: String,
        count: Int?,
        countColor: Color = .green,
        showExcluded: Bool = false,
        translationService: (any TranslationServiceProtocol)? = nil,
        onTap: @escaping () -> Void
    ) {
        self.isSelected = isSelected
        self.title = title
        self.count = count
        self.countColor = countColor
        self.showExcluded = showExcluded
        self.translationService = translationService
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Radio button
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.green : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 14, height: 14)
                    }
                }
                
                // Title
                Text(title)
                    .font(.system(size: 17))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Count
                if let count = count, count > 0 {
                    Text(showExcluded
                        ? t(ChatTranslationKeys.STORIES_EXCLUDED_COUNT, args: ["\(count)"])
                        : t(ChatTranslationKeys.STORIES_INCLUDED_COUNT, args: ["\(count)"]))
                        .font(.system(size: 15))
                        .foregroundColor(countColor)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Contact Selection View
struct ContactSelectionView: View {
    let mode: SelectionMode
    @Binding var selectedContacts: Set<Contact>
    @Environment(\.dismiss) var dismiss
    let translationService: (any TranslationServiceProtocol)?

    init(
        mode: SelectionMode,
        selectedContacts: Binding<Set<Contact>>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.mode = mode
        self._selectedContacts = selectedContacts
        self.translationService = translationService
    }

    @State private var searchText = ""
    @State private var contacts: [Contact] = Self.sampleContacts
    
    enum SelectionMode {
        case include
        case exclude
    }
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        NavigationView {
            if #available(iOS 16.0, *) {
                ZStack {
                    Color(red: 0.07, green: 0.09, blue: 0.08)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 0) {
                        // Search Bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(.gray)
                            
                            TextField(t(ChatTranslationKeys.STORIES_SEARCH_PLACEHOLDER), text: $searchText)
                                .textFieldStyle(PlainTextFieldStyle())
                                .foregroundColor(.white)
                            
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .padding(10)
                        .background(Color(red: 0.12, green: 0.14, blue: 0.13))
                        .cornerRadius(10)
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        
                        // Selected Count
                        if !selectedContacts.isEmpty {
                            HStack {
                                Text(t(ChatTranslationKeys.STORIES_SELECTED_COUNT, args: ["\(selectedContacts.count)"]))
                                    .font(.system(size: 14))
                                    .foregroundColor(.gray)
                                Spacer()
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 8)
                        }
                        
                        // Contact List
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(filteredContacts) { contact in
                                    ContactRow(
                                        contact: contact,
                                        isSelected: selectedContacts.contains(contact)
                                    ) {
                                        toggleSelection(contact)
                                    }
                                    
                                    Divider()
                                        .background(Color.gray.opacity(0.3))
                                        .padding(.leading, 70)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(mode == .include ? t(ChatTranslationKeys.STORIES_SHARE_WITH) : t(ChatTranslationKeys.STORIES_EXCLUDE_FROM))
                .navigationBarTitleDisplayMode(.inline)
                .toolbarColorScheme(.dark, for: .navigationBar)
                .toolbarBackground(Color(red: 0.07, green: 0.09, blue: 0.08), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(common("cancel")) {
                            dismiss()
                        }
                        .foregroundColor(.white)
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(t(ChatTranslationKeys.STORIES_DONE)) {
                            dismiss()
                        }
                        .foregroundColor(.white)
                        .fontWeight(.semibold)
                    }
                }
            } else {
                // Fallback on earlier versions
            }
        }
    }
    
    private func toggleSelection(_ contact: Contact) {
        if selectedContacts.contains(contact) {
            selectedContacts.remove(contact)
        } else {
            selectedContacts.insert(contact)
        }
    }
    
    static var sampleContacts: [Contact] {
        [
            Contact(name: "Alice Johnson", phoneNumber: "+1234567890", avatarColor: .blue),
            Contact(name: "Bob Smith", phoneNumber: "+1234567891", avatarColor: .green),
            Contact(name: "Carol Williams", phoneNumber: "+1234567892", avatarColor: .orange),
            Contact(name: "David Brown", phoneNumber: "+1234567893", avatarColor: .purple),
            Contact(name: "Emma Davis", phoneNumber: "+1234567894", avatarColor: .pink),
            Contact(name: "Frank Miller", phoneNumber: "+1234567895", avatarColor: .red),
            Contact(name: "Grace Wilson", phoneNumber: "+1234567896", avatarColor: .teal),
            Contact(name: "Henry Taylor", phoneNumber: "+1234567897", avatarColor: .indigo)
        ]
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

struct ContactRow: View {
    let contact: Contact
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Avatar
                Circle()
                    .fill(contact.avatarColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(contact.initials)
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                    )
                
                // Contact Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(contact.name)
                        .foregroundColor(.white)
                        .fontWeight(.regular)
                    Text(contact.phoneNumber)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Checkmark
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.green : Color.gray.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                    
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundColor(.green)
                            .font(.system(size: 12, weight: .bold))
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Mention Picker View
struct MentionPickerView: View {
    @Binding var isPresented: Bool
    var onSelect: (MentionItem) -> Void
    let translationService: (any TranslationServiceProtocol)?

    init(
        isPresented: Binding<Bool>,
        onSelect: @escaping (MentionItem) -> Void,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._isPresented = isPresented
        self.onSelect = onSelect
        self.translationService = translationService
    }
    
    @State private var searchText = ""
    @State private var contacts: [Contact] = ContactSelectionView.sampleContacts
    @State private var groups: [Groups] = Self.sampleGroups
    
    var filteredContacts: [Contact] {
        if searchText.isEmpty {
            return contacts
        }
        return contacts.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var filteredGroups: [Groups] {
        if searchText.isEmpty {
            return groups
        }
        return groups.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }
    
    var body: some View {
        ZStack {
            Color(red: 0.07, green: 0.09, blue: 0.08)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text(t(ChatTranslationKeys.STORIES_MENTION))
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: { isPresented = false }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                .padding()
                
                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField(t(ChatTranslationKeys.STORIES_SEARCH_PEOPLE_GROUPS), text: $searchText)
                        .textFieldStyle(PlainTextFieldStyle())
                        .foregroundColor(.white)
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                }
                .padding(10)
                .background(Color(red: 0.12, green: 0.14, blue: 0.13))
                .cornerRadius(10)
                .padding(.horizontal)
                .padding(.bottom, 12)
                
                Divider()
                    .background(Color.gray.opacity(0.3))
                
                // Results
                ScrollView {
                    VStack(spacing: 0) {
                        // Groups Section
                        if !filteredGroups.isEmpty {
                            SectionHeader(title: t(ChatTranslationKeys.STORIES_GROUPS))
                            ForEach(filteredGroups) { group in
                                MentionGroupRow(group: group) {
                                    onSelect(.group(group))
                                    isPresented = false
                                }
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.leading, 70)
                            }
                        }
                        
                        // Contacts Section
                        if !filteredContacts.isEmpty {
                            SectionHeader(title: t(ChatTranslationKeys.STORIES_CONTACTS))
                            ForEach(filteredContacts) { contact in
                                MentionContactRow(contact: contact) {
                                    onSelect(.contact(contact))
                                    isPresented = false
                                }
                                Divider()
                                    .background(Color.gray.opacity(0.3))
                                    .padding(.leading, 70)
                            }
                        }
                    }
                }
            }
        }
    }
    
    static var sampleGroups: [Groups] {
        [
            Groups(name: "Family", memberCount: 5, avatarColor: .blue),
            Groups(name: "Work Team", memberCount: 12, avatarColor: .green),
            Groups(name: "Friends", memberCount: 8, avatarColor: .orange)
        ]
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

enum MentionItem {
    case contact(Contact)
    case group(Groups)
}

struct MentionContactRow: View {
    let contact: Contact
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(contact.avatarColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(contact.initials)
                            .foregroundColor(.white)
                            .fontWeight(.medium)
                    )
                
                Text(contact.name)
                    .foregroundColor(.white)
                    .fontWeight(.regular)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct MentionGroupRow: View {
    let group: Groups
    let onTap: () -> Void
    let translationService: (any TranslationServiceProtocol)? = nil
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(group.avatarColor)
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    )
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.name)
                        .foregroundColor(.white)
                        .fontWeight(.regular)
                    Text(t(ChatTranslationKeys.STORIES_MEMBERS, args: ["\(group.memberCount)"]))
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

private struct SectionHeader: View {
    let title: String
    
    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundColor(.gray)
                .fontWeight(.semibold)
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}
