import SwiftUI

// MARK: - BottomSheet

struct AppBottomSheet<Content: View>: View {
    @Binding var isPresented: Bool
    var title: String? = nil
    var showDragIndicator: Bool = true

    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .bottom) {
            if isPresented {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                    .onTapGesture { dismiss() }
                    .transition(.opacity)

                VStack(spacing: 0) {
                    if showDragIndicator {
                        Capsule()
                            .fill(Color.appDisabled)
                            .frame(width: 36, height: 5)
                            .padding(.top, AppSpacing.sm)
                    }

                    if let title {
                        HStack {
                            Text(title)
                                .font(.appTitle3)
                                .foregroundStyle(Color.appText)
                            Spacer()
                            AppIconButton(icon: AppIcons.close, size: 32, iconSize: 14, tint: .appSecondaryText, background: .appSecondaryBackground) {
                                dismiss()
                            }
                        }
                        .padding(.horizontal, AppSpacing.md)
                        .padding(.top, AppSpacing.md)
                    }

                    content()
                        .padding(.top, title == nil ? AppSpacing.md : AppSpacing.sm)
                        .padding(.bottom, AppSpacing.lg)
                        .padding(.horizontal, AppSpacing.md)
                }
                .background(
                    RoundedRectangle(cornerRadius: AppCornerRadius.xl)
                        .fill(Color.appBackground)
                        .ignoresSafeArea(edges: .bottom)
                )
                .transition(.move(edge: .bottom))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: isPresented)
    }

    private func dismiss() {
        isPresented = false
    }
}

// MARK: - Modifier

struct BottomSheetModifier<SheetContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var title: String? = nil
    @ViewBuilder let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content.overlay {
            AppBottomSheet(isPresented: $isPresented, title: title, content: sheetContent)
        }
    }
}

extension View {
    func appBottomSheet<Content: View>(isPresented: Binding<Bool>, title: String? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        modifier(BottomSheetModifier(isPresented: isPresented, title: title, sheetContent: content))
    }
}

//#Preview("BottomSheet") {
//    struct Wrapper: View {
//        @State private var show = false
//        var body: some View {
//            VStack {
//                CustomButton(title: "Show Sheet") { show = true }
//                    .padding()
//            }
//            .frame(maxWidth: .infinity, maxHeight: .infinity)
//            .appBottomSheet(isPresented: $show, title: "Choose Option") {
//                VStack(spacing: 0) {
//                    ListRow(leadingIcon: AppIcons.camera, title: "Take Photo", showChevron: false) {}
//                    Divider().padding(.leading, 52)
//                    ListRow(leadingIcon: AppIcons.gallery, title: "Choose from Gallery", showChevron: false) {}
//                    Divider().padding(.leading, 52)
//                    ListRow(leadingIcon: AppIcons.delete, leadingIconColor: .appError, title: "Remove Photo", showChevron: false) {}
//                }
//            }
//        }
//    }
//    return Wrapper()
//}
