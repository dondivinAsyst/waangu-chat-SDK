// MARK: - SharedUI/Modifiers/PresentationDetentsModifier.swift

import SwiftUI

public struct PresentationDetentsDynamicModifier: ViewModifier {
    public let itemsCount: Int

    public init(itemsCount: Int) {
        self.itemsCount = itemsCount
    }

    public func body(content: Content) -> some View {
        let rowHeight: CGFloat = 50
        let titleHeight: CGFloat = 60
        let idealHeight = titleHeight + (CGFloat(itemsCount) * rowHeight)

        content
            .presentationDetents([.height(min(idealHeight, 600))])
    }
}
