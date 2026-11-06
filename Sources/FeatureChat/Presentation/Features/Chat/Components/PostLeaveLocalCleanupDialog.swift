import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct PostLeaveLocalCleanupDialogModifier: ViewModifier {
    @Binding var context: PostLeaveLocalCleanupContext?
    let translationService: (any TranslationServiceProtocol)?
    let onKeepLocally: () -> Void
    let onDeleteLocally: () -> Void
    
    func body(content: Content) -> some View {
        content.confirmationDialog(
            t(ChatTranslationKeys.POST_LEAVE_TITLE),
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            Button(t(ChatTranslationKeys.POST_LEAVE_KEEP_CHAT)) {
                onKeepLocally()
            }
            Button(t(ChatTranslationKeys.POST_LEAVE_DELETE_FOR_ME), role: .destructive) {
                onDeleteLocally()
            }
            Button(common("cancel"), role: .cancel) {
                context = nil
                onKeepLocally()
            }
        } message: {
            if let message = context?.userMessage {
                Text(message)
            }
        }
    }
    
    private var isPresented: Binding<Bool> {
        Binding(
            get: { context != nil },
            set: { isPresented in
                if !isPresented {
                    context = nil
                }
            }
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

@available(iOS 16.0, *)
extension View {
    func postLeaveLocalCleanupDialog(
        context: Binding<PostLeaveLocalCleanupContext?>,
        translationService: (any TranslationServiceProtocol)? = nil,
        onKeepLocally: @escaping () -> Void,
        onDeleteLocally: @escaping () -> Void
    ) -> some View {
        modifier(
            PostLeaveLocalCleanupDialogModifier(
                context: context,
                translationService: translationService,
                onKeepLocally: onKeepLocally,
                onDeleteLocally: onDeleteLocally
            )
        )
    }
}
