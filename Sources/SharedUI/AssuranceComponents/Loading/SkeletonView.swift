import SwiftUI

// MARK: - Skeleton Shape

public struct SkeletonView: View {
    public var width: CGFloat? = nil
    public var height: CGFloat = 16
    public var cornerRadius: CGFloat = AppCornerRadius.sm

    @State private var isAnimating = false
    
    public init(
        width: CGFloat? = nil,
        height: CGFloat = 16,
        cornerRadius: CGFloat = AppCornerRadius.sm
    ) {
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.appDisabled.opacity(0.4))
            .frame(width: width, height: height)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(
                        LinearGradient(
                            colors: [.clear, .white.opacity(0.4), .clear],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .offset(x: isAnimating ? 200 : -200)
            )
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Skeleton Row

public struct SkeletonRow: View {
    public init() {}

    public var body: some View {
        HStack(spacing: AppSpacing.sm) {
            SkeletonView(width: 44, height: 44, cornerRadius: 22)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                SkeletonView(width: 140, height: 14)
                SkeletonView(width: 200, height: 12)
            }

            Spacer()
        }
        .padding(AppSpacing.md)
    }
}

// MARK: - Skeleton List

public struct SkeletonList: View {
    public var rowCount: Int = 5

    public init(rowCount: Int = 5) {
        self.rowCount = rowCount
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rowCount, id: \.self) { _ in
                SkeletonRow()
                Divider().padding(.leading, 68)
            }
        }
    }
}

#Preview("Skeleton") {
    SkeletonList()
}
