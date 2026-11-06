import SwiftUI

// MARK: - Toast Type

enum ToastType {
    case success
    case error
    case warning
    case info

    var icon: String {
        switch self {
        case .success: return AppIcons.checkCircle
        case .error: return AppIcons.error
        case .warning: return AppIcons.warning
        case .info: return AppIcons.info
        }
    }

    var tint: Color {
        switch self {
        case .success: return .appSuccess
        case .error: return .appError
        case .warning: return .appWarning
        case .info: return .appInfo
        }
    }
}

// MARK: - Toast Item

struct ToastItem: Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    var message: String? = nil
    var duration: TimeInterval = 3

    static func == (lhs: ToastItem, rhs: ToastItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Toast View

struct ToastView: View {
    let toast: ToastItem

    var body: some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: toast.type.icon)
                .font(.title3)
                .foregroundStyle(toast.type.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(toast.title)
                    .font(.appHeadline)
                    .foregroundStyle(Color.appText)
                if let message = toast.message {
                    Text(message)
                        .font(.appFootnote)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                .fill(Color.appBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                .stroke(toast.type.tint.opacity(0.3), lineWidth: 1)
        )
        .appShadow(.lg)
        .padding(.horizontal, AppSpacing.md)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var toast: ToastItem?

    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast {
                    ToastView(toast: toast)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onTapGesture { dismiss() }
                        .gesture(
                            DragGesture(minimumDistance: 20)
                                .onEnded { value in
                                    if value.translation.height < -10 { dismiss() }
                                }
                        )
                        .padding(.top, AppSpacing.xxs)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: toast)
            .onChange(of: toast) { _, newValue in
                task?.cancel()
                guard let newValue else { return }
                task = Task {
                    try? await Task.sleep(for: .seconds(newValue.duration))
                    if !Task.isCancelled { dismiss() }
                }
            }
    }

    private func dismiss() {
        withAnimation { toast = nil }
    }
}

extension View {
    func toast(_ item: Binding<ToastItem?>) -> some View {
        modifier(ToastModifier(toast: item))
    }
}

//// MARK: - Preview
//
//#Preview("Toast") {
//    struct Wrapper: View {
//        @State private var toast: ToastItem?
//
//        var body: some View {
//            VStack(spacing: 16) {
//                CustomButton(title: "Success", style: .primary) {
//                    toast = ToastItem(type: .success, title: "Saved!", message: "Your changes have been saved.")
//                }
//                CustomButton(title: "Error", style: .destructive) {
//                    toast = ToastItem(type: .error, title: "Failed", message: "Something went wrong.")
//                }
//                CustomButton(title: "Warning", style: .outline) {
//                    toast = ToastItem(type: .warning, title: "Warning", message: "Check your input.")
//                }
//                CustomButton(title: "Info", style: .secondary) {
//                    toast = ToastItem(type: .info, title: "Info", message: "New update available.")
//                }
//            }
//            .padding()
//            .toast($toast)
//        }
//    }
//    return Wrapper()
//}
