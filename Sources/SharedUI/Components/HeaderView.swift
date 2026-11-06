

import SwiftUI

public struct HeaderView: View {
    
  public enum TapAction {
        case notification
        case profile
        case country
        case chat
        case qrCode
    }
    
    let avatar : String?
    var notificationBadgeCount: Int?
    var onTap: ((TapAction) -> Void)

    public init(
        avatar : String?,
        notificationBadgeCount: Int? = nil,
        onTap: @escaping ((TapAction) -> Void)
    ) {
        self.notificationBadgeCount = notificationBadgeCount
        self.avatar = avatar
        self.onTap = onTap
    }

    public var body: some View {
        headerView
    }
    
    // MARK: - Header custom
    private var headerView: some View {
        HStack(spacing: 0) {

            // MARK: Avatar + séparateur + pays
            HStack(spacing: 10) {
                Button(action: {
                    onTap(.profile)
                }) {
                    
                    RemoteImage(
                        urlString: avatar,
                        contentMode: .fit,
                        size: CGSize(width: 40, height: 40),
                        placeholder: {
                            Color.gray.opacity(0.15)
                        },
                        fallback: {
                            ZStack {
                                Color.gray.opacity(0.1)
                                Image(systemName: "person.fill")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    )
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 3))
                }
                .buttonStyle(.plain)

                // Séparateur vertical
                Rectangle()
                    .fill(Color.gray.opacity(0.4))
                    .frame(width: 1.5, height: 34)
                Button(action: {
                    onTap(.country)
                }){
                    HStack(spacing:4){
                        Text("🇧🇮")
                            .font(.system(size: 25, weight: .semibold))
                
                        Text("Bujumbura")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColors.white)
                            .lineLimit(1)
                        
                         Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .font(.caption2)
                            .foregroundStyle(AppColors.white)
                    }
                    
                }.buttonStyle(.plain)
            
                
            }

            Spacer()

            // MARK: Actions droite
            HStack(spacing: 16) {
                headerActionButton(icon: "qrcode.viewfinder") {
                    onTap(.qrCode)
                }
                
                headerActionButton(icon: "bubble.left") {
                    onTap(.chat)
                }
                
                headerActionButton(icon: "bell") {
                    onTap(.notification)
                }
                .overlay(alignment: .topTrailing) {
                    if let badge = notificationBadgeCount {
                        Text(badge > 99 ? "99+" : "\(badge)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, (badge > 9 && badge <= 99) ? 4 : 0)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Capsule().fill(Color.red))
                            .offset(x: 10, y: -10)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(AppColors.primary)  // même couleur que le scrollview
    }

    // MARK: - Helper bouton
    private func headerActionButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(AppColors.white)
                .frame(width: 25, height: 25)
        }
    }
}

#Preview {
    HeaderPreviewWrapper()
}

private struct HeaderPreviewWrapper: View {
    @State private var showScanner = false

    var body: some View {
        VStack{
            Text("ffrf")
            Spacer()
        }  .safeAreaInset(edge: .top) {
            HeaderView(
                avatar: "",
                notificationBadgeCount: 3
            ){ action in
            
            }
            .background(Color.black) // pour voir le contraste
            .previewLayout(.sizeThatFits)
        }
      
    }
}
