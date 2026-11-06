//
//  InsuranceCardSkeleton.swift
//  AppModules
//
//  Created by Don divin on 4/9/26.
//

import SwiftUI

struct ShimmerModifiers: ViewModifier {
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .white.opacity(0.45), location: 0.4),
                            .init(color: .white.opacity(0.45), location: 0.6),
                            .init(color: .clear, location: 1)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: -geo.size.width + phase * geo.size.width * 2)
                }
                .clipped()
            )
            .onAppear {
                withAnimation(
                    .linear(duration: 1.4)
                    .repeatForever(autoreverses: false)
                ) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifiers())
    }
}

// MARK: - Bone (reusable skeleton element)

private struct Bone: View {
    var width: CGFloat? = nil
    var height: CGFloat
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
            .frame(width: width, height: height)
    }
}

// MARK: - InsuranceCardSkeleton

//public struct InsuranceCardSkeleton: View {
//    public init() {}
//
//    public var body: some View {
//        VStack(alignment: .leading, spacing: 0) {
//
//            // TOP ROW — icon + title/subtitle + badge
//            HStack(alignment: .top, spacing: 12) {
//                Bone(width: 52, height: 52, cornerRadius: 12)
//
//                VStack(alignment: .leading, spacing: 8) {
//                    Bone(height: 14)
//                        .frame(maxWidth: 160)
//                    Bone(height: 11)
//                        .frame(maxWidth: 100)
//                }
//
//                Spacer()
//
//                Bone(width: 64, height: 24, cornerRadius: 20)
//            }
//
//            Divider()
//                .padding(.vertical, 16)
//
//            // COVERAGE LABEL + TAGS
//            VStack(alignment: .leading, spacing: 10) {
//                Bone(height: 11)
//                    .frame(maxWidth: 120)
//
//                HStack(spacing: 8) {
//                    Bone(width: 72, height: 26, cornerRadius: 20)
//                    Bone(width: 56, height: 26, cornerRadius: 20)
//                    Bone(width: 64, height: 26, cornerRadius: 20)
//                }
//            }
//
//            Spacer().frame(height: 16)
//
//            // BOTTOM ROW — two data points + CTA button
//            HStack(alignment: .bottom) {
//                VStack(alignment: .leading, spacing: 6) {
//                    Bone(width: 60, height: 10)
//                    Bone(width: 90, height: 13)
//                }
//
//                Spacer()
//
//                VStack(alignment: .trailing, spacing: 6) {
//                    Bone(width: 50, height: 10)
//                    Bone(width: 70, height: 13)
//                }
//
//                Spacer().frame(width: 16)
//
//                Bone(width: 88, height: 34, cornerRadius: 10)
//            }
//        }
//        .padding(20)
//        .background(Color(.systemGray6))
//        .cornerRadius(16)
//        .shimmer()
//    }
//}
public struct InsuranceCardSkeleton: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 0) {

            // TOP ROW — icon + name/stars + badge
            HStack(alignment: .top, spacing: 14) {
                Bone(width: 56, height: 56, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 8) {
                    Bone(height: 16)
                        .frame(maxWidth: 160)
                    // Star bones — individual squares like actual stars
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { _ in
                            Bone(width: 14, height: 14, cornerRadius: 3)
                        }
                    }
                }

                Spacer()

                Bone(width: 68, height: 24, cornerRadius: 20)
            }
            .padding(.bottom, 16)

            Divider()
                .padding(.bottom, 16)

            // BOTTOM ROW — tags + Continue button
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Bone(width: 80, height: 26, cornerRadius: 20)
                    Bone(width: 62, height: 26, cornerRadius: 20)
                    Bone(width: 72, height: 26, cornerRadius: 20)
                }
                .clipped()

                Spacer(minLength: 8)

                Bone(width: 80, height: 26, cornerRadius: 8)
            }
        }
        .padding(20)
        .background(Color.white)
        .cornerRadius(16)
        .shadow(color: Color.brandPrimary.opacity(0.15), radius: 12, x: 0, y: 4)
        .shimmer()
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 12) {
            ForEach(0..<4) { _ in
                InsuranceCardSkeleton()
            }
        }
        .padding()
    }
}
