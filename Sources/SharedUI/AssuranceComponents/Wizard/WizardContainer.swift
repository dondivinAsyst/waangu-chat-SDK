import SwiftUI

public struct WizardContainer: View {
    @ObservedObject var viewModel: WizardViewModel

    /// Fond de l'assistant.
    ///
    /// C'était `#F4F7FC`, une valeur claire en dur : l'assistant restait blanc
    /// en mode sombre, texte compris, sur toutes les surfaces qui l'emploient.
    /// Le jeton suit le thème et vaut la même teinte claire qu'avant.
    private let pageBg = AppColors.walletCanvas
    
    public init(viewModel: WizardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            WizardProgressBar(
                progress: viewModel.progress,
                stepLabel: viewModel.stepLabel,
                totalSteps: viewModel.totalVisibleSteps,
                currentStep: viewModel.currentStepIndex,
                lastAutosaveDate: viewModel.lastAutosaveDate,
                onJump: { viewModel.jumpToStep(index: $0) }
            )

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 0).id("wizard_scroll_anchor")

                        VStack(alignment: .leading, spacing: AppSpacing.lg) {
                            stepHeader
                            stepContent
                        }
                        .padding(EdgeInsets.appScreen)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id(viewModel.currentStepIndex)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: viewModel.currentStepIndex) { _, _ in
                    withAnimation {
                        proxy.scrollTo("wizard_scroll_anchor", anchor: .top)
                    }
                }
                .onChange(of: viewModel.firstInvalidField) { _, fieldKey in
                    guard let fieldKey else { return }
                    withAnimation {
                        proxy.scrollTo(fieldKey, anchor: .center)
                    }
                }
            }

            Divider()

            WizardNavigationBar(
                canGoBack: viewModel.canGoBack,
                isSubmitting: viewModel.isSubmitting,
                nextTitle: viewModel.nextButtonTitle,
                nextIcon: viewModel.nextButtonIcon,
                onBack: { viewModel.goBack() },
                onNext: { viewModel.goForward() }
            )
        }
        .background(pageBg.ignoresSafeArea())
        .overlay { completionOverlay }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: viewModel.isCompleted)
    }

    // MARK: - Step Header

    @ViewBuilder
    private var stepHeader: some View {
        if viewModel.isOnReviewStep {
            EmptyView()
        } else if let step = viewModel.currentStep {
            VStack(alignment: .leading, spacing: AppSpacing.xxxs) {
                Text(step.title)
                    .font(.appTitle2)
                    .foregroundStyle(Color.appText)

                if let subtitle = step.subtitle {
                    Text(subtitle)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }
            }
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        if viewModel.isOnReviewStep {
            VStack(alignment: .leading, spacing: AppSpacing.lg) {
                if let header = viewModel.reviewHeaderBuilder?(viewModel.formState) {
                    header
                }
                
                WizardReviewStep(
                    items: viewModel.reviewItems,
                    onEditStep: { viewModel.jumpToStep(id: $0) }
                )
            }
        } else if let step = viewModel.currentStep {
            step.makeBody(
                formState: $viewModel.formState,
                validationErrors: viewModel.currentValidationErrors
            )
        }
    }

    // MARK: - Completion Overlay

    @ViewBuilder
    private var completionOverlay: some View {
        if viewModel.isCompleted {
            VStack(spacing: AppSpacing.lg) {
                Image(systemName: AppIcons.checkCircle)
                    .font(.system(size: 64))
                    .foregroundStyle(Color.appSuccess)

                Text(viewModel.completionTitle)
                    .font(.appTitle2)
                    .foregroundStyle(Color.appText)

                Text(viewModel.completionMessage)
                    .font(.appSubheadline)
                    .foregroundStyle(Color.appSecondaryText)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, AppSpacing.xxl)

                CustomButton(
                    title: "Terminé",
                    size: .large,
                    isLoading: viewModel.isSubmitting,
                    action: { viewModel.onFinished?() }
                )
                .padding(.horizontal, AppSpacing.xxl)
                .padding(.top, AppSpacing.md)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(pageBg.ignoresSafeArea())
            .transition(.opacity.combined(with: .scale(scale: 0.95)))
        }
    }
}
