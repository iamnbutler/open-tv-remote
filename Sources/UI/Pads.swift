import SwiftUI

enum PadMode: String, CaseIterable, Identifiable {
    case dpad, touchpad, keypad
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dpad: "dpad.fill"
        case .touchpad: "hand.point.up.left.fill"
        case .keypad: "circle.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .dpad: "Directional pad"
        case .touchpad: "Touchpad"
        case .keypad: "Number pad"
        }
    }
}

// MARK: - D-pad

struct Wedge: InsettableShape {
    var direction: Angle
    var innerRatio: CGFloat = 0.44
    var gap: Angle = .degrees(2.2)
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let outer = r - insetAmount
        let inner = r * innerRatio + insetAmount
        let start = direction - .degrees(45) + gap
        let end = direction + .degrees(45) - gap
        var p = Path()
        p.addArc(center: c, radius: outer, startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: c, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        return p
    }

    func inset(by amount: CGFloat) -> Wedge {
        var w = self
        w.insetAmount += amount
        return w
    }
}

struct DPadView: View {
    @Environment(AppModel.self) private var model

    private let directions: [(key: RemoteKey, angle: Double, symbol: String)] = [
        (.right, 0, "chevron.right"),
        (.down, 90, "chevron.down"),
        (.left, 180, "chevron.left"),
        (.up, 270, "chevron.up"),
    ]

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let radius = size / 2
            let iconDistance = radius * (1 + 0.44) / 2
            ZStack {
                Circle()
                    .fill(Theme.well)
                    .overlay(Circle().strokeBorder(.white.opacity(0.04), lineWidth: 1))
                    .padding(-6)

                ForEach(directions, id: \.angle) { d in
                    KeyCap(shape: Wedge(direction: .degrees(d.angle)), repeats: true,
                           accessibilityLabel: d.key.accessibilityName) {
                        model.press(d.key)
                    } label: {
                        Image(systemName: d.symbol)
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(Theme.secondary)
                            .offset(x: cos(d.angle * .pi / 180) * iconDistance,
                                    y: sin(d.angle * .pi / 180) * iconDistance)
                    }
                }

                KeyCap(shape: Circle(), accessibilityLabel: "OK") {
                    model.press(.select)
                } label: {
                    Text("OK").font(.system(size: 22, weight: .bold, design: .rounded))
                }
                .frame(width: size * 0.40, height: size * 0.40)
            }
            .frame(width: size, height: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Touchpad

struct TouchpadView: View {
    @Environment(AppModel.self) private var model
    @State private var touch: CGPoint?
    @State private var anchor: CGPoint = .zero
    @State private var moved = false
    @GestureState private var isTouching = false

    private let step: CGFloat = 36

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28, style: .continuous)
        ZStack {
            shape.fill(Theme.well)
            Canvas { ctx, size in
                let spacing: CGFloat = 22
                for x in stride(from: spacing / 2, to: size.width, by: spacing) {
                    for y in stride(from: spacing / 2, to: size.height, by: spacing) {
                        ctx.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(.white.opacity(0.07)))
                    }
                }
            }
            .clipShape(shape)

            VStack(spacing: 6) {
                Text("Swipe to move")
                Text("Tap to select")
            }
            .font(.system(size: 15, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.secondary)
            .opacity(touch == nil ? 1 : 0.25)

            if let touch {
                Circle()
                    .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), Theme.accent.opacity(0)], center: .center, startRadius: 0, endRadius: 46))
                    .frame(width: 92, height: 92)
                    .position(touch)
                    .allowsHitTesting(false)
            }
        }
        .overlay(shape.strokeBorder(.white.opacity(0.06), lineWidth: 1))
        .contentShape(shape)
        .gesture(
            DragGesture(minimumDistance: 0)
                .updating($isTouching) { _, state, _ in state = true }
                .onChanged { v in
                    if touch == nil {
                        anchor = v.startLocation
                        moved = false
                    }
                    touch = v.location
                    let dx = v.location.x - anchor.x
                    let dy = v.location.y - anchor.y
                    if abs(dx) >= step, abs(dx) > abs(dy) {
                        emit(dx > 0 ? .right : .left)
                        anchor = CGPoint(x: anchor.x + (dx > 0 ? step : -step), y: v.location.y)
                    } else if abs(dy) >= step {
                        emit(dy > 0 ? .down : .up)
                        anchor = CGPoint(x: v.location.x, y: anchor.y + (dy > 0 ? step : -step))
                    }
                }
                .onEnded { v in
                    if !moved, hypot(v.translation.width, v.translation.height) < 12 {
                        Haptics.tap()
                        model.press(.select)
                    }
                    withAnimation(.easeOut(duration: 0.2)) { touch = nil }
                }
        )
        .onChange(of: isTouching) { _, touching in
            // A system-cancelled touch never reaches onEnded; clear it so the next swipe starts fresh.
            if !touching { withAnimation(.easeOut(duration: 0.2)) { touch = nil } }
        }
        .accessibilityElement()
        .accessibilityLabel("Touchpad")
        .accessibilityHint("Swipe to move, double tap to select")
        .accessibilityAction { model.press(.select) }
        .accessibilityAdjustableAction { direction in
            model.press(direction == .increment ? .up : .down)
        }
    }

    private func emit(_ key: RemoteKey) {
        moved = true
        Haptics.tick()
        model.press(key)
    }
}

// MARK: - Keypad

struct KeypadView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Rows stretch to fill whatever height the pad gets.
        Grid(horizontalSpacing: 12, verticalSpacing: 10) {
            ForEach(0..<3) { row in
                GridRow {
                    ForEach(1...3, id: \.self) { col in digit(row * 3 + col) }
                }
            }
            GridRow {
                KeyCap(accessibilityLabel: "Back") { model.press(.back) } label: {
                    Image(systemName: "arrow.uturn.backward").font(.system(size: 18, weight: .semibold))
                }
                digit(0)
                KeyCap(repeats: true, enabled: model.supports(.backspace), accessibilityLabel: "Delete") { model.press(.backspace) } label: {
                    Image(systemName: "delete.left").font(.system(size: 18, weight: .semibold))
                }
            }
        }
    }

    private func digit(_ n: Int) -> some View {
        KeyCap(enabled: model.supports(.digit(n)), accessibilityLabel: "\(n)") { model.press(.digit(n)) } label: {
            Text("\(n)").font(.system(size: 24, weight: .semibold, design: .rounded))
        }
    }
}
