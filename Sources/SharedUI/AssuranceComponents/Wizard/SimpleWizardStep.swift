import SwiftUI

/// A step powered entirely by a `[WizardField]` array.
/// Validation, view rendering, and review items are all auto-generated.
/// Use `customValidation` for cross-field rules beyond per-field checks.
public struct SimpleWizardStep: WizardStepConfiguration {
    public let id: String
    public let title: String
    public let subtitle: String?
    let fields: [WizardField]
    public let visibilityCondition: (WizardFormState) -> Bool
    public let validate: (WizardFormState) -> [WizardValidationResult]

   public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        fields: [WizardField],
        visibilityCondition: @escaping (WizardFormState) -> Bool = { _ in true },
        customValidation: ((WizardFormState) -> [WizardValidationResult])? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.fields = fields
        self.visibilityCondition = visibilityCondition

        let capturedFields = fields
        let capturedExtra = customValidation
        self.validate = { state in
            var errors = capturedFields.compactMap { $0.validate(state: state) }
            if let extra = capturedExtra {
                errors.append(contentsOf: extra(state).filter { !$0.isValid })
            }
            return errors.isEmpty ? [.valid] : errors
        }
    }

    public func makeBody(
        formState: Binding<WizardFormState>,
        validationErrors: [WizardValidationResult]
    ) -> AnyView {
        AnyView(
            VStack(spacing: AppSpacing.md) {
                ForEach(fields) { field in
                    field.makeView(formState: formState, errors: validationErrors)
                }
            }
        )
    }

    public func buildReviewItems(state: WizardFormState) -> [WizardReviewItem] {
        fields.compactMap { $0.reviewItem(state: state, stepID: id) }
    }
}
