//import SwiftUI
//
//struct InfoBannerView: View {
//    let message: String
//    var systemImage: String = "exclamationmark.triangle.fill"
//    var accentColor: Color = Color.orange.opacity(0.85)
//
//    private var iconBackgroundTint: Color {
//        accentColor.opacity(0.12)
//    }
//
//    var body: some View {
//        HStack(spacing: 14) {
//            Image(systemName: systemImage)
//                .font(.system(size: 20))
//                .foregroundColor(accentColor)
//                .frame(width: 36, height: 36)
//                .background(Circle().fill(iconBackgroundTint))
//
//            Text(message)
//                .font(.system(size: 15, weight: .medium))
//                .foregroundStyle(Color.appText)
//
//            Spacer(minLength: 0)
//        }
//        .padding(14)
//        .background(
//            RoundedRectangle(cornerRadius: 14, style: .continuous)
//                .fill(Color.appCard)
//                .overlay(
//                    RoundedRectangle(cornerRadius: 14, style: .continuous)
//                        .stroke(accentColor.opacity(0.35), lineWidth: 1)
//                )
//        )
//        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
//    }
//}
