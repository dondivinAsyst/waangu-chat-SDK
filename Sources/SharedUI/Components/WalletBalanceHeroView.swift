import SwiftUI
import Combine
import UIKit

public struct WalletBalanceHeroView: View {

    public init() {}
    @State private var selection: Int = 0
    private let timer = Timer.publish(every: 4, on: .main, in: .common).autoconnect()

    // Use these images as the first N slides
    private let images = ["https://d1csarkz8obe9u.cloudfront.net/posterpreviews/beauty-salon-banner-ad-design-template-8e88e6b1f2a8e8985f1bf573a05e1589_screen.jpg?ts=1734582038", "https://img.freepik.com/premium-psd/promotional-sales-web-banner-template-facebook-cover-post-template_550280-1938.jpg", "https://img.freepik.com/free-psd/3d-colorful-discount-sale-promotion-banner_125755-689.jpg"]

    public var body: some View {
        let total = images.count

        TabView(selection: $selection) {
            ForEach(images.indices, id: \.self) { idx in
                GeometryReader { geo in
                    RemoteImage(
                        urlString: images[idx],
                        contentMode: .fill,
                        size: CGSize(width: geo.size.width, height: geo.size.height),
                        placeholder: {
                            Color.gray.opacity(0.15)
                        },
                        fallback: {
                            Color.gray.opacity(0.1)
                                .overlay {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                }
                        }
                    )
                    .clipped()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: max(8, geo.size.height * 0.08),
                            style: .continuous
                        )
                    )
                }
                .tag(idx)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
        .frame(height: 130)
        .onReceive(timer) { _ in
            withAnimation {
                selection = (selection + 1) % total
            }
        }
        .padding(0)
    }
}

// MARK: - Slides

// HeroSlideAds removed — images are shown as top-level slides in the main TabView



fileprivate struct HeroSlideOffers: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [AppColors.payBill, AppColors.sendMoney]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(alignment: .leading, spacing: 8) {
                Text("Special Offers")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.95))

                Text("Get 10% cashback on utilities")
                    .font(.headline)
                    .foregroundColor(.white)

                Text("Use code: QUICK10")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(16)
        }
        .padding(.horizontal)
    }
}

fileprivate struct HeroSlideQuickActions: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AppColors.backgroundGradient)

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick Actions")
                        .font(.subheadline)
                        .foregroundColor(.primary)

                    HStack(spacing: 12) {
                        QuickActionButton(icon: "qrcode", title: "Scan")
                        QuickActionButton(icon: "banknote", title: "Top-up")
                        QuickActionButton(icon: "bolt.fill", title: "Pay")
                    }
                }
                Spacer()
            }
            .padding(16)
        }
        .padding(.horizontal)
    }
}

fileprivate struct QuickActionButton: View {
    let icon: String
    let title: String

    var body: some View {
        VStack(spacing: 8) {
            FeatureIconView(icon, color: AppColors.primary, size: 24)

            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

fileprivate struct WalletHeroActionButton: View {
    let title: String
    let icon: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 6) {
                FeatureIconView(icon, color: AppColors.iconLabel, size: 16)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.16))
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    WalletBalanceHeroView()
        .padding()
        .background(AppColors.backgroundGradient)
}
