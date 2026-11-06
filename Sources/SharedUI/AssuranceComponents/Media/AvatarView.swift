import SwiftUI

// MARK: - AvatarView

struct AvatarView: View {
    var imageURL: URL? = nil
    var initials: String = ""
    var size: CGFloat = 44
    var backgroundColor: Color = .brandPrimary.opacity(0.15)
    var foregroundColor: Color = .brandPrimary

    private var fontSize: CGFloat { size * 0.38 }

    var body: some View {
        Group {
            if let imageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        initialsView
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(backgroundColor)
            if initials.isEmpty {
                Image(systemName: AppIcons.personFill)
                    .font(.system(size: fontSize))
                    .foregroundStyle(foregroundColor)
            } else {
                Text(initials.prefix(2).uppercased())
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundStyle(foregroundColor)
            }
        }
    }
}

#Preview("Avatar") {
    HStack(spacing: 16) {
        AvatarView(initials: "DD", size: 56)
        AvatarView(initials: "WC", size: 44, backgroundColor: .appSuccess.opacity(0.15), foregroundColor: .appSuccess)
        AvatarView(size: 36)
        AvatarView(imageURL: URL(string: "https://picsum.photos/100"), size: 48)
    }
    .padding()
}
