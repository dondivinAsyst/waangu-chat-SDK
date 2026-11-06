import SwiftUI

enum StoryTextDeleteZoneMetrics {
    static let paddingLeading: CGFloat = 20
    static let paddingTop: CGFloat = 108
    static let size: CGFloat = 52

    static var zoneRect: CGRect {
        CGRect(
            x: paddingLeading - 8,
            y: paddingTop - 8,
            width: size + 16,
            height: size + 16
        )
    }

    static func contains(_ point: CGPoint) -> Bool {
        let center = CGPoint(x: paddingLeading + size / 2, y: paddingTop + size / 2)
        let dx = point.x - center.x
        let dy = point.y - center.y
        let hitRadius = size / 2 + 36
        return (dx * dx + dy * dy) <= hitRadius * hitRadius
    }
}

struct StoryTextDeleteZone: View {
    let isActive: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(isActive ? Color.red.opacity(0.92) : Color.black.opacity(0.45))
                .frame(width: isActive ? 52 : 44, height: isActive ? 52 : 44)
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(isActive ? 0.4 : 0.18), lineWidth: 1)
                }
                .shadow(color: .black.opacity(isActive ? 0.35 : 0.2), radius: isActive ? 8 : 4, y: 2)

            AnimatedTrashLidIcon(isOpen: isActive)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: isActive)
        .allowsHitTesting(false)
        .accessibilityLabel(isActive ? "Release to delete" : "Drag here to delete")
    }
}

private struct AnimatedTrashLidIcon: View {
    let isOpen: Bool

    var body: some View {
        ZStack(alignment: .top) {
            Image(systemName: "trash.fill")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.white)
                .offset(y: 2)

            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white)
                .frame(width: isOpen ? 17 : 14, height: 2.5)
                .offset(y: isOpen ? -5 : -1)
                .rotationEffect(.degrees(isOpen ? -38 : 0), anchor: .leading)
                .offset(x: isOpen ? -5 : -1)
        }
        .frame(width: 22, height: 22)
        .scaleEffect(isOpen ? 1.12 : 1)
        .animation(.spring(response: 0.28, dampingFraction: 0.68), value: isOpen)
    }
}
