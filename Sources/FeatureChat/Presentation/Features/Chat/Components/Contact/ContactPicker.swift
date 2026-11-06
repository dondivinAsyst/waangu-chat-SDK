//
//  ContactPicker.swift
//  Pods
//
//  Created by Asyst on 8/25/25.
//

import SwiftUI
import WaanguCoreKit


struct ContactPicker: View {

    @ObservedObject var viewModel: GalleryViewModel
    let onDismiss: () -> Void
    var onSendContacts: (([ContactItem]) -> Void)?
    let translationService: (any TranslationServiceProtocol)?

    init(
        viewModel: GalleryViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onDismiss: @escaping () -> Void,
        onSendContacts: (([ContactItem]) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.translationService = translationService
        self.onDismiss = onDismiss
        self.onSendContacts = onSendContacts
    }

    @State private var searchText: String = ""
    @State private var selectedContacts = Set<String>()
    @State private var editMode: Bool = false

    var filteredContacts: [UserContactProps] {
        if searchText.isEmpty {
            return viewModel.contactsList
        } else {
            return viewModel.contactsList.filter { $0.name.lowercased().contains(searchText.lowercased()) }
        }
    }

    var body: some View {
        NavigationView {
            List(filteredContacts, id: \.phone) { contact in
                HStack(spacing: 12) {
                    if editMode {
                        CheckboxBounceView(
                            isSelected: selectedContacts.contains(contact.phone),
                            isEditMode: editMode,
                            id: contact.phone
                        )
                    }

                    RemoteImageView(urlString: contact.avatar ?? "", fallBack: "")

                    VStack(alignment: .leading) {
                        Text(contact.name).font(.headline)
                        Text(contact.description).font(.subheadline).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if editMode {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                            toggleSelection(contact)
                        }
                    }
                }
                .onLongPressGesture {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        editMode = true
                        toggleSelection(contact)
                    }
                }
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: editMode)
                .listRowBackground(Color.clear)
            }
            .searchable(text: $searchText, prompt: t(ChatTranslationKeys.CONTACT_PICKER_SEARCH_BY_NAME))
            .navigationTitle(t(ChatTranslationKeys.CONTACT_PICKER_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(t(ChatTranslationKeys.CONTACT_PICKER_CLOSE)) {
                        onDismiss()
                        selectedContacts.removeAll()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        let contactItems = buildContactItems()
                        onSendContacts?(contactItems)
                    }) {
                        Text(t(ChatTranslationKeys.CONTACT_PICKER_SEND)).font(.headline).bold().foregroundColor(.blue)
                    }
                    .opacity(selectedContacts.isEmpty ? 0 : 1)
                    .disabled(selectedContacts.isEmpty)
                    .animation(.easeInOut, value: selectedContacts.isEmpty)
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                editMode = true
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func toggleSelection(_ contact: UserContactProps) {
        if selectedContacts.contains(contact.phone) {
            selectedContacts.remove(contact.phone)
        } else {
            selectedContacts.insert(contact.phone)
        }
    }

    private func buildContactItems() -> [ContactItem] {
        return viewModel.contactsList
            .filter { selectedContacts.contains($0.phone) }
            .map { contact in
                ContactItem(
                    idContact: contact.idContact ?? "",
                    userId: contact.userId,
                    phone: contact.phone,
                    name: contact.name,
                    avatar: contact.avatar,
                    isRegistered: !contact.userId.isEmpty
                )
            }
    }
}




struct CheckboxBounceView: View {
    let isSelected: Bool
    let isEditMode: Bool
    let id: String
    
    @State private var currentScale: CGFloat = 1.0
    @State private var isAnimating = false
    
    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .foregroundColor(.blue)
            .font(.title2)
            .scaleEffect(currentScale)
            .offset(x: isEditMode ? 0 : -50)
            .opacity(isEditMode ? 1 : 0)
            .frame(width: isEditMode ? 30 : 0)
            .onChange(of: isSelected) { newValue in
                if newValue {
                    triggerBounceAnimation()
                }
            }

            .onAppear {
                currentScale = 1.0
            }
    }
    
    private func triggerBounceAnimation() {
        guard !isAnimating else { return }
        
        isAnimating = true
        
        // Animation de bounce
        withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
            currentScale = 1.3
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.15)) {
                currentScale = 1.0
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                isAnimating = false
            }
        }
    }
}

