// MARK: - SharedUI/Modifiers/LoadingModifier.swift

import SwiftUI
import UIKit

public struct LoadingModifier: ViewModifier {
    public let isLoading: Bool

    public init(isLoading: Bool) {
        self.isLoading = isLoading
    }

    public func body(content: Content) -> some View {
        ZStack {
            content
            if isLoading {
                RNStyleLoadingOverlay()
                    .zIndex(1_000)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}


private struct RNStyleLoadingOverlay: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private let cardCornerRadius: CGFloat = 10 // RN: borderRadius: 10

    var body: some View {
        ZStack {

            VStack(alignment: .center, spacing: 0) {
                RNLoadingSpinner(size: 28, ringUsesDarkStroke: reduceTransparency) // RN: size={28}
                    .padding(.top, 10) // RN: marginTop: 10 sur l'Animated.View

                Text("Loading...")
                    .font(.system(size: 14, weight: .medium)) // RN: fontSize: 14
                    .foregroundStyle(reduceTransparency ? Color(hex: 0x4A4A4A) : .white)
                    .multilineTextAlignment(.center)
                    .padding(.top, 25) // RN: marginTop: 25
            }
            .padding(.horizontal, 25) // RN: paddingHorizontal: 25
            .padding(.vertical, 20)   // RN: paddingVertical: 20
            .fixedSize(horizontal: true, vertical: false)
            .background {
                Group {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                            .fill(Color.white)
                    } else {
                        DarkLoadingBlurCard(cornerRadius: cardCornerRadius)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Loading"))
        .accessibilityAddTraits(.updatesFrequently)
    }
}

// MARK: - UIKit blur (équiv. `@react-native-community/blur` dark + overlay)

private struct DarkLoadingBlurCard: UIViewRepresentable {
    var cornerRadius: CGFloat

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
        view.clipsToBounds = true
        view.layer.cornerCurve = .continuous

        let tint = UIView()
        tint.backgroundColor = UIColor(red: 74/255, green: 74/255, blue: 74/255, alpha: 0.65)
        tint.isUserInteractionEnabled = false
        tint.translatesAutoresizingMaskIntoConstraints = false
        view.contentView.addSubview(tint)
        NSLayoutConstraint.activate([
            tint.topAnchor.constraint(equalTo: view.contentView.topAnchor),
            tint.leadingAnchor.constraint(equalTo: view.contentView.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: view.contentView.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: view.contentView.bottomAnchor)
        ])
        return view
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.layer.cornerRadius = cornerRadius
    }
}

// MARK: - Spinner

private struct RNLoadingSpinner: View {
    let size: CGFloat
    var ringUsesDarkStroke: Bool = false

    // RN: Easing.ease = ease-in-out sur 1000ms
    // On simule avec une animation SwiftUI repeatForever
    @State private var rotation: Double = 0

    private let dotGreen = Color(hex: 0x75D729)

    var body: some View {
        let height = size * (30.0 / 31.0)

        Canvas { ctx, canvas in
            let s = min(canvas.width / 31, canvas.height / 30)
            ctx.translateBy(x: canvas.width / 2, y: canvas.height / 2)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: -16, y: -15)

            // RN: strokeWidth={1} dans le viewBox → on passe 1.0 directement,
            // Canvas GraphicsContext.stroke travaille en coordonnées locales après le scale
            let ring = Path(ellipseIn: CGRect(x: 16 - 14.5, y: 15 - 14.5, width: 29, height: 29))
            let ringColor = ringUsesDarkStroke ? Color(hex: 0x4A4A4A) : Color.white
            ctx.stroke(ring, with: .color(ringColor), lineWidth: 1.0) // RN: strokeWidth={1}

            // RN: cx={25.692} cy={25.19} r={3.5}
            let d1 = CGRect(x: 25.692 - 3.5, y: 25.19 - 3.5, width: 7, height: 7)
            ctx.fill(Path(ellipseIn: d1), with: .color(dotGreen))

            // RN: cx={4.438} cy={6.565} r={3.5}
            let d2 = CGRect(x: 4.438 - 3.5, y: 6.565 - 3.5, width: 7, height: 7)
            ctx.fill(Path(ellipseIn: d2), with: .color(dotGreen))
        }
        .frame(width: size, height: height)
        // RN: rotation du SVG entier avec Easing.ease, duration: 1000ms
        .rotationEffect(.degrees(rotation))
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.0) // RN: Easing.ease, duration: 1000
                .repeatForever(autoreverses: false)
            ) {
                rotation = 360
            }
        }
    }
}
