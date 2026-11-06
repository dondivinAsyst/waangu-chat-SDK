import SwiftUI
import Combine

@MainActor
public final class WizardViewModel: ObservableObject {

    // MARK: - Published State

    @Published public private(set) var allSteps: [AnyWizardStep]
    @Published public var formState: WizardFormState
    @Published public private(set) var currentStepIndex: Int = 0
    @Published public private(set) var navigationDirection: NavigationDirection = .forward
    @Published public private(set) var currentValidationErrors: [WizardValidationResult] = []
    @Published public private(set) var hasAttemptedForward: Bool = false
    @Published public private(set) var lastAutosaveDate: Date? = nil
    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var isCompleted: Bool = false

    // MARK: - Configuration

    public let includesReviewStep: Bool
    public let completionTitle: String
    public let completionMessage: String
    public var skipCompletion: Bool
    public var submitTitle: String
    public var reviewItemBuilder: ((WizardFormState) -> [WizardReviewItem])?
    public var reviewHeaderBuilder: ((WizardFormState) -> AnyView)?
    public var onComplete: ((WizardFormState) -> Void)?
    public var onFinished: (() -> Void)?

    // MARK: - Private

    private var autosaveTimer: AnyCancellable?
    private var autosaveSnapshot: WizardFormState = [:]

    // MARK: - Enums

    public enum NavigationDirection {
        case forward, backward
    }

    // MARK: - Computed Properties

    public var visibleSteps: [AnyWizardStep] {
        allSteps.filter { $0.visibilityCondition(formState) }
    }

    public var totalVisibleSteps: Int {
        visibleSteps.count + (includesReviewStep ? 1 : 0)
    }

    public var stepLabel: String {
        "Étape \(currentStepIndex + 1) sur \(totalVisibleSteps)"
    }

    public var progress: Double {
        guard totalVisibleSteps > 0 else { return 0 }
        return Double(currentStepIndex + 1) / Double(totalVisibleSteps)
    }

    public var currentStep: AnyWizardStep? {
        let steps = visibleSteps
        guard currentStepIndex >= 0, currentStepIndex < steps.count else { return nil }
        return steps[currentStepIndex]
    }

    public var isOnReviewStep: Bool {
        includesReviewStep && currentStepIndex == visibleSteps.count
    }

    public var isFirstStep: Bool { currentStepIndex == 0 }

    public var isLastStep: Bool {
        currentStepIndex == totalVisibleSteps - 1
    }

    public var canGoBack: Bool { currentStepIndex > 0 }

    public var nextButtonTitle: String {
        if isOnReviewStep || (!includesReviewStep && isLastStep) { return submitTitle }
        if includesReviewStep && currentStepIndex == visibleSteps.count - 1 { return "Vérifier" }
        return "Suivant"
    }

    public var nextButtonIcon: String? {
        if isOnReviewStep || (!includesReviewStep && isLastStep) {
            return AppIcons.checkmark
        }
        return AppIcons.chevronRight
    }

    public var reviewItems: [WizardReviewItem] {
        if let builder = reviewItemBuilder {
            return builder(formState)
        }
        return visibleSteps.flatMap { $0.buildReviewItems(state: formState) }
    }

    public var firstInvalidField: String? {
        for result in currentValidationErrors {
            if case .invalid(let field, _) = result {
                return field
            }
        }
        return nil
    }

    // MARK: - Init

    public init(
        steps: [any WizardStepConfiguration],
        initialFormState: WizardFormState = [:],
        includesReviewStep: Bool = false,
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
        self.allSteps = steps.map(AnyWizardStep.init)
        self.formState = initialFormState
        self.includesReviewStep = includesReviewStep
        self.skipCompletion = skipCompletion
        self.submitTitle = submitTitle
        self.completionTitle = completionTitle
        self.completionMessage = completionMessage
        self.reviewItemBuilder = reviewItemBuilder
        self.reviewHeaderBuilder = reviewHeaderBuilder
        self.onComplete = onComplete
        self.onFinished = onFinished
        self.autosaveSnapshot = initialFormState

        startAutosaveTimer(interval: autosaveInterval)
    }

    deinit {
        autosaveTimer?.cancel()
    }

    // MARK: - Navigation

    public func goForward() {
        if isOnReviewStep {
            submit()
            return
        }

        hasAttemptedForward = true
        runValidation()

        guard currentValidationErrors.isEmpty else { return }

        if !includesReviewStep && isLastStep {
            submit()
            return
        }

        withAnimation(.easeInOut(duration: 0.3)) {
            navigationDirection = .forward
            currentStepIndex += 1
            hasAttemptedForward = false
            currentValidationErrors = []
        }
    }

    public func goBack() {
        guard canGoBack else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            navigationDirection = .backward
            currentStepIndex -= 1
            hasAttemptedForward = false
            currentValidationErrors = []
        }
    }

    public func jumpToStep(id: String) {
        guard let index = visibleSteps.firstIndex(where: { $0.id == id }) else { return }
        jumpToStep(index: index)
    }

    public func jumpToStep(index: Int) {
        guard index >= 0, index < totalVisibleSteps else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            navigationDirection = index > currentStepIndex ? .forward : .backward
            currentStepIndex = index
            hasAttemptedForward = false
            currentValidationErrors = []
            performAutosave()
        }
    }

    public func jumpToReview() {
        guard includesReviewStep else { return }
        let reviewIndex = visibleSteps.count
        withAnimation(.easeInOut(duration: 0.3)) {
            navigationDirection = .forward
            currentStepIndex = reviewIndex
            hasAttemptedForward = false
            currentValidationErrors = []
        }
    }

    // MARK: - Validation

    public func runValidation() {
        guard let step = currentStep else {
            currentValidationErrors = []
            return
        }
        currentValidationErrors = step.validate(formState).filter { !$0.isValid }
    }

    public func validateField(_ fieldKey: String) {
        guard hasAttemptedForward, let step = currentStep else { return }
        let results = step.validate(formState)

        currentValidationErrors.removeAll {
            if case .invalid(let field, _) = $0, field == fieldKey { return true }
            return false
        }

        let fieldErrors = results.filter {
            if case .invalid(let field, _) = $0, field == fieldKey { return true }
            return false
        }

        currentValidationErrors.append(contentsOf: fieldErrors)
    }

    // MARK: - Dynamic Step Management

    public func insertStep(_ step: any WizardStepConfiguration, after existingID: String) {
        guard let index = allSteps.firstIndex(where: { $0.id == existingID }) else { return }
        allSteps.insert(AnyWizardStep(step), at: index + 1)
    }

    public func removeStep(id: String) {
        allSteps.removeAll { $0.id == id }
        let maxIndex = max(0, totalVisibleSteps - 1)
        if currentStepIndex > maxIndex {
            currentStepIndex = maxIndex
        }
    }

    public func replaceSteps(_ newSteps: [any WizardStepConfiguration]) {
        allSteps = newSteps.map(AnyWizardStep.init)
        currentStepIndex = 0
        hasAttemptedForward = false
        currentValidationErrors = []
    }

    // MARK: - Submission

    private func submit() {
        guard !isSubmitting else { return }
        isSubmitting = true
        performAutosave()

        if skipCompletion {
            isSubmitting = false
            onComplete?(formState)
            onFinished?()
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self else { return }
            self.isSubmitting = false
            self.isCompleted = true
            self.onComplete?(self.formState)
        }
    }

    // MARK: - Autosave

    private func startAutosaveTimer(interval: TimeInterval) {
        autosaveTimer = Timer.publish(every: interval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.performAutosave()
            }
    }

    public func performAutosave() {
        autosaveSnapshot = formState
        lastAutosaveDate = Date()
    }

    public func restoreFromAutosave() {
        guard !autosaveSnapshot.isEmpty else { return }
        formState = autosaveSnapshot
    }
}
