//import SwiftUI
//
//struct TermsCheckboxView: View {
//    @Binding var isAccepted: Bool
//    let leadingText: String
//    let linkText: String
//    var onLinkTap: (() -> Void)? = nil
//
//    var body: some View {
//        HStack(alignment: .top, spacing: 12) {
//            Button {
//                isAccepted.toggle()
//            } label: {
//                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
//                    .font(.system(size: 22))
//                    .foregroundColor(isAccepted ? .brandPrimary : Color.appSecondaryText)
//            }
//            .buttonStyle(.plain)
//
//            HStack(spacing: 4) {
//                Text(leadingText)
//                    .font(.appBody)
//                    .foregroundStyle(Color.appText)
//
//                Button(linkText) {
//                    onLinkTap?()
//                }
//                .font(.system(size: 15, weight: .medium))
//                .foregroundColor(.brandPrimary)
//                .underline()
//            }
//
//            Spacer(minLength: 0)
//        }
//    }
//}
