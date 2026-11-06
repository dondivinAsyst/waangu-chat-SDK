import SwiftUI
import Combine

// MARK: - Public API
struct DraggableCompass: View {
    @ObservedObject var viewModel: CropViewModel
    var onBegin: () -> Void = {}
    var onChange: (Double) -> Void
    var onDismiss: () -> Void = {}
    var limit: Double = 90

    @State private var isDragging = false
    @State private var dragStartAngle: Angle = .zero

    var body: some View {
        GeometryReader { proxy in
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)

            ZStack {
                VStack {
                    CompassBody(limit: self.limit)
                        .rotationEffect(.degrees(180) + viewModel.rotateCompass)
                        .padding(.bottom)
                    Triangle()
                        .fill(Color.white.opacity(0.7))
                        .frame(width: 10, height: 10)
                        .offset(y: 10)
                    Spacer().frame(height: 270)
                }

                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        DragGesture()
                            .onChanged { value in
                                if !isDragging {
                                    isDragging = true
                                    onBegin()
                                    dragStartAngle = angle(from: center, to: value.startLocation)
                                    viewModel.startRotation = viewModel.rotateCompass
                                }

                                let currentAngle = angle(from: center, to: value.location)
                                var delta = currentAngle - dragStartAngle

                                while delta.degrees > 180 { delta -= .degrees(360) }
                                while delta.degrees < -180 { delta += .degrees(360) }

                                var proposedRotation = viewModel.startRotation + delta

                                if proposedRotation.degrees > self.limit {
                                    proposedRotation = .degrees(self.limit)
                                } else if proposedRotation.degrees < -self.limit {
                                    proposedRotation = .degrees(-self.limit)
                                }

                                viewModel.rotateCompass = proposedRotation
                                onChange(proposedRotation.degrees)
                            }
                            .onEnded { _ in
                                isDragging = false
                                onDismiss()
                            }
                    )
            }
            .frame(width: proxy.size.width, height: 100)
            .clipped()
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, maxHeight: 100)
    }

    private func angle(from center: CGPoint, to point: CGPoint) -> Angle {
        let dx = point.x - center.x
        let dy = point.y - center.y
        return .radians(atan2(dy, dx))
    }
}

// MARK: - Compass graphics (ticks + numbers)
private struct CompassBody: View {
    var limit: Double = 90
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.7), lineWidth: 4)
                .frame(width: 300, height: 300)

            ForEach(0..<72, id: \.self) { i in
                let angle = Double(i) * 5
                Rectangle()
                    .fill(Color.gray)
                    .frame(
                        width: angle.truncatingRemainder(dividingBy: 30) == 0 ? 3 : 1.5,
                        height: angle.truncatingRemainder(dividingBy: 30) == 0 ? 24 : 14
                    )
                    .offset(y: -130)
                    .rotationEffect(.degrees(angle))
            }

            ForEach(0..<12, id: \.self) { i in
                let rawDeg = Double(i) * 30
                let displayDeg = rawDeg > 180 ? rawDeg - 360 : rawDeg

                if abs(displayDeg) <= self.limit {
                    Text("\(Int(displayDeg))")
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .foregroundColor(.white)
                        .offset(y: -170)
                        .rotationEffect(.degrees(rawDeg))
                }
            }

            Circle()
                .fill(Color.gray)
                .frame(width: 12, height: 12)
        }
    }
}

// MARK: - Triangle shape (points down)
private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}
