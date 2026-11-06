import SwiftUI

// MARK: - Field Type

public enum TextFieldType {
    case standard
    case secure
    case search
    case phone
    case multiline
    case amount
}

// MARK: - AppTextField

public struct CustomTextField: View {
    let label: String
    var placeholder: String = ""
    var type: TextFieldType = .standard
    var leadingIcon: String? = nil
    var errorMessage: String? = nil
    var characterLimit: Int? = nil
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isDisabled: Bool = false
    var phoneCode: String = "+254"
    /// Couleur de l'erreur. Rouge par défaut ; la finance passe la couleur
    /// principale, selon sa règle d'une seule couleur.
    var errorTint: Color = .appError
    @Binding var text: String
    @State private var isSecureVisible = false
    @FocusState private var isFocused: Bool

    private var hasError: Bool { errorMessage != nil }

    private var borderColor: Color {
        if hasError { return errorTint }
        if isFocused { return .brandPrimary }
        return .appBorder
    }
    
    // MARK: - Public Initializer
    public init(
        label: String,
        placeholder: String = "",
        type: TextFieldType = .standard,
        leadingIcon: String? = nil,
        errorMessage: String? = nil,
        characterLimit: Int? = nil,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences,
        isDisabled: Bool = false,
        phoneCode: String = "+254",
        errorTint: Color = .appError,
        text: Binding<String>
    ) {
        self.label = label
        self.placeholder = placeholder
        self.type = type
        self.leadingIcon = leadingIcon
        self.errorMessage = errorMessage
        self.characterLimit = characterLimit
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.isDisabled = isDisabled
        self.phoneCode = phoneCode
        self.errorTint = errorTint
        self._text = text
    }

   

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            // Label
            if !label.isEmpty {
                Text(label)
                    .font(.appInputLabel)
                    .foregroundStyle(hasError ? errorTint : Color.brandPrimary)
                    .padding(.leading, 10)
            }

            // Input row
            Group {
                switch type {
                case .multiline:
                    multilineField
                default:
                    singleLineField
                }
            }

            // Footer: error or character count
            HStack {
                if let errorMessage {
                    Text(errorMessage)
                        .font(.appInputError)
                        .foregroundStyle(errorTint)
                }
                Spacer()
                if let limit = characterLimit, type == .multiline {
                    Text("\(text.count)/\(limit)")
                        .font(.appCaption2)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.5 : 1.0)
    }

    // MARK: - Single Line

    private var singleLineField: some View {
        HStack(spacing: AppSpacing.xs) {
            // Leading icon or phone code
            if type == .phone {
                Text(phoneCode)
                    .font(.appInputText)
                    .foregroundStyle(Color.appText)
                Divider().frame(height: 20)
            } else if type == .search {
                Image(systemName: AppIcons.search)
                    .foregroundStyle(Color.appPlaceholder)
            } else if let leadingIcon {
                Image(systemName: leadingIcon)
                    .foregroundStyle(Color.appPlaceholder)
            }

            // Text input
            if type == .secure && !isSecureVisible {
                SecureField(placeholder, text: $text)
                    .font(.appInputText)
                    .focused($isFocused)
            } else {
                TextField(placeholder, text: $text)
                    .font(.appInputText)
                    .focused($isFocused)
                    .keyboardType(type == .phone || type == .amount ? .phonePad : keyboardType)
                    .textInputAutocapitalization(type == .search ? .never : autocapitalization)
                    .onChange(of: text) { oldValue, newValue in
                        if type == .amount {
                            handleAmountChange(oldValue: oldValue, newValue: newValue)
                        }
                    }
            }

            // Trailing actions
            if type == .secure {
                Button {
                    isSecureVisible.toggle()
                } label: {
                    Image(systemName: isSecureVisible ? AppIcons.eyeOpen : AppIcons.eyeClosed)
                        .foregroundStyle(Color.appSecondaryText)
                }
            } else if type == .search && !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: AppIcons.close)
                        .font(.caption)
                        .foregroundStyle(Color.appSecondaryText)
                        .padding(4)
                        .background(Circle().fill(Color(.systemGray5)))
                }
            }
        }
        .padding(.horizontal, AppSpacing.sm)
        .frame(height: 48)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.md)
                .stroke(borderColor, lineWidth: isFocused || hasError ? 1.5 : 1)
        )
    }

    // MARK: - Multiline

    private var multilineField: some View {
        TextEditor(text: $text)
            .font(.appInputText)
            .focused($isFocused)
            .frame(minHeight: 100, maxHeight: 200)
            .scrollContentBackground(.hidden)
            .padding(AppSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.md)
                    .stroke(borderColor, lineWidth: isFocused || hasError ? 1.5 : 1)
            )
            .onChange(of: text) { _, newValue in
                if let limit = characterLimit, newValue.count > limit {
                    text = String(newValue.prefix(limit))
                }
            }
    }

    // MARK: - Amount Logic

    private func handleAmountChange(oldValue: String, newValue: String) {
        // Remove all non-digits
        let clean = newValue.filter { $0.isNumber }
        
        // Convert to number to remove leading zeros if any, then back to string
        if let number = Int(clean) {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.groupingSeparator = " "
            
            if let formatted = formatter.string(from: NSNumber(value: number)) {
                if formatted != newValue {
                    text = formatted
                }
            }
        } else if clean.isEmpty {
            text = ""
        }
    }
}

// MARK: - OTP Field

struct OTPField: View {
    let length: Int
    @Binding var code: String
    var onComplete: ((String) -> Void)? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        ZStack {
            // Hidden input to capture keyboard
            TextField("", text: $code)
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .focused($isFocused)
                .frame(width: 0, height: 0)
                .opacity(0)
                .onChange(of: code) { _, newValue in
                    let filtered = String(newValue.prefix(length)).filter(\.isNumber)
                    if filtered != code { code = filtered }
                    if filtered.count == length { onComplete?(filtered) }
                }

            // Digit boxes
            HStack(spacing: AppSpacing.sm) {
                ForEach(0..<length, id: \.self) { index in
                    let digit = index < code.count
                        ? String(code[code.index(code.startIndex, offsetBy: index)])
                        : ""

                    Text(digit)
                        .font(.appTitle2)
                        .frame(width: 48, height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: AppCornerRadius.md)
                                .stroke(
                                    index == code.count && isFocused
                                        ? Color.brandPrimary
                                        : Color.appBorder,
                                    lineWidth: index == code.count && isFocused ? 2 : 1
                                )
                        )
                }
            }
            .onTapGesture { isFocused = true }
        }
    }
}

// MARK: - Previews

#Preview("Text Fields") {
    ScrollView {
        VStack(spacing: 20) {
            CustomTextField(label: "Full Name", placeholder: "Enter your name", text: .constant(""))

            CustomTextField(label: "Email", placeholder: "email@example.com", leadingIcon: AppIcons.email, keyboardType: .emailAddress, text: .constant(""))

            CustomTextField(label: "Password", placeholder: "Enter password", type: .secure, text: .constant("secret"))

            CustomTextField(label: "Phone", placeholder: "712 345 678", type: .phone, text: .constant(""))

            CustomTextField(label: "Search", placeholder: "Search...", type: .search, text: .constant("query"))

            CustomTextField(label: "Bio", placeholder: "Tell us about yourself", type: .multiline, characterLimit: 200, text: .constant("Hello world"))

            CustomTextField(label: "Error field", placeholder: "Oops", errorMessage: "This field is required", text: .constant(""))

            VStack(alignment: .leading) {
                Text("OTP Code").font(.appInputLabel)
                OTPField(length: 6, code: .constant("123"))
            }
        }
        .padding()
    }
}
