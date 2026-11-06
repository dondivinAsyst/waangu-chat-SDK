import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct DiscussionDeletionDialogModifier: ViewModifier {
    @Binding var context: DeletionDialogContext?
    let translationService: (any TranslationServiceProtocol)?
    let onPrimary: () -> Void
    let onDeleteLocalContent: () -> Void
    let onLeaveGroup: () -> Void
    let onExitKeepLocally: () -> Void
    let onExitDeleteLocally: () -> Void
    let onCancel: () -> Void
    
    func body(content: Content) -> some View {
        content.confirmationDialog(
            dialogTitle,
            isPresented: isPresented,
            titleVisibility: .visible
        ) {
            dialogButtons
        } message: {
            if let context {
                Text(dialogMessage(for: context))
            }
        }
    }
    
    private var dialogTitle: String {
        guard let context else { return "" }
        if context.intent == .exitGroup {
            return t(ChatTranslationKeys.DELETION_EXIT_GROUP)
        }
        return context.eligibility.intentTitle(for: context.intent)
    }
    
    private func dialogMessage(for context: DeletionDialogContext) -> String {
        if context.intent == .exitGroup {
            return context.exitGroupPromptMessage
        }
        return context.eligibility.userMessage
    }
    
    private var isPresented: Binding<Bool> {
        Binding(
            get: { context != nil },
            set: { isPresented in
                if !isPresented {
                    context = nil
                    onCancel()
                }
            }
        )
    }
    
    @ViewBuilder
    private var dialogButtons: some View {
        if let context {
            let eligibility = context.eligibility
            
            switch context.intent {
            case .exitGroup:
                exitGroupButtons()
            case .deleteFromList, .deleteFromGroupInfo:
                deleteButtons(eligibility: eligibility)
            }
        }
    }
    
    @ViewBuilder
    private func deleteButtons(eligibility: DeletionEligibility) -> some View {
        switch eligibility.suggestedAction {
        case .deleteNow:
            Button(t(ChatTranslationKeys.DELETION_DELETE), role: .destructive, action: onPrimary)
            Button(common("cancel"), role: .cancel, action: onCancel)
            
        case .deleteLocalContent:
            Button(clearOrDeleteLocalTitle(for: eligibility), role: .destructive, action: onPrimary)
            Button(common("cancel"), role: .cancel, action: onCancel)
            
        case .leaveGroupFirst:
            Button(t(ChatTranslationKeys.DELETION_LEAVE_GROUP), role: .destructive, action: onLeaveGroup)
            if eligibility.metadata.canDeleteLocalContent {
                Button(clearOrDeleteLocalTitle(for: eligibility), role: .destructive, action: onDeleteLocalContent)
            }
            Button(common("cancel"), role: .cancel, action: onCancel)
            
        case .leaveAndDelete:
            Button(t(ChatTranslationKeys.DELETION_LEAVE_GROUP), role: .destructive, action: onLeaveGroup)
            if eligibility.metadata.canDeleteLocalContent {
                Button(clearOrDeleteLocalTitle(for: eligibility), role: .destructive, action: onDeleteLocalContent)
            }
            Button(common("cancel"), role: .cancel, action: onCancel)
            
        case .cannotDelete:
            Button(common("ok"), role: .cancel, action: onCancel)
        }
    }
    
    private func clearOrDeleteLocalTitle(for eligibility: DeletionEligibility) -> String {
        eligibility.metadata.isMember ? t(ChatTranslationKeys.DELETION_CLEAR_MESSAGES) : t(ChatTranslationKeys.DELETION_DELETE_FOR_ME)
    }
    
    @ViewBuilder
    private func exitGroupButtons() -> some View {
        Button(t(ChatTranslationKeys.DELETION_EXIT), action: onExitKeepLocally)
        Button(t(ChatTranslationKeys.DELETION_EXIT_DELETE_FOR_ME), role: .destructive, action: onExitDeleteLocally)
        Button(common("cancel"), role: .cancel, action: onCancel)
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
    func discussionDeletionDialog(
        context: Binding<DeletionDialogContext?>,
        translationService: (any TranslationServiceProtocol)? = nil,
        onPrimary: @escaping () -> Void,
        onDeleteLocalContent: @escaping () -> Void,
        onLeaveGroup: @escaping () -> Void,
        onExitKeepLocally: @escaping () -> Void,
        onExitDeleteLocally: @escaping () -> Void,
        onCancel: @escaping () -> Void = {}
    ) -> some View {
        modifier(
            DiscussionDeletionDialogModifier(
                context: context,
                translationService: translationService,
                onPrimary: onPrimary,
                onDeleteLocalContent: onDeleteLocalContent,
                onLeaveGroup: onLeaveGroup,
                onExitKeepLocally: onExitKeepLocally,
                onExitDeleteLocally: onExitDeleteLocally,
                onCancel: onCancel
            )
        )
    }
}
