import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// The line above the composer while the other side is typing.
///
/// Nothing here decides when to disappear: entries expire in `TypingStore`, and
/// this view renders whatever is still standing.
struct TypingIndicatorView: View {
    let users: [TypingUser]
    let isGroup: Bool
    let translator: (any TranslationServiceProtocol)?
    /// Bumped by the view model on locale change, so the sentence re-resolves.
    var localeToken: Int = 0

    var body: some View {
        if let text = TypingPhrase.text(for: users, isGroup: isGroup, translator: translator) {
            HStack(spacing: 6) {
                TypingDots()
                Text(text)
                    .font(.caption)
                    .foregroundColor(AppColors.primary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .transition(.opacity)
        }
    }
}

/// Three dots rising in sequence — the shape everyone reads as "still typing".
/// Also Waangu Copilot's "thinking" indicator.
struct TypingDots: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 5, height: 5)
                    .offset(y: animating ? -3 : 0)
                    .opacity(animating ? 1 : 0.4)
                    .animation(
                        .easeInOut(duration: 0.4)
                            .repeatForever(autoreverses: true)
                            // Staggered rather than three dots moving as one.
                            .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
    }
}
