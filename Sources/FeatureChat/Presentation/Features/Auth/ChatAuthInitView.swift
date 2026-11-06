//
//  ChatAuthInitView.swift
//  FeatureChat
//
//  Created by Don divin on 5/20/26.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
public struct ChatAuthInitView: View {
    
    @StateObject private var viewModel: ChatAuthInitViewModel
    private let onAuthSuccess: () -> Void
    private let translationService: (any TranslationServiceProtocol)?
    
    @State private var rotationAngle: Double = 0
    @State private var dotScale: [CGFloat] = [1.0, 1.0, 1.0]
    @State private var animationID = UUID()
    
    public init(
        viewModel: ChatAuthInitViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAuthSuccess: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.translationService = translationService
        self.onAuthSuccess = onAuthSuccess
    }
    
    public var body: some View {
        ZStack {
            AppColors.background
                .ignoresSafeArea()
            
            // Content based on auth state
            switch viewModel.authState {
            case .initializing:
                VStack {
                    Spacer()
                    initializingView
                    Spacer()
                }
                .padding(.horizontal, 32)
                
            case .authenticated:
                // This state is handled by onAuthSuccess callback
                EmptyView()
                
            case .failed:
                failedView
            }
        }
        .task {
            await viewModel.checkAuthenticationStatus()
        }
        .onChange(of: viewModel.authState) { newState in
            if case .authenticated = newState {
                onAuthSuccess()
            } else if case .initializing = newState {
                // Reset animations when state changes to initializing
                resetAnimations()
            }
        }
    }
    
    // MARK: - Initializing View
    
    private var initializingView: some View {
        VStack(spacing: 24) {
            // Animated logo or icon
            ZStack {
                // Background circle
                Circle()
                    .stroke(
                        AppColors.primary.opacity(0.2),
                        lineWidth: 4
                    )
                    .frame(width: 80, height: 80)
                
                // Animated rotating circle
                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(
                        AppColors.primary,
                        style: StrokeStyle(
                            lineWidth: 4,
                            lineCap: .round
                        )
                    )
                    .frame(width: 80, height: 80)
                    .rotationEffect(.degrees(rotationAngle))
                    .onAppear {
                        startRotationAnimation()
                    }
                
                // Message icon
                Image(systemName: "message.fill")
                    .font(.system(size: 32))
                    .foregroundColor(AppColors.primary)
            }
            .padding(.bottom, 8)
            .id(animationID) // Force view recreation when animationID changes
            
            // Status text
            VStack(spacing: 8) {
                Text(t(ChatTranslationKeys.AUTH_INITIALIZING_CHAT))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.titleDark)
                
                Text(t(ChatTranslationKeys.AUTH_VERIFYING_SESSION))
                    .font(.subheadline)
                    .foregroundColor(AppColors.subtitleGray)
            }
            
            // Animated dots
            HStack(spacing: 8) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(AppColors.primary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(dotScale[index])
                        .onAppear {
                            animateDot(at: index)
                        }
                }
            }
            .padding(.top, 8)
            .id(animationID) // Force view recreation when animationID changes
        }
    }
    
    // MARK: - Failed View
    
    /// Sans pastille teintée ni rouge : une icône au trait dit ce qui a échoué,
    /// le texte dit quoi faire, et le seul geste possible est un vrai bouton,
    /// en bas, à portée du pouce.
    private var failedView: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 20) {
                Image(systemName: failureSymbol)
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(AppColors.primary)
                    .accessibilityHidden(true)
                
                VStack(spacing: 8) {
                    Text(t(ChatTranslationKeys.AUTH_START_FAILED_TITLE))
                        .font(.title3.weight(.semibold))
                        .foregroundColor(AppColors.titleDark)
                    
                    Text(failureDetail)
                        .font(.subheadline)
                        .foregroundColor(AppColors.subtitleGray)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 32)
            .accessibilityElement(children: .combine)
            
            Spacer()
            
            retryButton
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
        }
    }
    
    private var retryButton: some View {
        Button {
            Task { await viewModel.retry() }
        } label: {
            ZStack {
                // Le libellé garde sa place pendant l'essai : le bouton ne
                // change pas de taille quand le spinner le remplace.
                Text(common("retry"))
                    .opacity(viewModel.isRetrying ? 0 : 1)
                if viewModel.isRetrying {
                    ProgressView()
                        .tint(.white)
                }
            }
            .font(.system(size: 17, weight: .semibold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppColors.primary)
            )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isRetrying)
        .accessibilityLabel(common("retry"))
    }
    
    private var failureSymbol: String {
        switch viewModel.failure {
        case .session:
            return "exclamationmark.bubble"
        case .network, nil:
            return "wifi.exclamationmark"
        }
    }
    
    private var failureDetail: String {
        switch viewModel.failure {
        case .session:
            return t(ChatTranslationKeys.AUTH_START_FAILED_SESSION)
        case .network, nil:
            return t(ChatTranslationKeys.AUTH_START_FAILED_NETWORK)
        }
    }
    
    // MARK: - Helper Methods
    
    private func resetAnimations() {
        // Reset all animation states
        rotationAngle = 0
        dotScale = [1.0, 1.0, 1.0]
        animationID = UUID() // Change ID to force view recreation
    }
    
    private func startRotationAnimation() {
        withAnimation(
            .linear(duration: 1)
                .repeatForever(autoreverses: false)
        ) {
            rotationAngle = 360
        }
    }
    
    private func animateDot(at index: Int) {
        withAnimation(
            .easeInOut(duration: 0.6)
                .repeatForever()
                .delay(Double(index) * 0.2)
        ) {
            dotScale[index] = 0.5
        }
        
        // Alternate back to original size
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3 + Double(index) * 0.2) {
            withAnimation(
                .easeInOut(duration: 0.6)
                    .repeatForever()
                    .delay(Double(index) * 0.2)
            ) {
                dotScale[index] = 1.0
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

