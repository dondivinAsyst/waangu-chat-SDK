import SwiftUI

struct TextStatusViewComponent: View {
    let text: String
    let backgroundColor: Color
    let textColor: Color
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let preferredFontSize: CGFloat?
    let fontWeight: Font.Weight
    let fontFamily: String
    let hasShadow: Bool
    let fillsContainer: Bool

    init(
        text: String,
        backgroundColor: Color? = nil,
        textColor: Color = .white,
        width: CGFloat = 200,
        height: CGFloat = 200,
        cornerRadius: CGFloat = 16,
        fontSize: CGFloat? = nil,
        fontFamily: String = "system",
        fontWeight: Font.Weight = .bold,
        hasShadow: Bool = true,
        fillsContainer: Bool = false
    ) {
        self.text = text
        if let color = backgroundColor {
            self.backgroundColor = color
        } else {
            let colors: [Color] = [.blue, .green, .orange, .pink, .purple, .teal, .indigo, .red]
            self.backgroundColor = colors.randomElement() ?? .blue
        }
        self.textColor = textColor
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.preferredFontSize = fontSize
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.hasShadow = hasShadow
        self.fillsContainer = fillsContainer
    }

    var body: some View {
        if fillsContainer {
            fullScreenBody
        } else {
            cardBody
        }
    }

    // MARK: - Full-screen (StatusViewer)

    private var fullScreenBody: some View {
        GeometryReader { geo in
            let fitted = TextStatusFontSizing.fittedFontSize(
                text: text,
                in: CGSize(width: geo.size.width, height: geo.size.height * 0.62),
                fontFamily: fontFamily,
                fontWeight: fontWeightRaw,
                startSize: preferredFontSize ?? TextStatusFontSizing.baseFontSize
            )

            ZStack {
                backgroundColor
                    .ignoresSafeArea()

                Text(text)
                    .font(swiftUIFont(size: fitted))
                    .fontWeight(fontWeight)
                    .foregroundColor(textColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .minimumScaleFactor(0.9)
                    .padding(.horizontal, TextStatusFontSizing.horizontalInset)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Thumbnail / strip card

    private var cardBody: some View {
        let fitted = TextStatusFontSizing.fittedFontSizeForThumbnail(
            text: text,
            cardSize: CGSize(width: width, height: height),
            fontFamily: fontFamily,
            fontWeight: fontWeightRaw
        )

        return ZStack {
            backgroundColor
                .frame(width: width, height: height)
                .cornerRadius(cornerRadius)
                .shadow(
                    color: hasShadow ? .black.opacity(0.2) : .clear,
                    radius: hasShadow ? 6 : 0,
                    x: 0,
                    y: 4
                )

            Text(text)
                .font(swiftUIFont(size: fitted))
                .fontWeight(fontWeight)
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
                .lineLimit(6)
                .minimumScaleFactor(0.85)
                .padding(max(6, width * 0.08))
                .frame(width: width * 0.92, height: height * 0.9)
        }
    }

    // MARK: - Helpers

    private var fontWeightRaw: String {
        switch fontWeight {
        case .ultraLight: return "ultralight"
        case .thin: return "thin"
        case .light: return "light"
        case .regular: return "regular"
        case .medium: return "medium"
        case .semibold: return "semibold"
        case .bold: return "bold"
        case .heavy: return "heavy"
        case .black: return "black"
        default: return "regular"
        }
    }

    private func swiftUIFont(size: CGFloat) -> Font {
        if fontFamily.isEmpty || fontFamily.lowercased() == "system" {
            return .system(size: size, weight: fontWeight)
        }
        return .custom(fontFamily, size: size)
    }
}
