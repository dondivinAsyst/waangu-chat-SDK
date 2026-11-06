//
//  CopilotFloatingButton.swift
//  FeatureChat
//
//  Bouton flottant de Waangu Copilot (§8) — déplaçable, aimanté au bord.
//

import SwiftUI
import WaanguSharedUI

/// Bouton flottant qui ouvre Waangu Copilot.
///
/// Suit le doigt au pixel près, puis glisse vers le bord gauche ou droit au
/// relâchement — celui vers lequel on l'a lancé, sinon le plus proche, comme
/// l'image dans l'image d'iOS. Un appui court l'ouvre.
///
/// Deux pièges évités, qui le faisaient sauter :
/// - le geste se mesure dans l'espace **de l'écran**, pas dans celui du bouton :
///   ce dernier se déplace avec lui, et chaque image corrigeait la précédente ;
/// - la position suivie est un `@State`, pas un `@GestureState` : celui-ci
///   revient à zéro sans animation au relâchement, et le bouton retournait à
///   son point de départ avant de repartir vers le bord.
/// - le glissement est **prioritaire** sur le défilement de la page : sinon la
///   page et le bouton se disputaient le même doigt.
struct CopilotFloatingButton: View {

    let action: () -> Void

    /// Centre du bouton dans l'écran qui le porte. `nil` ⇒ en bas à droite.
    @State private var center: CGPoint?
    /// Centre au début du glissement : le doigt déplace à partir de là.
    @State private var dragOrigin: CGPoint?
    @State private var isLifted = false

    private static let space = "copilotFloatingButton"

    enum Metrics {
        static let size: CGFloat = 64
        static let glyph: CGFloat = 26
        static let margin: CGFloat = 16
        /// Au-dessus du bas de l'écran : la barre d'accueil et les feuilles.
        static let bottomInset: CGFloat = 96
        static let topInset: CGFloat = 120
        static let dragThreshold: CGFloat = 6
    }

    var body: some View {
        GeometryReader { proxy in
            let resting = center ?? Self.home(in: proxy.size)
            button
                .position(resting)
                // Prioritaire : posé sur une page qui défile, le bouton
                // garde le doigt au lieu de le céder au défilement.
                .highPriorityGesture(drag(from: resting, in: proxy.size))
        }
        .coordinateSpace(name: Self.space)
    }

    private func drag(from resting: CGPoint, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: Metrics.dragThreshold, coordinateSpace: .named(Self.space))
            .onChanged { value in
                let origin = dragOrigin ?? resting
                if dragOrigin == nil {
                    dragOrigin = origin
                    withAnimation(.easeOut(duration: 0.15)) { isLifted = true }
                }
                // Sans animation : le bouton est sous le doigt, pas derrière lui.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    center = Self.clamped(CGPoint(x: origin.x + value.translation.width,
                                                  y: origin.y + value.translation.height), in: size)
                }
            }
            .onEnded { value in
                let origin = dragOrigin ?? resting
                dragOrigin = nil
                // Le côté suit l'élan : lancé vers la droite, il va à droite.
                let aimed = CGPoint(x: origin.x + value.predictedEndTranslation.width,
                                    y: origin.y + value.translation.height)
                withAnimation(.spring(response: 0.42, dampingFraction: 0.78)) {
                    center = Self.snapped(aimed, in: size)
                    isLifted = false
                }
            }
    }

    private var button: some View {
        Image(systemName: "sparkles")
            .font(.system(size: Metrics.glyph, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: Metrics.size, height: Metrics.size)
            .background(
                Circle()
                    .fill(AppColors.primary)
                    // Liseré clair : le bord reste lisible sur un fond sombre.
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
            )
            // Deux ombres : une large et teintée qui le décolle de la page, une
            // courte et sombre qui fixe son bord.
            .shadow(color: AppColors.primary.opacity(isLifted ? 0.45 : 0.32),
                    radius: isLifted ? 20 : 14, y: isLifted ? 12 : 7)
            .shadow(color: .black.opacity(0.14), radius: 2, y: 1)
            .scaleEffect(isLifted ? 1.08 : 1)
            .contentShape(Circle())
            .onTapGesture(perform: action)
            .accessibilityElement()
            .accessibilityLabel(FinanceStrings.copilotName)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }

    // MARK: - Placement

    static func home(in size: CGSize) -> CGPoint {
        CGPoint(x: size.width - Metrics.margin - Metrics.size / 2,
                y: size.height - Metrics.bottomInset - Metrics.size / 2)
    }

    /// Pendant le glissement : n'importe où, mais jamais hors de l'écran.
    static func clamped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let half = Metrics.size / 2
        let minX = Metrics.margin + half
        let maxX = max(minX, size.width - Metrics.margin - half)
        let minY = Metrics.topInset + half
        let maxY = max(minY, size.height - Metrics.bottomInset - half)
        return CGPoint(x: min(max(point.x, minX), maxX), y: min(max(point.y, minY), maxY))
    }

    /// Au relâchement : contre le bord du côté visé, à la hauteur atteinte.
    static func snapped(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let half = Metrics.size / 2
        let x = point.x < size.width / 2 ? Metrics.margin + half : size.width - Metrics.margin - half
        return clamped(CGPoint(x: x, y: point.y), in: size)
    }
}
