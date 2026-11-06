import UIKit
import SwiftUI
import WaanguSharedUI

func textMetrics(for text: String, font: UIFont, maxWidth: CGFloat) -> (lines: Int, occupiedWidth: CGFloat) {
    
    let maxSize = CGSize(width: maxWidth, height: CGFloat.greatestFiniteMagnitude)
    
    let textAttributes: [NSAttributedString.Key: Any] = [.font: font]
    
    // Calculate bounding rect
    let textRect = text.boundingRect(
        with: maxSize,
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: textAttributes,
        context: nil
    )
    
    let lineHeight = font.lineHeight
    let numberOfLines = Int(ceil(textRect.height / lineHeight))
    
    // Occupied width = min(maxWidth, actual text width)
    let occupiedWidth = min(maxWidth, ceil(textRect.width))
    
    return (lines: numberOfLines, occupiedWidth: occupiedWidth)
}

func textMetricsWidth(
    for text: String,
    font: Font,
    maxWidth: CGFloat
) -> CGFloat {
    let uiFont = font.toUIFont()

    let attributes: [NSAttributedString.Key: Any] = [
        .font: uiFont
    ]

    let boundingRect = text.boundingRect(
        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: attributes,
        context: nil
    )

    return min(ceil(boundingRect.width), maxWidth)
}
