//
//  CallAddParticipantSheet.swift
//  FeatureChat
//
//  Invites more people into an already-running call.
//
//  Contact loading, search, the row layout and the selected-avatars strip all
//  come from the existing chat partner picker — only the confirm action differs,
//  which is why this is a thin shell rather than another picker.
//
//  Selection is held locally on purpose: `ChatPartnerPickerViewModel` is a
//  shared instance, and writing to its `selectedChatPartners` would leak this
//  call's picks into the group-creation flow.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct CallAddParticipantSheet: View {

    @ObservedObject var pickerViewModel: ChatPartnerPickerViewModel
    @Environment(\.dismiss) private var dismiss

    /// Digits-only phones of the remotes currently on the call, so they are not
    /// offered again. Shrinks as people leave — someone who dropped out
    /// reappears here and can be called back.
    let alreadyInCall: Set<String>
    /// How many seats the call already occupies, this device included.
    /// Not derived from `alreadyInCall`, which holds remotes only.
    let occupiedSlots: Int
    let maxParticipants: Int
    let translationService: (any TranslationServiceProtocol)?

    var onConfirm: ([UserContactProps]) -> Void

    @State private var selected: [UserContactProps] = []
    @State private var searchText = ""

    /// Contacts that are not already on the call.
    private var invitableUsers: [UserContactProps] {
        pickerViewModel.waanguUsers.filter { !alreadyInCall.contains($0.phone.onlyDigits) }
    }

    private var remainingSlots: Int {
        max(0, maxParticipants - occupiedSlots - selected.count)
    }

    var body: some View {
        NavigationView {
            List {
                if !selected.isEmpty {
                    SelectedChatPartnerView(users: selected) { user in
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            toggle(user)
                        }
                    }
                }

                Section {
                    if invitableUsers.isEmpty {
                        emptyState
                    } else {
                        ForEach(invitableUsers) { user in
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    toggle(user)
                                }
                            } label: {
                                row(user)
                            }
                            .buttonStyle(.plain)
                            .disabled(!isSelected(user) && remainingSlots == 0)
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: selected.count)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: t(ChatTranslationKeys.CALLS_SEARCH_CONTACTS)
            )
            .onChange(of: searchText) { _, text in
                pickerViewModel.searchContacts(text)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { title }
                ToolbarItem(placement: .topBarLeading) {
                    Button(common("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t(ChatTranslationKeys.CALLS_ADD)) {
                        onConfirm(selected)
                        dismiss()
                    }
                    .bold()
                    .disabled(selected.isEmpty)
                }
            }
        }
        // The picker view model is shared, and `searchContacts` filters its
        // published list in place — clear the filter so the next screen that
        // observes it does not inherit this sheet's search.
        .onDisappear { pickerViewModel.searchContacts("") }
    }

    // MARK: - Pieces

    private var title: some View {
        VStack(spacing: 1) {
            Text(t(ChatTranslationKeys.CALLS_ADD_PARTICIPANT_TITLE))
                .font(.system(size: 16, weight: .semibold))

            Text(t(
                ChatTranslationKeys.CALLS_PARTICIPANTS_SELECTED,
                args: ["\(occupiedSlots + selected.count)", "\(maxParticipants)"]
            ))
            .font(.footnote)
            .foregroundStyle(.gray)
        }
    }

    private func row(_ user: UserContactProps) -> some View {
        ChatPartnerRowView(user: user) {
            Spacer()

            let isOn = isSelected(user)

            ZStack {
                Circle()
                    .stroke(isOn ? AppColors.primary : Color(.systemGray4), lineWidth: 2)
                    .frame(width: 24, height: 24)

                if isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isOn)
        }
        .contentShape(Rectangle())
    }

    private var emptyState: some View {
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

    // MARK: - Selection

    private func isSelected(_ user: UserContactProps) -> Bool {
        selected.contains { $0.phone.onlyDigits == user.phone.onlyDigits }
    }

    private func toggle(_ user: UserContactProps) {
        if let index = selected.firstIndex(where: { $0.phone.onlyDigits == user.phone.onlyDigits }) {
            selected.remove(at: index)
        } else if remainingSlots > 0 {
            selected.append(user)
        }
    }

    // MARK: - Localisation

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
