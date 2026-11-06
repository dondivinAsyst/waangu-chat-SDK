import SwiftUI

// MARK: - Rounded Top Corners Shape
// Declared ONCE here. Do not copy this into any other file.
public struct RoundedCornerShape: Shape {
    var radius: CGFloat
    var corners: UIRectCorner

    public init(radius: CGFloat, corners: UIRectCorner) {
        self.radius = radius
        self.corners = corners
    }

    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

// MARK: - Shared Input Field
public struct SharedInputField: View {
    var placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    public init(placeholder: String, text: Binding<String>, keyboardType: UIKeyboardType = .default) {
        self.placeholder = placeholder
        self._text = text
        self.keyboardType = keyboardType
    }

    public var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(keyboardType)
            .padding()
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(UIColor.systemGray4)))
    }
}

// MARK: - Shared Multiline Text Area
public struct SharedTextArea: View {
    var placeholder: String
    @Binding var text: String

    public init(placeholder: String, text: Binding<String>) {
        self.placeholder = placeholder
        self._text = text
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(Color.gray)
                    .padding(12)
            }
            TextEditor(text: $text)
                .frame(height: 100)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 6).stroke(Color(UIColor.systemGray4)))
        }
    }
}

// MARK: - Date Button (shows label and calendar icon)
public struct SharedDateFieldButton: View {
    var title: String
    var valueText: String
    var action: () -> Void

    public init(title: String, valueText: String, action: @escaping () -> Void) {
        self.title = title
        self.valueText = valueText
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack {
                Text(valueText)
                    .foregroundColor(valueText.isEmpty ? Color.gray : Color(UIColor.darkText))
                Spacer()
                Image(systemName: "calendar")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(RoundedRectangle(cornerRadius: 6).stroke(Color(UIColor.systemGray4)))
        }
    }
}

// MARK: - Primary Button
public struct SharedPrimaryButton: View {
    var title: String
    var action: () -> Void

    public init(title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primary)
                .cornerRadius(8)
        }
    }
}

// MARK: - Shared Radio Button
public struct SharedRadioButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(isSelected ? AppColors.primary : Color.gray, lineWidth: 2)
                        .frame(width: 22, height: 22)

                    if isSelected {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(title)
                    .foregroundColor(Color(UIColor.gray))
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
