//
//  BubbleContactView.swift
//  Pods
//
//  Created by Asyst on 8/27/25.
//

import SwiftUI
import Contacts
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct BubbleContactView: View {
    let message: MessageDataItem
    let contactsUseCases: ContactsUseCasesProtocol
    let isSelectionMode: Bool
    let navigationCoord: ChatsTabCoordinator
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel

    @State private var isOpenInfoSheet: Bool = false
    @State private var showAllContacts: Bool = false
    @State private var showSavedAlert: Bool = false
    @State private var savedAlertMessage: String = ""
    @State private var phonesInMyContacts: Set<String> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let contacts = message.message.contact, let firstContact = contacts.first {
            HStack {
                if message.direction == .sent {
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    // Forwarded indicator inside the bubble
                    forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")

                    VStack(spacing: 5) {
                        HStack(alignment: .top, spacing: 8) {
                            avatarStack(contacts)

                            VStack(alignment: .leading, spacing: 6) {
                                nameView(contacts, first: firstContact)

                                if contacts.count == 1 {
                                    Text(PhoneNumberFormatter.format(firstContact.phone))
                                        .font(.subheadline)
                                        .foregroundStyle(ChatBubbleStyle.foreground(for: colorScheme))
                                }
                            }
                            .padding(.trailing, 72)
                            .padding(.bottom, 2)
                            .overlay(alignment: .bottomTrailing) {
                                BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 10)
                        .frame(maxWidth: .infinity)

                        if contacts.count > 1 {
                            viewAllButton
                        } else  {
                            actionButtonsSection(contacts, first: firstContact)
                        }
                    }
                }
                .background(ChatBubbleStyle.mutedOverlay(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(8)
                .background(message.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .applyStrokeOnBubbleView()
                .applyTailView(message.direction)
                .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
                
                if message.direction == .received {
                    // No forward button for contact bubbles
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.8, alignment: message.alignment)
            .padding(.leading, message.direction == .received ? 10 : 60)
            .padding(.trailing, message.direction == .received ? 60 : 10)
            .onAppear { checkPersistedContacts(contacts) }
            .chatAppearanceSheet(isPresented: $isOpenInfoSheet) {
                ContactInfoView(
                    contact: firstContact,
                    isInDeviceContacts: isPersistedContact(firstContact),
                    onDismiss: { isOpenInfoSheet = false },
                    translationService: chatVM.translationService
                )
            }
            .id(message.id)
            .chatAppearanceSheet(isPresented: $showAllContacts) {
                NavigationView {
                    List(contacts, id: \.id) { contact in
                        HStack(spacing: 12) {
                            CircularProfileImageView(contact.avatar ?? "", size: .xSmall)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name ?? "Unknown").font(.headline)
                                Text(PhoneNumberFormatter.format(contact.phone))
                                    .font(.subheadline).foregroundColor(.secondary)
                            }
                            Spacer()

                            if phonesInMyContacts.contains(contact.phone) {
                                Button(t(ChatTranslationKeys.CONTACT_BUBBLE_MESSAGE)) { navigateToChat(contact: contact) }
                                    .font(.subheadline).buttonStyle(.bordered)
                            } else if !isPersistedContact(contact) {
                                Button {
                                    saveContact(contact)
                                } label: {
                                    Image(systemName: "person.badge.plus")
                                }.buttonStyle(.bordered)
                            } else {
                                Button { makePhoneCall(phone: contact.phone) } label: {
                                    Image(systemName: "phone.fill")
                                }.buttonStyle(.bordered)
                            }
                        }
                    }
                    .navigationTitle(t(ChatTranslationKeys.CONTACT_BUBBLE_SHARED_CONTACTS))
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button(common("done")) { showAllContacts = false }
                        }
                    }
                }
            }
            .alert(savedAlertMessage, isPresented: $showSavedAlert) {
                Button(common("ok"), role: .cancel) {}
            }
        }
    }

    // MARK: - View All Button (always visible for multi-contact)

    private var viewAllButton: some View {
        HStack(spacing: 0) {
            Button(action: { showAllContacts = true }) {
                Text(t(ChatTranslationKeys.CONTACT_BUBBLE_VIEW_ALL))
                    .frame(maxWidth: .infinity).padding().font(.subheadline)
            }
            .allowsHitTesting(!isSelectionMode)
        }
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(message.backgroundColor),
            alignment: .top
        )
    }

    // MARK: - Action Buttons (received single contact)

    @ViewBuilder
    private func actionButtonsSection(_ contacts: [ContactItem], first: ContactItem) -> some View {
        HStack(spacing: 0) {
            // Prefer Waangu registration state for primary action.
            if first.isRegistered == true {
                Button(action: { navigateToChat(contact: first) }) {
                    Text(t(ChatTranslationKeys.CONTACT_BUBBLE_MESSAGE))
                        .frame(maxWidth: .infinity).padding().font(.subheadline)
                }
                .allowsHitTesting(!isSelectionMode)
            } else if let isRegistered = first.isRegistered, isRegistered == false {
                // Not a Waangu user: show invite action.
                Button(action: {
                    // Reuse new-chat invite wording; actual invite flow can be refined later.
                    navigateToInvite(contact: first)
                }) {
                    Text(t(ChatTranslationKeys.NEW_CHAT_INVITE_ON_WAANGU))
                        .frame(maxWidth: .infinity).padding().font(.subheadline)
                }
                .allowsHitTesting(!isSelectionMode)
            } else if isPersistedContact(first) {
                Button(action: { makePhoneCall(phone: first.phone) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill").font(.caption)
                        Text(t(ChatTranslationKeys.CONTACT_BUBBLE_CALL))
                    }
                    .frame(maxWidth: .infinity).padding().font(.subheadline)
                }
                .allowsHitTesting(!isSelectionMode)

                Divider()
                    .frame(height: 30)
                    .background(Color.gray.opacity(0.5))

                Button(action: { saveContact(first) }) {
                    Text(t(ChatTranslationKeys.CONTACT_BUBBLE_ADD_CONTACT))
                        .frame(maxWidth: .infinity).padding().font(.subheadline)
                }
                .allowsHitTesting(!isSelectionMode)
            } else {
                Button(action: { makePhoneCall(phone: first.phone) }) {
                    HStack(spacing: 4) {
                        Image(systemName: "phone.fill").font(.caption)
                        Text(t(ChatTranslationKeys.CONTACT_BUBBLE_CALL))
                    }
                    .frame(maxWidth: .infinity).padding().font(.subheadline)
                }
                .allowsHitTesting(!isSelectionMode)
            }
        }
        .overlay(
            Rectangle()
                .frame(height: 2)
                .foregroundColor(message.backgroundColor),
            alignment: .top
        )
    }

    // MARK: - Avatar Stack

    @ViewBuilder
    private func avatarStack(_ contacts: [ContactItem]) -> some View {
        if contacts.count > 1 {
            ZStack(alignment: .leading) {
                ForEach(Array(contacts.prefix(3).enumerated()), id: \.offset) { index, contact in
                    CircularProfileImageView(contact.avatar ?? "", size: .xSmall)
                        .overlay(Circle().stroke(Color.white, lineWidth: 1))
                        .offset(x: CGFloat(index) * 6)
                        .zIndex(CGFloat(-index))
                }
            }
            .frame(width: 40 + CGFloat(min(contacts.count, 3) - 1) * 6, height: 40, alignment: .leading)
        } else {
            CircularProfileImageView(contacts.first?.avatar ?? "", size: .xSmall)
                .overlay(Circle().stroke(Color.white, lineWidth: 1))
        }
    }

    // MARK: - Name

    @ViewBuilder
    private func nameView(_ contacts: [ContactItem], first: ContactItem) -> some View {
        if contacts.count > 1 {
            Text(t(ChatTranslationKeys.CONTACT_BUBBLE_OTHER_CONTACTS, args: [first.name ?? "Unknown", "\(contacts.count - 1)"]))
                .foregroundStyle(AppColors.primary).lineLimit(2)
                .font(.system(size: 15, weight: .bold, design: .default))
        } else {
            Text(first.name ?? PhoneNumberFormatter.format(first.phone))
                .foregroundStyle(AppColors.primary).lineLimit(1)
                .font(.system(size: 15, weight: .bold, design: .default))
                .contentShape(Rectangle())
                .onTapGesture {
                    // Opens for every shared card. The old `idContact?.isEmpty == true`
                    // check only passed on an empty-string id, so the common nil
                    // case made the name untappable.
                    isOpenInfoSheet = true
                }
                .allowsHitTesting(!isSelectionMode)
        }
    }

    // MARK: - Local Contact Check (GRDB)

    private func checkPersistedContacts(_ contacts: [ContactItem]) {
        Task {
            var found = Set<String>()
            for contact in contacts where !contact.phone.isEmpty {
                if (try? await contactsUseCases.isContactPersisted.execute(phone: contact.phone)) == true {
                    found.insert(contact.phone)
                }
            }
            phonesInMyContacts = found
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }

    // MARK: - Actions

    private func navigateToChat(contact: ContactItem) {
        guard !isSelectionMode else { return }
        showAllContacts = false
        guard !contact.phone.isEmpty else { return }

        // Reuse an existing direct discussion for this phone when possible so we
        // don't mint a fresh UUID conversation on every Message tap.
        let targetDigits = contact.phone.onlyDigits
        let channelVM = navigationCoord.feature.makeChannelTabViewModel()
        let existingId = channelVM.discussions
            .first(where: {
                $0.contact?.isGroup == false
                && ($0.contact?.phone.onlyDigits ?? "") == targetDigits
            })?.conversationId
            ?? channelVM.archivedDiscussions
            .first(where: {
                $0.contact?.isGroup == false
                && ($0.contact?.phone.onlyDigits ?? "") == targetDigits
            })?.conversationId

        // The card already knows who this is — the sender's picker put the Waangu
        // account id, name and avatar on the wire. Hand them to the room instead
        // of letting it re-derive them from a phone number that, by definition,
        // is usually absent from *our* contacts.
        let peer = DirectChatPeer(
            userId: contact.userId,
            idContact: contact.idContact ?? "",
            name: contact.name ?? "",
            avatar: contact.avatar ?? ""
        )

        let route: ChatsTabRoute = .chatRoom(
            type: .direct(
                phoneNumber: contact.phone,
                conversationId: existingId,
                peer: peer.isEmpty ? nil : peer
            ),
            isArchived: false
        )
        navigationCoord.push(route)
    }

    private func saveContact(_ contact: ContactItem) {
        guard !isSelectionMode else { return }
        let store = CNContactStore()
        store.requestAccess(for: .contacts) { granted, _ in
            guard granted else {
                DispatchQueue.main.async {
                    savedAlertMessage = "Please allow contact access in Settings."
                    showSavedAlert = true
                }
                return
            }

            let cnContact = CNMutableContact()
            let nameParts = (contact.name ?? "").split(separator: " ")
            cnContact.givenName = nameParts.first.map(String.init) ?? ""
            if nameParts.count > 1 {
                cnContact.familyName = nameParts.dropFirst().joined(separator: " ")
            }
            cnContact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile,
                                                     value: CNPhoneNumber(stringValue: contact.phone))]

            let saveRequest = CNSaveRequest()
            saveRequest.add(cnContact, toContainerWithIdentifier: nil)

            do {
                try store.execute(saveRequest)
                DispatchQueue.main.async {
                    savedAlertMessage = "\(contact.name ?? "Contact") saved!"
                    showSavedAlert = true
                }
            } catch {
                DispatchQueue.main.async {
                    savedAlertMessage = ChatErrorStrings.saveContactFailed
                    showSavedAlert = true
                }
            }
        }
    }

    private func navigateToInvite(contact: ContactItem) {
        // For now, just open the system share sheet with the phone number.
        // A dedicated Waangu invite link flow can replace this implementation.
        makePhoneCall(phone: contact.phone)
    }

    private func isPersistedContact(_ contact: ContactItem) -> Bool {
        guard !contact.phone.isEmpty else { return false }
        return phonesInMyContacts.contains(contact.phone)
    }

    private func makePhoneCall(phone: String) {
        guard !isSelectionMode else { return }
        let cleaned = phone.replacingOccurrences(of: " ", with: "")
        guard let url = URL(string: "tel:\(cleaned)") else { return }
        UIApplication.shared.open(url)
    }
}
