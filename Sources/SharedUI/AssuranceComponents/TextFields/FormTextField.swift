//import SwiftUI
//
//struct FormTextField: View {
//    let label: String?
//    let placeholder: String
//    @Binding var text: String
//    var keyboardType: UIKeyboardType = .default
//
//    init(
//        placeholder: String,
//        text: Binding<String>,
//        label: String? = nil,
//        keyboardType: UIKeyboardType = .default
//    ) {
//        self.placeholder = placeholder
//        _text = text
//        self.label = label
//        self.keyboardType = keyboardType
//    }
//
//    var body: some View {
//        VStack(alignment: .leading, spacing: 10) {
//            if let label = label {
//                Text(label)
//                    .font(.system(size: 15, weight: .semibold))
//                    .foregroundColor(AppColors.iconLabel.opacity(0.9))
//            }
//            TextField(placeholder, text: $text)
//                .keyboardType(keyboardType)
//                .font(.system(size: 16))
//                .foregroundColor(AppColors.iconLabel)
//                .padding(.horizontal, 16)
//                .padding(.vertical, 14)
//                .background(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .fill(AppColors.cardBackground)
//                )
//                .overlay(
//                    RoundedRectangle(cornerRadius: 12, style: .continuous)
//                        .stroke(AppColors.iconLabel.opacity(0.2), lineWidth: 1)
//                )
//        }
//    }
//}
