import SwiftUI

enum PadMode: String, CaseIterable, Identifiable {
    case dpad, keyboard, keypad
    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .dpad: "dpad.fill"
        case .keyboard: "keyboard.fill"
        case .keypad: "circle.grid.3x3.fill"
        }
    }

    var title: String {
        switch self {
        case .dpad: "Directional pad"
        case .keyboard: "Keyboard"
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

// MARK: - Keyboard

struct KeyboardPadView: View {
    @Environment(AppModel.self) private var model
    @State private var shifted = false
    @State private var symbols = false

    // The last row of each layer sits between shift (or a spacer) and delete.
    private static let letters = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
    ] + ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { $0.map(String.init) }
    private static let others = [
        ["-", "/", ":", ";", "(", ")", "$", "&", "@", "\""],
        ["[", "]", "{", "}", "#", "%", "^", "*", "+", "="],
        ["_", "\\", "|", "~", "<", ">", "€", "£", "•"],
        [".", ",", "?", "!", "'", "`", "¥"],
    ]
    private let gap: CGFloat = 6

    var body: some View {
        VStack(spacing: 10) {
            controls
            GeometryReader { geo in
                let key = (geo.size.width - gap * 9) / 10
                // Shift and delete take up the space of the two keys row three is missing.
                let wide = key * 1.5 + gap / 2
                let rows = symbols ? Self.others : Self.letters
                VStack(spacing: gap) {
                    ForEach(0..<3) { i in
                        HStack(spacing: gap) { characters(rows[i], width: key) }
                    }
                    HStack(spacing: gap) {
                        if symbols {
                            Color.clear.frame(width: wide)
                        } else {
                            special(shifted ? "shift.fill" : "shift", label: "Shift", width: wide) { shifted.toggle() }
                        }
                        characters(rows[3], width: key)
                        KeyCap(shape: keyShape, repeats: true, accessibilityLabel: "Delete") { model.typeDelete() } label: {
                            Image(systemName: "delete.left").font(.system(size: 16, weight: .semibold))
                        }
                        .frame(width: wide)
                    }
                    HStack(spacing: gap) {
                        KeyCap(shape: keyShape, accessibilityLabel: symbols ? "Letters" : "Numbers and symbols") {
                            symbols.toggle()
                        } label: {
                            Text(symbols ? "ABC" : "123").font(.system(size: 15, weight: .semibold, design: .rounded))
                        }
                        .frame(width: wide)
                        KeyCap(shape: keyShape, accessibilityLabel: "Space") { model.type(" ") } label: {
                            Text("space").font(.system(size: 15, weight: .medium, design: .rounded)).foregroundStyle(Theme.secondary)
                        }
                    }
                }
                .frame(maxHeight: 5 * 64 + 4 * gap)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onDisappear { model.typed = "" }
    }

    /// A small D-pad for moving through results, with clear, delete and Return beside it.
    private var controls: some View {
        HStack(spacing: 20) {
            KeyCap(shape: keyShape, accessibilityLabel: "Clear") { model.typeClear() } label: {
                Text("Clear").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            .frame(height: 52)
            // Lines up with the delete key opposite.
            .frame(maxWidth: .infinity, maxHeight: 52 * 2 + 10, alignment: .top)
            DPadView().frame(width: 150, height: 150)
            VStack(spacing: 10) {
                KeyCap(shape: keyShape, repeats: true, accessibilityLabel: "Delete") { model.typeDelete() } label: {
                    Image(systemName: "delete.left").font(.system(size: 16, weight: .semibold))
                }
                .frame(height: 52)
                KeyCap(shape: keyShape, accessibilityLabel: "Return") { model.typeReturn() } label: {
                    Image(systemName: "return").font(.system(size: 16, weight: .semibold))
                }
                .frame(height: 52)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(height: 150)
    }

    private var keyShape: RoundedRectangle { RoundedRectangle(cornerRadius: 8, style: .continuous) }

    private func characters(_ row: [String], width: CGFloat) -> some View {
        ForEach(row, id: \.self) { c in
            let text = shifted && !symbols ? c.uppercased() : c
            KeyCap(shape: keyShape, accessibilityLabel: text) {
                model.type(text)
                shifted = false
            } label: {
                Text(text).font(.system(size: 19, weight: .medium, design: .rounded))
            }
            .frame(width: width)
        }
    }

    private func special(_ symbol: String, label: String, width: CGFloat, action: @escaping () -> Void) -> some View {
        KeyCap(shape: keyShape, accessibilityLabel: label, action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
        }
        .frame(width: width)
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
