//import SwiftUI
//
//struct MenuSelectionFieldLabel: View {
//    let text: String
//    var isPlaceholder: Bool = false
//
//    var body: some View {
//        HStack {
//            Text(text)
//                .font(.system(size: 16))
//                .foregroundColor(isPlaceholder ? AppColors.iconLabel.opacity(0.5) : AppColors.iconLabel)
//
//            Spacer()
//
//            Image(systemName: "chevron.down")
//                .font(.system(size: 14, weight: .semibold))
//                .foregroundColor(AppColors.iconLabel.opacity(0.4))
//        }
//        .padding(.horizontal, 16)
//        .padding(.vertical, 14)
//        .background(
//            RoundedRectangle(cornerRadius: 12, style: .continuous)
//                .fill(AppColors.cardBackground)
//        )
//        .overlay(
//            RoundedRectangle(cornerRadius: 12, style: .continuous)
//                .stroke(AppColors.iconLabel.opacity(0.2), lineWidth: 1)
//        )
//    }
//}
