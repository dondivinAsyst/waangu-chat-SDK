import SwiftUI

/// Single entry point for creating a wizard.
/// - `onComplete`: Called during submission for data processing (API calls, saving).
/// - `onFinished`: Called when the user taps "Terminé" on the completion screen (navigation/dismiss).
public struct AppWizard: View {
    @StateObject private var viewModel: WizardViewModel

public init(
        steps: [any WizardStepConfiguration],
        initialFormState: WizardFormState = [:],
        includesReviewStep: Bool = true,
        skipCompletion: Bool = false,
        submitTitle: String = "Soumettre",
        autosaveInterval: TimeInterval = 10,
        completionTitle: String = "Terminé !",
        completionMessage: String = "Vos informations ont été soumises avec succès.",
        reviewItemBuilder: ((WizardFormState) -> [WizardReviewItem])? = nil,
        reviewHeaderBuilder: ((WizardFormState) -> AnyView)? = nil,
        onComplete: ((WizardFormState) -> Void)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: WizardViewModel(
            steps: steps,
            initialFormState: initialFormState,
            includesReviewStep: includesReviewStep,
            skipCompletion: skipCompletion,
            submitTitle: submitTitle,
            autosaveInterval: autosaveInterval,
            completionTitle: completionTitle,
            completionMessage: completionMessage,
            reviewItemBuilder: reviewItemBuilder,
            reviewHeaderBuilder: reviewHeaderBuilder,
            onComplete: onComplete,
            onFinished: onFinished
        ))
    }

    public var body: some View {
        WizardContainer(viewModel: viewModel)
    }
}
