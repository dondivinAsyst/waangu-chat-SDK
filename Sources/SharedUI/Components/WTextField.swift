// MARK: - SharedUI/Components/WTextField.swift

import SwiftUI

public struct WTextField: View {
    public var disabled: Bool
    public var label: String
    @Binding public var text: String
    public var error: String?
    public var isSecure: Bool
    @State private var isHidden = true

    public init(
        label: String,
        text: Binding<String>,
        disabled: Bool = false,
        error: String? = nil,
        isSecure: Bool = false
    ) {
        self.label = label
        self._text = text
        self.disabled = disabled
        self.error = error
        self.isSecure = isSecure
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            HStack {
                if isSecure && isHidden {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                }

                if isSecure {
                    Button { isHidden.toggle() } label: {
                        Image(systemName: isHidden ? "eye.slash" : "eye")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding()
            .frame(height: 56)
            .background(Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(error == nil || error!.isEmpty ? Color.clear : Color.red, lineWidth: 1)
            )
            .cornerRadius(10)
            .disabled(disabled)

            if let error = error, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }
}
