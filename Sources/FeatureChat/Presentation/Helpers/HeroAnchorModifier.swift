import SwiftUI
import UIKit

/// Reports a view's window-space rect to `MediaHeroAnchorRegistry`, and hides it
/// while its snapshot is flying in a hero transition.
private struct HeroAnchorModifier: ViewModifier {

    let id: String
    let image: UIImage?

    @ObservedObject private var registry = MediaHeroAnchorRegistry.shared

    func body(content: Content) -> some View {
        content
            .opacity(registry.hiddenAnchorID == id ? 0 : 1)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { register(geo.frame(in: .global)) }
                        .onChange(of: geo.frame(in: .global)) { _, rect in register(rect) }
                        .onDisappear { registry.unregister(id: id) }
                }
            )
    }

    private func register(_ rect: CGRect) {
        registry.register(id: id, rect: rect, image: image, sourceView: nil)
    }
}

extension View {
    /// Marks this view as the hero source for `id`.
    ///
    /// Apply it to the media content itself, never to the enclosing bubble — the
    /// bubble includes the reply preview, caption and padding, and flying from
    /// that rect is what made the previous viewer jump on open.
    func heroAnchor(id: String, image: UIImage?) -> some View {
        modifier(HeroAnchorModifier(id: id, image: image))
    }
}
