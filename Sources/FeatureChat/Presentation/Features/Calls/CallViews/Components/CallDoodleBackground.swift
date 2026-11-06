//
//  CallDoodleBackground.swift
//  FeatureChat
//
//  The tiled doodle texture behind an active call.
//
//  Drawn procedurally into a `Canvas` from SF Symbols rather than shipped as an
//  image asset: no binary weight, resolution-independent on every device, and
//  the density/opacity stay tunable from `CallTheme`. The layout is seeded, so
//  the pattern is stable across redraws instead of shuffling on every frame.
//

import SwiftUI

struct CallDoodleBackground: View {

    /// Cell size of the pattern grid. Smaller = denser texture.
    var cellSize: CGFloat = 78
    var tint: Color = CallTheme.Palette.doodle

    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 0xC4115_CA11)
            let columns = Int(ceil(size.width / cellSize)) + 1
            let rows = Int(ceil(size.height / cellSize)) + 1

            for row in 0..<rows {
                for column in 0..<columns {
                    let glyph = Self.glyphs.randomElement(using: &generator) ?? "heart"
                    var resolved = context.resolve(Image(systemName: glyph))
                    resolved.shading = .color(tint)

                    // Jitter each glyph off its grid node so the tiling never reads as a grid.
                    let jitterX = CGFloat.random(in: -18...18, using: &generator)
                    let jitterY = CGFloat.random(in: -18...18, using: &generator)
                    let angle = Double.random(in: -28...28, using: &generator)
                    let scale = CGFloat.random(in: 0.72...1.28, using: &generator)

                    let origin = CGPoint(
                        x: CGFloat(column) * cellSize + jitterX,
                        y: CGFloat(row) * cellSize + jitterY
                    )

                    context.drawLayer { layer in
                        layer.translateBy(x: origin.x, y: origin.y)
                        layer.rotate(by: .degrees(angle))
                        layer.scaleBy(x: scale, y: scale)
                        layer.draw(resolved, at: .zero, anchor: .center)
                    }
                }
            }
        }
        .font(.system(size: 26, weight: .light))
        .background(CallTheme.Palette.canvas)
        .drawingGroup()
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Light, friendly glyphs — deliberately mundane so the texture stays background.
    private static let glyphs: [String] = [
        "heart", "star", "bolt", "camera", "gift", "bicycle", "airplane",
        "cup.and.saucer", "leaf", "moon", "sun.max", "cloud", "music.note",
        "gamecontroller", "balloon", "birthday.cake", "pawprint", "flame",
        "umbrella", "bell", "envelope", "paperplane", "book", "lightbulb",
        "car", "tram", "sailboat", "tortoise", "hare", "fish", "ladybug",
        "tshirt", "eyeglasses", "crown", "die.face.5", "puzzlepiece",
        "globe", "map", "mountain.2", "tree", "carrot", "wineglass"
    ]
}

// MARK: - Seeded Generator

/// Deterministic RNG (SplitMix64) so the doodle layout is identical on every redraw.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    CallDoodleBackground()
}
