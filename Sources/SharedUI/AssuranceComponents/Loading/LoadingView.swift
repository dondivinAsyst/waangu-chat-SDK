import SwiftUI

// MARK: - Full Screen Loading Overlay

public struct LoadingOverlay: View {
    var message: String? = nil
    public init(message: String? = nil) {
        self.message = message
    }
    public  var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: AppSpacing.md) {
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(.white)

                if let message {
                    Text(message)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.white)
                }
            }
            .padding(AppSpacing.xl)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                    .fill(.ultraThinMaterial)
            )
        }
    }
}

// MARK: - Inline Loader

struct InlineLoader: View {
    var message: String = "Loading..."

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            ProgressView()
            Text(message)
                .font(.appFootnote)
                .foregroundStyle(Color.appSecondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, AppSpacing.lg)
    }
}

// MARK: - Modifier for full-screen loading

struct LoadingOverlayModifier: ViewModifier {
    let isLoading: Bool
    var message: String? = nil

    func body(content: Content) -> some View {
        content.overlay {
            if isLoading {
                LoadingOverlay(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
   public func loadingOverlay(_ isLoading: Bool, message: String? = nil) -> some View {
        modifier(LoadingOverlayModifier(isLoading: isLoading, message: message))
    }
}

#Preview("Loading") {
    VStack {
        Text("Content behind loader")
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .loadingOverlay(true, message: "Please wait...")
}
