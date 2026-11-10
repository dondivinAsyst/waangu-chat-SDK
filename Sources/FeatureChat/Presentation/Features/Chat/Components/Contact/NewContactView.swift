//
//  CreateContact.swift
//  Pods
//
//  Created by Asyst on 8/29/25.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Name and number a contact sheet should open with, whatever the source — an
/// existing Waangu contact, or a contact card shared into a chat.
struct ContactDraft: Equatable {
    var name: String
    var phone: String
    /// True when this is an edit of a contact the user already has, which makes
    /// the sheet rename the device contact instead of adding a second one.
    var isExisting: Bool
    /// Whether this number has a Waangu account, when that is known. The sheet
    /// says "not on Waangu" only for `false`: unknown says nothing, rather than
    /// telling someone their chat partner is not on the app.
    var isOnWaangu: Bool?

    init(name: String, phone: String, isExisting: Bool, isOnWaangu: Bool? = nil) {
        self.name = name
        self.phone = phone
        self.isExisting = isExisting
        self.isOnWaangu = isOnWaangu
    }

    /// A Waangu user the person is already chatting with.
    init(user: UserContactProps) {
        self.init(name: user.name, phone: user.phone, isExisting: true, isOnWaangu: true)
    }
}

struct NewContactView: View {
    @Environment(\.dismiss) private var dismiss

    private let draft: ContactDraft?

    @State private var firstName: String = ""
    @State private var lastName: String = ""

    @State private var selectedCountry: Country
    @State private var showCountryPicker = false

    @State private var phone: String = ""
    @State private var isSaving = false
    @State private var phoneSyncError: String?
    let translationService: (any TranslationServiceProtocol)?

    init(
        draft: ContactDraft? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.translationService = translationService
        self.draft = draft

        // Split the stored E.164 number back into country + national parts.
        // Seeding the field with the full number instead would re-prefix the
        // dial code on save and corrupt it a little more on every edit.
        let split = Country.split(draft?.phone ?? "")
        _selectedCountry = State(initialValue: split.country)
        _phone = State(initialValue: split.nationalNumber)

        if let draft {
            let parts = draft.name.split(separator: " ", maxSplits: 1)
            _firstName = State(initialValue: String(parts.first ?? ""))
            _lastName = State(initialValue: parts.count > 1 ? String(parts[1]) : "")
        }
    }

    private var isEditing: Bool { draft?.isExisting == true }

    var isDoneEnabled: Bool {
        !firstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !isSaving
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 18) {
                    avatar()
                        .padding(.top, 8)
                        .staggeredAppear(0)

                    // MARK: - Names
                    VStack(spacing: 0) {
                        ClearableField(
                            symbol: "person.fill",
                            title: t(ChatTranslationKeys.NEW_CONTACT_FIRST_NAME),
                            clearAccessibilityLabel: t(ChatTranslationKeys.ACCESSIBILITY_CLEAR_FIELD, args: [t(ChatTranslationKeys.NEW_CONTACT_FIRST_NAME)]),
                            text: $firstName
                        )
                        Divider().padding(.leading, 50)
                        ClearableField(
                            symbol: nil,
                            title: t(ChatTranslationKeys.NEW_CONTACT_LAST_NAME),
                            clearAccessibilityLabel: t(ChatTranslationKeys.ACCESSIBILITY_CLEAR_FIELD, args: [t(ChatTranslationKeys.NEW_CONTACT_LAST_NAME)]),
                            text: $lastName
                        )
                    }
                    .contactCard()
                    .staggeredAppear(1)

                    // MARK: - Phone
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t(ChatTranslationKeys.NEW_CONTACT_PHONE))
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)

                        VStack(spacing: 0) {
                            Button {
                                showCountryPicker = true
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(AppColors.primary)
                                        .frame(width: 22)
                                    Text(selectedCountry.name)
                                        .foregroundStyle(.primary)
                                        .lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(selectedCountry.dialCode)
                                        .font(.subheadline.weight(.semibold))
                                        .monospacedDigit()
                                        .foregroundStyle(AppColors.primary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(AppColors.primary.opacity(0.12), in: Capsule())
                                    Image(systemName: "chevron.right")
                                        .font(.footnote.weight(.semibold))
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .frame(height: 52)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(t(ChatTranslationKeys.NEW_CONTACT_SELECT_COUNTRY))

                            Divider().padding(.leading, 50)

                            HStack(spacing: 12) {
                                Image(systemName: "phone.fill")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(AppColors.primary)
                                    .frame(width: 22)
                                    .accessibilityHidden(true)
                                Text(selectedCountry.dialCode)
                                    .font(.title3.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                TextField(t(ChatTranslationKeys.NEW_CONTACT_PHONE), text: $phone)
                                    .keyboardType(.numberPad)
                                    .textContentType(.telephoneNumber)
                                    .font(.title3.weight(.medium))
                                    .monospacedDigit()
                            }
                            .padding(.horizontal, 16)
                            .frame(height: 58)
                        }
                        .contactCard()
                    }
                    .staggeredAppear(2)

                    // MARK: - Not on Waangu
                    if draft?.isOnWaangu == false {
                    HStack(alignment: .center, spacing: 14) {
                        ChatSymbolBadge(symbol: "person.badge.plus", size: 40)

                        VStack(alignment: .leading, spacing: 8) {
                            Text(t(ChatTranslationKeys.NEW_CONTACT_NOT_ON_WAANGU))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Button {
                                // action d’invitation
                            } label: {
                                Text(t(ChatTranslationKeys.NEW_CONTACT_INVITE_TO_WAANGU))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(AppColors.primary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(16)
                    .contactCard()
                    .staggeredAppear(3)
                    }

                    // Contacts live in the device address book — the Waangu list is
                    // a synced mirror of it — so saving here writes there.
                    Label {
                        Text(t(ChatTranslationKeys.NEW_CONTACT_SAVED_TO_PHONE_NOTE))
                    } icon: {
                        Image(systemName: "iphone")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .staggeredAppear(4)

                    Spacer(minLength: 20)
                }
                .padding(.horizontal, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            // The same soft wash of the app blue behind the top as the create forms.
            .background(alignment: .top) {
                LinearGradient(
                    colors: [AppColors.primary.opacity(0.12), AppColors.primary.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
                .allowsHitTesting(false)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(common("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .principal) {
                    Text(isEditing ? t(ChatTranslationKeys.NEW_CONTACT_EDIT_TITLE) : t(ChatTranslationKeys.NEW_CONTACT_CREATE_TITLE)).font(.headline)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button(common("done")) { save() }
                            .disabled(!isDoneEnabled)
                    }
                }
            }
            .chatAppearanceSheet(isPresented: $showCountryPicker) {
                CountryPickerView(
                    selected: $selectedCountry,
                    translationService: translationService
                )
            }
            .alert(t(ChatTranslationKeys.NEW_CONTACT_SAVE_ERROR), isPresented: .init(
                get: { phoneSyncError != nil },
                set: { if !$0 { phoneSyncError = nil } }
            )) {
                Button(common("ok"), role: .cancel) { phoneSyncError = nil }
            } message: {
                Text(phoneSyncError ?? "")
            }
            .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        }
    }

    /// The contact's initials on the app blue, following the name as it is typed.
    private func avatar() -> some View {
        let size: CGFloat = 96
        let name = "\(firstName) \(lastName)"
        return Circle()
            .fill(
                LinearGradient(
                    colors: [AppColors.centerGradientStart, AppColors.primary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                if let initials = ProfileEditView.initials(of: name) {
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .contentTransition(.numericText())
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
            .shadow(color: AppColors.primary.opacity(0.22), radius: 14, y: 6)
            .animation(.easeOut(duration: 0.2), value: ProfileEditView.initials(of: name))
            .accessibilityHidden(true)
    }

    /// Writes the contact to the device address book — renaming the existing
    /// entry when editing rather than leaving a duplicate behind — then asks the
    /// app to re-sync so the new name shows up in chat lists.
    private func save() {
        isSaving = true
        Task {
            defer { Task { @MainActor in isSaving = false } }

            do {
                try await DeviceContactWriter.saveContact(
                    givenName: firstName,
                    familyName: lastName,
                    nationalNumber: phone.filter(\.isNumber),
                    countryDialCode: selectedCountry.dialCode,
                    replacingExistingNumber: isEditing
                )
            } catch {
                await MainActor.run { phoneSyncError = error.localizedDescription }
                return
            }

            await MainActor.run {
                NotificationCenter.default.post(name: .contactsShouldRefresh, object: nil)
                dismiss()
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Clearable textfield (style WhatsApp)
/// One row of the names card: an optional icon, the field, and a clear button.
/// The card around the rows draws the background.
private struct ClearableField: View {
    var symbol: String?
    var title: String
    var clearAccessibilityLabel: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColors.primary)
                } else {
                    Color.clear
                }
            }
            .frame(width: 22)
            .accessibilityHidden(true)

            TextField(title, text: $text)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(.tertiaryLabel)
                }
                .accessibilityLabel(clearAccessibilityLabel)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
}

private extension View {
    /// The rounded card every group on this sheet sits in.
    func contactCard() -> some View {
        background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

// MARK: - Country model & picker
struct Country: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let dialCode: String
}

extension Country {
    static let supported: [Country] = [
        .init(name: "Burundi", dialCode: "+257"),
        .init(name: "Congo - Kinshasa", dialCode: "+243"),
        .init(name: "Rwanda", dialCode: "+250"),
        .init(name: "Tanzania", dialCode: "+255"),
        .init(name: "Uganda", dialCode: "+256"),
    ]

    static let fallback = Country(name: "Congo - Kinshasa", dialCode: "+243")

    /// Stand-in for a number whose country code isn't in `supported`. Its empty
    /// dial code means a save re-emits exactly the digits it was given instead
    /// of prefixing someone else's country onto them.
    static let unknown = Country(name: "—", dialCode: "+")

    /// Splits a stored number back into the country the picker should show and
    /// the national digits the field should hold.
    ///
    /// Matched longest-dial-code-first against the list the picker itself
    /// offers, so every number this screen can produce it can also read back.
    static func split(_ phoneNumber: String) -> (country: Country, nationalNumber: String) {
        let digits = phoneNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return (fallback, "") }

        let byLongestCode = supported.sorted {
            $0.dialCode.count > $1.dialCode.count
        }

        for country in byLongestCode {
            let code = country.dialCode.filter(\.isNumber)
            if digits.hasPrefix(code) {
                return (country, String(digits.dropFirst(code.count)))
            }
        }

        // An explicit +code we don't stock: keep every digit and carry no dial
        // code, so saving round-trips the number unchanged. A number with no +
        // is already national, so it pairs with the default country.
        return phoneNumber.hasPrefix("+") ? (unknown, digits) : (fallback, digits)
    }
}

struct CountryPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var selected: Country
    @State private var query = ""
    let translationService: (any TranslationServiceProtocol)?

    init(
        selected: Binding<Country>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._selected = selected
        self.translationService = translationService
    }

    var filtered: [Country] {
        guard !query.isEmpty else { return Country.supported }
        return Country.supported.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.dialCode.contains(query) }
    }
    
    var body: some View {
        NavigationView {
            List {
                ForEach(filtered) { country in
                    Button {
                        selected = country
                        dismiss()
                    } label: {
                        HStack {
                            Text(country.name)
                            Spacer()
                            Text(country.dialCode)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle(t(ChatTranslationKeys.NEW_CONTACT_SELECT_COUNTRY))
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(common("cancel")) { dismiss() }
                }
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Helpers (UIKit colors)
extension Color {
    static var tertiaryLabel: Color { Color(UIColor.tertiaryLabel) }
}


