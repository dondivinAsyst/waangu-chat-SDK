//
//  ContactInfoView.swift
//  Pods
//
//  Created by Asyst on 8/29/25.
//
import SwiftUI
import Contacts
import WaanguSharedUI
import WaanguCoreKit

/// Details for a contact card shared into a chat.
///
/// Everything here comes from the `ContactItem` that was actually shared — the
/// screen used to render a placeholder avatar and one hardcoded phone number
/// regardless of which card you opened.
struct ContactInfoView: View {
    let contact: ContactItem
    /// Whether this number is already saved on the device, which decides
    /// between offering "save" actions and offering to message them.
    let isInDeviceContacts: Bool
    let onDismiss: () -> Void
    let translationService: (any TranslationServiceProtocol)?

    init(
        contact: ContactItem,
        isInDeviceContacts: Bool = false,
        onDismiss: @escaping () -> Void,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.contact = contact
        self.isInDeviceContacts = isInDeviceContacts
        self.onDismiss = onDismiss
        self.translationService = translationService
    }

    @State private var showAddSheet = false
    @State private var showContactPicker = false
    @State private var showInviteSheet = false
    @State private var resultMessage: String?

    private var displayName: String {
        let name = (contact.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? PhoneNumberFormatter.format(contact.phone) : name
    }

    private var formattedPhone: String {
        PhoneNumberFormatter.format(contact.phone)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {

                // Avatar + Name
                VStack(spacing: 12) {
                    avatar

                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 20)

                // Options list
                VStack(spacing: 0) {
                    if !isInDeviceContacts {
                        optionRow(title: t(ChatTranslationKeys.CONTACT_INFO_INVITE_TO_WAANGU))
                            .contentShape(Rectangle())
                            .onTapGesture { showInviteSheet = true }
                        Divider()
                    }

                    optionRow(title: t(ChatTranslationKeys.CONTACT_INFO_CREATE_NEW))
                        .contentShape(Rectangle())
                        .onTapGesture { showAddSheet = true }
                    Divider()
                    optionRow(title: t(ChatTranslationKeys.CONTACT_INFO_ADD_TO_EXISTING))
                        .contentShape(Rectangle())
                        .onTapGesture { showContactPicker = true }
                }
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)

                // Phone number
                VStack(alignment: .leading, spacing: 6) {
                    Text(t(ChatTranslationKeys.CONTACT_INFO_MOBILE))
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text(formattedPhone)
                        .font(.body)
                        .foregroundColor(.blue)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)
                .padding(.top, 20)

                Spacer()
            }
            .chatAppearanceSheet(isPresented: $showAddSheet) {
                NewContactView(
                    draft: ContactDraft(
                        name: contact.name ?? "",
                        phone: contact.phone,
                        isExisting: false
                    ),
                    translationService: translationService
                )
            }
            .chatAppearanceSheet(isPresented: $showContactPicker) {
                DeviceContactPickerView(
                    onSelect: { existing in
                        showContactPicker = false
                        addNumber(to: existing)
                    },
                    onCancel: { showContactPicker = false }
                )
            }
            .chatAppearanceSheet(isPresented: $showInviteSheet) {
                ActivityShareSheet(
                    activityItems: [t(ChatTranslationKeys.CONTACT_INFO_INVITE_MESSAGE)]
                )
            }
            .customAlert(
                title: t(ChatTranslationKeys.CONTACT_INFO_NAV_TITLE),
                message: resultMessage,
                isPresented: .init(
                    get: { resultMessage != nil },
                    set: { if !$0 { resultMessage = nil } }
                ),
                okTitle: common("ok"),
                animation: .smooth,
                onDismiss: { resultMessage = nil }
            )
            .background(Color(UIColor.systemGroupedBackground))
            .navigationBarTitle(t(ChatTranslationKeys.CONTACT_INFO_NAV_TITLE), displayMode: .inline)
            .navigationBarItems(leading:
                Button(t(ChatTranslationKeys.CONTACT_INFO_CLOSE)) {
                onDismiss()
                }
            )
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarUrl = contact.avatar, !avatarUrl.isEmpty {
            CircularProfileImageView(avatarUrl, size: .custom(80))
        } else {
            Circle()
                .fill(Color.gray.opacity(0.3))
                .frame(width: 80, height: 80)
                .overlay(
                    Text(String(displayName.prefix(1)).uppercased())
                        .font(.title)
                        .foregroundColor(.white)
                )
        }
    }

    private func addNumber(to existing: CNContact) {
        Task {
            do {
                try await DeviceContactWriter.addPhoneNumber(contact.phone, to: existing)
                await MainActor.run {
                    NotificationCenter.default.post(name: .contactsShouldRefresh, object: nil)
                    resultMessage = t(
                        ChatTranslationKeys.CONTACT_INFO_ADDED_TO_CONTACT,
                        args: [CNContactFormatter.string(from: existing, style: .fullName) ?? ""]
                    )
                }
            } catch {
                await MainActor.run {
                    resultMessage = t(
                        ChatTranslationKeys.CONTACT_INFO_ADD_FAILED,
                        args: [error.localizedDescription]
                    )
                }
            }
        }
    }

    // Reusable row
    @ViewBuilder
    func optionRow(title: String) -> some View {
        HStack {
            Text(title)
                .foregroundColor(.blue)
            Spacer()
        }
        .padding()

    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
