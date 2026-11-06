// MARK: - SharedUI/Components/PinEntryOverlay.swift

import SwiftUI

// MARK: - Pin keypad models

private enum PinKeypadItem: Identifiable {
    case digit(String, letters: String?)
    case spacer
    case backspace

    var id: String {
        switch self {
        case .digit(let n, _): return "d-\(n)"
        case .spacer: return "spacer"
        case .backspace: return "bs"
        }
    }
}

// MARK: - PinEntryOverlay

/// Numeric PIN entry (phone-style keypad + dot indicators). Intended for a fixed-height bottom sheet or full-width column.
public struct PinEntryOverlay: View {

    public let title: String
    public let digitCount: Int
    @Binding public var pin: String
    public let onComplete: (String) -> Void
    public let onDismiss: () -> Void

    private static let keypadRows: [[PinKeypadItem]] = [
        [.digit("1", letters: nil), .digit("2", letters: "ABC"), .digit("3", letters: "DEF")],
        [.digit("4", letters: "GHI"), .digit("5", letters: "JKL"), .digit("6", letters: "MNO")],
        [.digit("7", letters: "PQRS"), .digit("8", letters: "TUV"), .digit("9", letters: "WXYZ")],
        [.spacer, .digit("0", letters: nil), .backspace],
    ]

    public init(
        title: String = "Please Enter Your Password",
        digitCount: Int = 6,
        pin: Binding<String>,
        onComplete: @escaping (String) -> Void = { _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.title = title
        self.digitCount = max(4, min(12, digitCount))
        self._pin = pin
        self.onComplete = onComplete
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            dotIndicator
                .padding(.top, 16)
                .padding(.bottom, 12)
            Spacer(minLength: 4)
            keypad
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PinEntryTokens.screenBackground)
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PinEntryTokens.title)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 44)

            HStack {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(PinEntryTokens.closeIcon)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Close"))

                Spacer()
            }
            .padding(.horizontal, 8)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity)
        .background(PinEntryTokens.headerBackground)
    }

    // MARK: Dots

    private var dotIndicator: some View {
        HStack(spacing: 14) {
            ForEach(0..<digitCount, id: \.self) { index in
                Circle()
                    .fill(index < pin.count ? PinEntryTokens.dotFilled : PinEntryTokens.dotEmpty)
                    .frame(width: 12, height: 12)
                    .animation(.easeInOut(duration: 0.18), value: pin.count)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 18)
        .background(
            Capsule()
                .fill(PinEntryTokens.capsuleFill)
                .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 3)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("PIN entry")
        .accessibilityValue("\(pin.count) of \(digitCount) digits entered")
    }

    // MARK: Keypad

    private var keypad: some View {
        VStack(spacing: 14) {
            ForEach(Self.keypadRows.indices, id: \.self) { rowIndex in
                HStack(spacing: 14) {
                    ForEach(Self.keypadRows[rowIndex]) { item in
                        keypadCell(item)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keypadCell(_ item: PinKeypadItem) -> some View {
        switch item {
        case .spacer:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: PinEntryTokens.keyHeight)

        case .digit(let number, let letters):
            Button {
                appendDigit(number)
            } label: {
                VStack(spacing: 2) {
                    Text(number)
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(PinEntryTokens.keyDigit)
                    if let letters, !letters.isEmpty {
                        Text(letters)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(PinEntryTokens.keyLetters)
                            .tracking(0.6)
                    } else {
                        Text(" ")
                            .font(.system(size: 9))
                            .foregroundStyle(.clear)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: PinEntryTokens.keyHeight)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PinEntryTokens.keyBackground)
                        .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 2)
                        .shadow(color: Color.black.opacity(0.04), radius: 1, x: 0, y: 1)
                )
            }
            .buttonStyle(PinKeyButtonStyle())
            .accessibilityLabel(letters.map { "\(number), \($0)" } ?? number)

        case .backspace:
            Button {
                deleteLastDigit()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(PinEntryTokens.backspaceIcon)
                    .frame(maxWidth: .infinity)
                    .frame(height: PinEntryTokens.keyHeight)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("Delete"))
        }
    }

    private func appendDigit(_ character: String) {
        guard pin.count < digitCount else { return }
        let filtered = character.filter { $0.isNumber }
        guard let c = filtered.first else { return }
        pin.append(c)
        if pin.count == digitCount {
            onComplete(pin)
        }
    }

    private func deleteLastDigit() {
        guard !pin.isEmpty else { return }
        pin.removeLast()
    }
}

// MARK: - Tokens

private enum PinEntryTokens {
    /// Raised above the sheet in dark mode — a fixed white made the title,
    /// which turns near-white there, invisible.
    static let headerBackground = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    static let screenBackground = Color(light: 0xE8E9ED, dark: 0x1C1C1E)
    static let title = Color(light: 0x111111, dark: 0xF2F2F7)
    static let closeIcon = Color(light: 0x3A3A3C, dark: 0xEBEBF5)
    static let capsuleFill = Color(light: 0xFFFFFF, dark: 0x2C2C2E)
    /// Entered digits use app primary; empty slots stay soft gray.
    static var dotFilled: Color { AppColors.primary }
    static let dotEmpty = Color(light: 0xD1D1D6, dark: 0x48484A)
    /// Close to the iOS dark keypad: the digits turn white in dark mode, and
    /// on a fixed white key they disappeared.
    static let keyBackground = Color(light: 0xFFFFFF, dark: 0x3A3A3C)
    static let keyDigit = Color(light: 0x000000, dark: 0xFFFFFF)
    static let keyLetters = Color(light: 0x8E8E93, dark: 0xAEAEB2)
    static let backspaceIcon = Color(light: 0x3A3A3C, dark: 0xAEAEB2)
    static let keyHeight: CGFloat = 56
}

// MARK: - Button style (subtle press)

private struct PinKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
