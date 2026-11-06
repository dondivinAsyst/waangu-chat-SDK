//
//  QRScanReticle.swift
//  SharedUI
//
//  Le viseur d'un scanner de code.
//

import SwiftUI

/// Voile percé, équerres d'angle et ligne de balayage.
///
/// **Dit où viser.** Une prévisualisation caméra nue ne se distingue pas d'un
/// appareil photo : rien n'indique qu'il faut cadrer quelque chose, ni où. Le
/// voile réduit la zone utile à une fenêtre, les équerres la bornent, et le
/// balayage dit que l'écran travaille — trois signaux qui, ensemble, font lire
/// « scanner » plutôt que « photo ».
///
/// Le voile a aussi un effet pratique : il assombrit le pourtour, ce qui aide
/// l'œil à centrer le code et l'exposition de la caméra à ne pas se régler sur
/// une scène plus large que la cible.
public struct QRScanReticle: View {

    /// Côté de la fenêtre. Plafonné à la largeur disponible au rendu.
    public let side: CGFloat

    /// Remonte la fenêtre au-dessus du centre géométrique.
    ///
    /// Un viseur centré à l'écran se retrouve bas dans le champ de vision : le
    /// téléphone est tenu incliné, et la main masque le bas de l'appareil.
    public let verticalOffset: CGFloat

    /// Teinte des équerres et du balayage.
    ///
    /// ``AppColors/primary`` par défaut. Sur une scène sombre elle reste moins
    /// lumineuse qu'un blanc pur : les traits portent donc une ombre noire, qui
    /// les détache d'un fond clair sans altérer la teinte.
    public let tint: Color

    public init(side: CGFloat = 260,
                verticalOffset: CGFloat = -50,
                tint: Color = AppColors.primary) {
        self.side = side
        self.verticalOffset = verticalOffset
        self.tint = tint
    }

    /// Le balayage s'arrête si le système demande moins de mouvement.
    ///
    /// Une boucle infinie est exactement ce que ce réglage vise ; la fenêtre et
    /// les équerres suffisent à désigner la cible sans elle.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum Metrics {
        static let radius: CGFloat = 24
        static let cornerLength: CGFloat = 34
        static let cornerWidth: CGFloat = 4
        static let veil: Double = 0.55
        /// Marge entre la barre et le bord de la fenêtre, pour qu'elle ne
        /// vienne pas buter dans les équerres.
        static let sweepInset: CGFloat = 14
        /// Durée d'un aller-retour complet, en secondes.
        static let sweepPeriod: Double = 3.0
    }

    public var body: some View {
        GeometryReader { geo in
            let box = min(side, geo.size.width - 64)
            let origin = CGPoint(
                x: (geo.size.width - box) / 2,
                y: (geo.size.height - box) / 2 + verticalOffset
            )

            ZStack(alignment: .topLeading) {
                veil(box: box, origin: origin, size: geo.size)

                window(box: box)
                    .offset(x: origin.x, y: origin.y)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        // Décoratif : la consigne est portée par le texte, et VoiceOver n'a
        // que faire d'un cadre qu'il ne peut pas viser.
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Voile sombre percé d'une fenêtre.
    ///
    /// `blendMode(.destinationOut)` dans un `compositingGroup` : le trou est
    /// découpé dans le voile lui-même, sans quoi un rectangle clair posé
    /// par-dessus éclaircirait l'image au lieu de la révéler.
    private func veil(box: CGFloat, origin: CGPoint, size: CGSize) -> some View {
        Color.black.opacity(Metrics.veil)
            .overlay(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                    .frame(width: box, height: box)
                    .offset(x: origin.x, y: origin.y)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .ignoresSafeArea()
    }

    private func window(box: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metrics.radius, style: .continuous)
                .stroke(tint.opacity(0.45), lineWidth: 1)

            corners(box: box)

            if !reduceMotion { sweepLine(box: box) }
        }
        .frame(width: box, height: box)
    }

    /// Quatre équerres, une par angle.
    private func corners(box: CGFloat) -> some View {
        ForEach(0..<4, id: \.self) { index in
            CornerBracket()
                .stroke(tint,
                        style: StrokeStyle(lineWidth: Metrics.cornerWidth,
                                           lineCap: .round, lineJoin: .round))
                .frame(width: Metrics.cornerLength, height: Metrics.cornerLength)
                // Détache l'équerre d'une scène claire — un bleu de marque sur
                // un mur blanc perd presque tout son contraste.
                .shadow(color: .black.opacity(0.5), radius: 3)
                // Une seule équerre dessinée, tournée par quart de tour :
                // quatre tracés distincts divergeraient à la première retouche.
                .rotationEffect(.degrees(Double(index) * 90))
                .position(
                    x: index == 0 || index == 3 ? Metrics.cornerLength / 2 + 2
                                                : box - Metrics.cornerLength / 2 - 2,
                    y: index <= 1 ? Metrics.cornerLength / 2 + 2
                                  : box - Metrics.cornerLength / 2 - 2
                )
        }
    }

    /// La barre qui monte et descend dans la fenêtre.
    ///
    /// Pilotée par l'horloge et non par une animation `repeatForever` déclenchée
    /// depuis `onAppear`. La première version l'était, et restait immobile : une
    /// animation répétée est **annulée dès que la vue parente se reconstruit**,
    /// et la prévisualisation caméra en provoque plusieurs au démarrage — juste
    /// après l'`onAppear` qui l'avait lancée. L'horloge, elle, ne dépend
    /// d'aucun état à préserver.
    private func sweepLine(box: CGFloat) -> some View {
        let travel = box - Metrics.sweepInset * 2

        return TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSinceReferenceDate
            let cycle = elapsed.truncatingRemainder(dividingBy: Metrics.sweepPeriod)
                / Metrics.sweepPeriod
            // Aller-retour : 0 → 1 → 0 sur un cycle.
            let bounce = cycle < 0.5 ? cycle * 2 : (1 - cycle) * 2
            // Lissage cubique — la rampe linéaire pique aux deux extrémités.
            let eased = bounce * bounce * (3 - 2 * bounce)

            ZStack {
                // Halo : donne du corps au trait et rend le mouvement lisible
                // sur une scène claire, où un filet de 2 pt disparaît.
                LinearGradient(
                    colors: [tint.opacity(0), tint.opacity(0.35), tint.opacity(0)],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 26)

                LinearGradient(
                    colors: [tint.opacity(0), tint, tint.opacity(0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(height: 2)
                .shadow(color: tint.opacity(0.9), radius: 5)
            }
            .frame(width: box - Metrics.sweepInset * 2)
            .offset(y: -travel / 2 + travel * eased)
        }
    }
}

/// Une équerre en coin haut-gauche. La rotation produit les trois autres.
private struct CornerBracket: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + 10))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + 10, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
