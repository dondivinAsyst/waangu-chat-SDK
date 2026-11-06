import SwiftUI

struct BottomTabBar: View {
    @Binding var selectedIndex: Int
    var onCenterTap: (() -> Void)?
    @Namespace private var tabNamespace

    private let buttonSize: CGFloat = 64
    private let notchGap: CGFloat = 8
    private let barCornerRadius: CGFloat = 28

    init(selectedIndex: Binding<Int>, onCenterTap: (() -> Void)? = nil) {
        self._selectedIndex = selectedIndex
        self.onCenterTap = onCenterTap
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                ZStack(alignment: .top) {
                    HStack(alignment: .center, spacing: 0) {
                        HStack(spacing: 30) {
                            TabItem(icon: "house.fill", title: "Home", index: 0,
                                    selectedIndex: $selectedIndex, namespace: tabNamespace)
                            TabItem(icon: "square.grid.2x2", title: "Services", index: 1,
                                    selectedIndex: $selectedIndex, namespace: tabNamespace)
                        }
                        .frame(maxWidth: .infinity)
                        
                        Spacer().frame(width: 90)
                        
                        HStack(spacing: 30) {
                            TabItem(icon: "car.fill", title: "Ride", index: 3,
                                    selectedIndex: $selectedIndex, namespace: tabNamespace)
                            TabItem(icon: "clock", title: "History", index: 4,
                                    selectedIndex: $selectedIndex, namespace: tabNamespace)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)
                    .glassEffect(
                        .regular,
                        in: NotchedBarShape(
                            cornerRadius: barCornerRadius,
                            notchRadius: buttonSize / 2 + notchGap
                        )
                    )
                    .overlay {
                        let shape = NotchedBarShape(
                            cornerRadius: barCornerRadius,
                            notchRadius: buttonSize / 2 + notchGap
                        )
                        shape
                            .strokeBorder(.white.opacity(0.72), lineWidth: 1)
                            .overlay {
                                shape
                                    .strokeBorder(.black.opacity(0.06), lineWidth: 0.8)
                            }
                            .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    }
                    
                    Button(action: { onCenterTap?() }) {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppColors.centerGradientStart, AppColors.centerGradientEnd],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: buttonSize, height: buttonSize)
                            
                            Image(systemName: "qrcode")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundStyle(.white)
                        }
                        .shadow(color: AppColors.centerGradientEnd.opacity(0.4), radius: 10, y: 4)
                    }
                    .offset(y: -buttonSize / 2)
                }
            }
            .frame(maxWidth: .infinity)
            .edgesIgnoringSafeArea(.bottom)
        } else {
            // Fallback on earlier versions
        }
    }
}

// MARK: - Notched Bar Shape

fileprivate struct NotchedBarShape: InsettableShape {
    let cornerRadius: CGFloat
    let notchRadius: CGFloat
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> NotchedBarShape {
        NotchedBarShape(cornerRadius: cornerRadius, notchRadius: notchRadius, insetAmount: insetAmount + amount)
    }

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let cr = cornerRadius
        let nr = notchRadius
        let cx = r.midX
        let arcSegments = 28

        var path = Path()

        path.move(to: CGPoint(x: r.minX + cr, y: r.minY))
        path.addLine(to: CGPoint(x: cx - nr, y: r.minY))

        for segment in 0...arcSegments {
            let t = CGFloat(segment) / CGFloat(arcSegments)
            let angle = Double.pi * (1 - Double(t))
            let point = CGPoint(
                x: cx + nr * CGFloat(cos(angle)),
                y: r.minY + nr * CGFloat(sin(angle))
            )
            path.addLine(to: point)
        }

        path.addLine(to: CGPoint(x: r.maxX - cr, y: r.minY))

        path.addArc(center: CGPoint(x: r.maxX - cr, y: r.minY + cr),
                     radius: cr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - cr))
        path.addArc(center: CGPoint(x: r.maxX - cr, y: r.maxY - cr),
                     radius: cr, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX + cr, y: r.maxY))
        path.addArc(center: CGPoint(x: r.minX + cr, y: r.maxY - cr),
                     radius: cr, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + cr))
        path.addArc(center: CGPoint(x: r.minX + cr, y: r.minY + cr),
                     radius: cr, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)

        return path
    }
}

// MARK: - Tab Item

fileprivate struct TabItem: View {
    let icon: String
    let title: String
    let index: Int
    @Binding var selectedIndex: Int
    var namespace: Namespace.ID

    private var isSelected: Bool { selectedIndex == index }

    var body: some View {
        Button {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) {
                selectedIndex = index
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? Color.black : .secondary)

                Text(title)
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(minWidth: 48)
                        .background {
                            if isSelected {
                                if #available(iOS 26.0, *) {
                                    Circle()
                                        .fill(.clear)
                                        .frame(width: 56, height: 56)
                                        .glassEffect(.clear, in: .circle)
                                        .matchedGeometryEffect(id: "highlight", in: namespace)
                                } else {
                                    // Fallback on earlier versions
                                }
                            }            }
        }
        .buttonStyle(.plain)
    }
}
