import UIKit

/// WhatsApp-style text-status font sizing: start large, shrink until the text
/// fits the available rect (not character-count buckets).
enum TextStatusFontSizing {
    static let maxCharacterCount = 700
    static let baseFontSize: CGFloat = 42
    static let minFontSize: CGFloat = 18
    static let step: CGFloat = 1
    static let horizontalInset: CGFloat = 32

    /// Binary-search / step-down fit for a known container.
    static func fittedFontSize(
        text: String,
        in container: CGSize,
        fontFamily: String? = nil,
        fontWeight: String? = nil,
        startSize: CGFloat = baseFontSize,
        minSize: CGFloat = minFontSize,
        horizontalInset: CGFloat = horizontalInset
    ) -> CGFloat {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return min(startSize, baseFontSize) }

        let availableWidth = max(1, container.width - horizontalInset * 2)
        let availableHeight = max(1, container.height)
        var low = minSize
        var high = max(minSize, min(startSize, baseFontSize * 1.15))
        var best = minSize

        while low <= high {
            let mid = ((low + high) / 2).rounded(.down)
            let font = uiFont(family: fontFamily, size: mid, weight: fontWeight)
            let height = textHeight(trimmed, font: font, width: availableWidth)
            if height <= availableHeight {
                best = mid
                low = mid + step
            } else {
                high = mid - step
            }
        }
        return best
    }

    /// Editor fallback when GeometryReader isn't available yet.
    static func fittedFontSizeForScreen(
        text: String,
        fontFamily: String? = nil,
        fontWeight: String? = nil
    ) -> CGFloat {
        let bounds = UIScreen.main.bounds
        // Reserve chrome (progress / header / composer controls).
        let container = CGSize(
            width: bounds.width,
            height: bounds.height * 0.58
        )
        return fittedFontSize(
            text: text,
            in: container,
            fontFamily: fontFamily,
            fontWeight: fontWeight
        )
    }

    /// Thumbnail / strip cards — smaller base, still fit-to-bounds.
    static func fittedFontSizeForThumbnail(
        text: String,
        cardSize: CGSize,
        fontFamily: String? = nil,
        fontWeight: String? = nil
    ) -> CGFloat {
        fittedFontSize(
            text: text,
            in: CGSize(width: cardSize.width, height: cardSize.height * 0.85),
            fontFamily: fontFamily,
            fontWeight: fontWeight,
            startSize: 16,
            minSize: 7,
            horizontalInset: max(6, cardSize.width * 0.08)
        )
    }

    // MARK: - Measurement

    private static func textHeight(_ text: String, font: UIFont, width: CGFloat) -> CGFloat {
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return ceil(rect.height)
    }

    static func uiFont(family: String?, size: CGFloat, weight: String?) -> UIFont {
        if let family, !family.isEmpty, family.lowercased() != "system",
           let custom = UIFont(name: family, size: size) {
            return custom
        }
        return UIFont.systemFont(ofSize: size, weight: uiFontWeight(weight))
    }

    private static func uiFontWeight(_ raw: String?) -> UIFont.Weight {
        switch raw?.lowercased() {
        case "100", "ultralight": return .ultraLight
        case "200", "thin":       return .thin
        case "300", "light":      return .light
        case "400", "regular":    return .regular
        case "500", "medium":     return .medium
        case "600", "semibold":   return .semibold
        case "700", "bold":       return .bold
        case "800", "heavy":      return .heavy
        case "900", "black":      return .black
        default:                  return .regular
        }
    }
}
