import SwiftUI

@available(iOS 16.0, *)
struct DiscussionActionLoadingOverlay: ViewModifier {
    let isLoading: Bool
    let message: String?
    
    func body(content: Content) -> some View {
        content
            .disabled(isLoading)
            .overlay {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.large)
                            if let message, !message.isEmpty {
                                Text(message)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
    }
}

@available(iOS 16.0, *)
extension View {
    func discussionActionLoadingOverlay(isLoading: Bool, message: String?) -> some View {
        modifier(DiscussionActionLoadingOverlay(isLoading: isLoading, message: message))
    }
}
