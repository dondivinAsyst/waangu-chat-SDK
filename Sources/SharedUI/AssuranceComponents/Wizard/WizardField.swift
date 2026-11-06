import SwiftUI

// MARK: - WizardField

/// Declarative field definition that auto-generates its UI, validation, and review items.
public struct WizardField: Identifiable {
    public var id: String { key }

    let key: String
    let label: String
    let isRequired: Bool
    let reviewLabel: String?
    let kind: Kind

    enum Kind {
        case text(
            placeholder: String = "",
            leadingIcon: String? = nil,
            keyboard: UIKeyboardType = .default,
            autocap: TextInputAutocapitalization = .sentences
        )
        case phone(placeholder: String = "", phoneCode: String = "+257")
        case multiline(placeholder: String = "", characterLimit: Int? = nil)
        case dropdown(
            placeholder: String = "Sélectionnez...",
            options: [DropdownOption],
            isMulti: Bool = false
        )
        case date(isSetKey: String)
        case toggle(subtitle: String? = nil)
        case media(maxCount: Int = 5)
        case amount(placeholder: String = "")
    }
}

// MARK: - Factory Methods

public extension WizardField {

    static func text(
        _ key: String,
        label: String,
        placeholder: String = "",
        leadingIcon: String? = nil,
        required: Bool = true,
        keyboard: UIKeyboardType = .default,
        autocap: TextInputAutocapitalization = .sentences,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .text(placeholder: placeholder, leadingIcon: leadingIcon,
                          keyboard: keyboard, autocap: autocap))
    }

    static func email(
        _ key: String,
        label: String,
        placeholder: String = "exemple@email.com",
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .text(placeholder: placeholder, leadingIcon: AppIcons.email,
                          keyboard: .emailAddress, autocap: .never))
    }

    static func phone(
        _ key: String,
        label: String,
        placeholder: String = "",
        phoneCode: String = "+257",
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .phone(placeholder: placeholder, phoneCode: phoneCode))
    }

    static func multiline(
        _ key: String,
        label: String,
        placeholder: String = "",
        characterLimit: Int? = nil,
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .multiline(placeholder: placeholder, characterLimit: characterLimit))
    }

    static func dropdown(
        _ key: String,
        label: String,
        placeholder: String = "Sélectionnez...",
        options: [DropdownOption],
        isMulti: Bool = false,
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .dropdown(placeholder: placeholder, options: options, isMulti: isMulti))
    }

    static func date(
        _ key: String,
        label: String,
        isSetKey: String,
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .date(isSetKey: isSetKey))
    }

    static func toggle(
        _ key: String,
        label: String,
        subtitle: String? = nil,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: false, reviewLabel: reviewLabel,
              kind: .toggle(subtitle: subtitle))
    }

    static func media(
        _ key: String,
        label: String,
        maxCount: Int = 5,
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .media(maxCount: maxCount))
    }

    static func amount(
        _ key: String,
        label: String,
        placeholder: String = "",
        required: Bool = true,
        reviewLabel: String? = nil
    ) -> WizardField {
        .init(key: key, label: label, isRequired: required, reviewLabel: reviewLabel,
              kind: .amount(placeholder: placeholder))
    }
}


// MARK: - Derived Labels

extension WizardField {

    var displayLabel: String {
        isRequired ? "\(label)*" : label
    }

    var effectiveReviewLabel: String {
        reviewLabel ?? label
    }
}

// MARK: - View Rendering

extension WizardField {

    @ViewBuilder
 public   func makeView(
        formState: Binding<WizardFormState>,
        errors: [WizardValidationResult]
    ) -> some View {
        let errorMsg = errors.errorMessage(for: key)

        switch kind {
        case .text(let placeholder, let icon, let keyboard, let autocap):
            CustomTextField(
                label: displayLabel,
                placeholder: placeholder,
                leadingIcon: icon,
                errorMessage: errorMsg,
                keyboardType: keyboard,
                autocapitalization: autocap,
                text: formState.string(for: key)
            )
            .id(key)

        case .phone(let placeholder, let code):
            CustomTextField(
                label: displayLabel,
                placeholder: placeholder,
                type: .phone,
                errorMessage: errorMsg,
                keyboardType: .phonePad,
                phoneCode: code,
                text: formState.string(for: key)
            )
            .id(key)

        case .multiline(let placeholder, let limit):
            CustomTextField(
                label: displayLabel,
                placeholder: placeholder,
                type: .multiline,
                errorMessage: errorMsg,
                characterLimit: limit,
                text: formState.string(for: key)
            )
            .id(key)

        case .dropdown(let placeholder, let options, let isMulti):
            SelectDropdown(
                options: options,
                label: displayLabel,
                placeholder: placeholder,
                isMulti: isMulti,
                errorMessage: errorMsg,
                selected: formState.stringArray(for: key)
            )
            .id(key)

        case .date(let isSetKey):
            DateField(
                label: displayLabel,
                errorMessage: errorMsg,
                date: formState.date(for: key),
                isSet: formState.bool(for: isSetKey)
            )
            .id(key)

        case .toggle(let subtitle):
            toggleView(formState: formState, subtitle: subtitle, errorMsg: errorMsg)
                .id(key)

        case .media(let maxCount):
            MediaUploadField(
                label: displayLabel,
                maxCount: maxCount,
                errorMessage: errorMsg,
                paths: formState.stringArray(for: key)
            )
            .id(key)

        case .amount(let placeholder):
            CustomTextField(
                label: displayLabel,
                placeholder: placeholder,
                type: .amount,
                errorMessage: errorMsg,
                keyboardType: .numberPad,
                text: formState.string(for: key)
            )
            .id(key)
        }
    }

    @ViewBuilder
    private func toggleView(
        formState: Binding<WizardFormState>,
        subtitle: String?,
        errorMsg: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Toggle(isOn: formState.bool(for: key)) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.appBody)
                        .foregroundStyle(Color.appText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appCaption1)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }
            }
            .tint(Color.brandPrimary)

            if let errorMsg {
                Text(errorMsg)
                    .font(.appInputError)
                    .foregroundStyle(Color.appError)
            }
        }
    }
}

// MARK: - Validation

extension WizardField {

  public  func validate(state: WizardFormState) -> WizardValidationResult? {
        switch kind {
        case .text(_, _, let kb, _):
            let value = state.string(key).trimmingCharacters(in: .whitespaces)
            if isRequired && value.isEmpty {
                return .invalid(field: key, message: "\(label) est requis")
            }
            if kb == .emailAddress && !value.isEmpty
                && (!value.contains("@") || !value.contains(".")) {
                return .invalid(field: key, message: "\(label) n'est pas valide")
            }

        case .phone, .multiline:
            if isRequired && state.string(key).trimmingCharacters(in: .whitespaces).isEmpty {
                return .invalid(field: key, message: "\(label) est requis")
            }

        case .dropdown:
            if isRequired && state.stringArray(key).isEmpty {
                return .invalid(field: key, message: "\(label) est requis")
            }

        case .date(let isSetKey):
            if isRequired && !state.bool(isSetKey) {
                return .invalid(field: key, message: "\(label) est requis")
            }

        case .toggle:
            return nil

        case .media:
            if isRequired && state.stringArray(key).isEmpty {
                return .invalid(field: key, message: "\(label) est requis")
            }
        case .amount:
            if isRequired && state.string(key).trimmingCharacters(in: .whitespaces).isEmpty {
                return .invalid(field: key, message: "\(label) est requis")
            }
        }
        return nil
    }
}

// MARK: - Review Item

extension WizardField {

    func reviewItem(state: WizardFormState, stepID: String) -> WizardReviewItem? {
        let rlabel = effectiveReviewLabel

        switch kind {
        case .text, .phone, .multiline:
            let value = state.string(key)
            if value.isEmpty && !isRequired { return nil }
            return WizardReviewItem(label: rlabel, value: value, stepID: stepID)

        case .dropdown(_, let options, _):
            let ids = state.stringArray(key)
            if ids.isEmpty && !isRequired { return nil }
            let value = ids.compactMap { id in
                options.first(where: { $0.id == id })?.label
            }.joined(separator: ", ")
            return WizardReviewItem(label: rlabel, value: value.isEmpty ? "—" : value, stepID: stepID)

        case .date(let isSetKey):
            guard state.bool(isSetKey), let date = state.date(key) else {
                return isRequired
                    ? WizardReviewItem(label: rlabel, value: "—", stepID: stepID)
                    : nil
            }
            let df = DateFormatter()
            df.dateStyle = .medium
            df.locale = Locale(identifier: "fr_BI")
            return WizardReviewItem(label: rlabel, value: df.string(from: date), stepID: stepID)

        case .toggle:
            let value = state.bool(key) ? "Oui" : "Non"
            return WizardReviewItem(label: rlabel, value: value, stepID: stepID)

        case .media:
            let count = state.stringArray(key).count
            let value = count == 0 ? "Aucune photo" : "\(count) photo(s)"
            return WizardReviewItem(label: rlabel, value: value, stepID: stepID)
        case .amount:
            let value = state.string(key)
            if value.isEmpty && !isRequired { return nil }
            return WizardReviewItem(label: rlabel, value: value.isEmpty ? "—" : value, stepID: stepID)
        }
    }
}
