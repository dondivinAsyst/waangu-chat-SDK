import SwiftUI

struct SkeletonCell: View {
    @State private var shimmerOffset: CGFloat = -200

    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.gray.opacity(0.3),
                        Color.gray.opacity(0.45),
                        Color.gray.opacity(0.3)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0.0),
                        Color.white.opacity(0.6),
                        Color.white.opacity(0.0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .offset(x: shimmerOffset)
                .mask(RoundedRectangle(cornerRadius: 8))
            )
            .onAppear {
                withAnimation(
                    Animation
                        .linear(duration: 1.2)
                        .repeatForever(autoreverses: false)
                ) {
                    shimmerOffset = 200
                }
            }
    }
}

// MARK: VIEW
struct SkeletonGrid: View {
    var CellNumber: Int = 16
    private let columns = Array(
        repeating: GridItem(.flexible(minimum: 100, maximum: 200), spacing: 2),
        count: 3
    )

    var body: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<CellNumber, id: \.self) { _ in
                SkeletonCell()
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .padding(4)
    }
}

