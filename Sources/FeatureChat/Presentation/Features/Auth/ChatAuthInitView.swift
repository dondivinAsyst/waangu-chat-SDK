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
    /// Leaves chat for the host app. No button when nil.
    private let onClose: (() -> Void)?
    private let translationService: (any TranslationServiceProtocol)?
    
    // Failure screen: staggered entrance and the automatic retry countdown.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var failureShown = false
    @State private var retryCountdown: Int?
    @State private var retryDelay = 1
    @State private var autoRetryAttempt = 0
    @State private var autoRetryTask: Task<Void, Never>?

    /// Seconds before each automatic retry; the last one repeats.
    private static let autoRetryDelays = [5, 10, 20, 30]

    public init(
        viewModel: ChatAuthInitViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onClose: (() -> Void)? = nil,
        onAuthSuccess: @escaping () -> Void
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.translationService = translationService
        self.onClose = onClose
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
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .topLeading) {
            if let onClose {
                backButton(action: onClose)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: viewModel.authState)
        .task {
            await viewModel.checkAuthenticationStatus()
        }
        .onChange(of: viewModel.authState) { newState in
            if case .authenticated = newState {
                onAuthSuccess()
            }
        }
    }
    
    // MARK: - Back

    /// The same chevron the chat list uses to leave chat, so nobody is stuck here while chat
    /// loads or after it fails. The system reads the chevron to VoiceOver as "Back".
    private func backButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(AppColors.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.leading, 8)
    }

    // MARK: - Initializing View
    
    /// The logo on a white tile, three dots that rise one after another, and the status text.
    /// No spinner. With reduce motion the dots stay still.
    private var initializingView: some View {
        VStack(spacing: 28) {
            logoTile

            LoadingDots(color: AppColors.primary, animated: !reduceMotion)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(t(ChatTranslationKeys.AUTH_INITIALIZING_CHAT))
                    .font(.headline)
                    .foregroundColor(AppColors.titleDark)

                Text(t(ChatTranslationKeys.AUTH_VERIFYING_SESSION))
                    .font(.subheadline)
                    .foregroundColor(AppColors.subtitleGray)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    /// The logo is dark blue on a transparent background: a white tile keeps it readable in dark
    /// mode too, like an app icon.
    private var logoTile: some View {
        Group {
            if let logo = Self.logo {
                Image(uiImage: logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 62)
            } else {
                Image(systemName: "message.fill")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundColor(AppColors.primary)
            }
        }
        .frame(width: 96, height: 96)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(AppColors.primary.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: AppColors.primary.opacity(0.18), radius: 18, x: 0, y: 10)
        .accessibilityHidden(true)
    }

    private static let logo = UIImage(named: "waangu_logo", in: .module, with: nil)
    
    // MARK: - Failed View
    
    /// A picture of the subject (two chat bubbles and a status badge) on a soft primary wash,
    /// then a left-aligned title and one line of text, then the automatic retry and the button
    /// at thumb height. Parts arrive one after another; primary colour only.
    private var failedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            failureBand
                .modifier(Arrive(shown: failureShown, index: 0, reduceMotion: reduceMotion))

            VStack(alignment: .leading, spacing: 10) {
                Text(t(ChatTranslationKeys.AUTH_START_FAILED_TITLE))
                    .font(.title2.weight(.bold))
                    .foregroundColor(AppColors.titleDark)

                Text(failureDetail)
                    .font(.body)
                    .foregroundColor(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .accessibilityElement(children: .combine)
            .modifier(Arrive(shown: failureShown, index: 1, reduceMotion: reduceMotion))

            Spacer(minLength: 24)

            VStack(spacing: 16) {
                if let retryCountdown {
                    autoRetryRow(remaining: retryCountdown)
                        .transition(.opacity)
                }

                CustomButton(
                    title: common("retry"),
                    icon: "arrow.clockwise",
                    isLoading: viewModel.isRetrying,
                    isDisabled: viewModel.isRetrying,
                    action: retryNow
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .modifier(Arrive(shown: failureShown, index: 2, reduceMotion: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            failureShown = true
            scheduleAutoRetry()
        }
        .onDisappear {
            failureShown = false
            cancelAutoRetry()
            autoRetryAttempt = 0
        }
        .onChange(of: viewModel.isRetrying) { retrying in
            // A retry that failed again leaves this screen up: count down to the next one.
            if !retrying, viewModel.authState == .failed { scheduleAutoRetry() }
        }
    }

    // MARK: Picture band

    private var failureBand: some View {
        bubblesIllustration
            .frame(maxWidth: .infinity)
            .frame(height: 230)
            .background(bandWash.ignoresSafeArea(edges: .top))
            .accessibilityHidden(true)
    }

    /// A soft primary wash with two blurred blobs and a few dots, fading into the background.
    private var bandWash: some View {
        ZStack {
            LinearGradient(
                colors: [AppColors.primary.opacity(0.16), AppColors.primary.opacity(0.03)],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(AppColors.primary.opacity(0.22))
                .frame(width: 200, height: 200)
                .blur(radius: 60)
                .offset(x: -120, y: -30)
            Circle()
                .fill(AppColors.primary.opacity(0.16))
                .frame(width: 160, height: 160)
                .blur(radius: 50)
                .offset(x: 130, y: 50)
            ForEach(Array(Self.bandDots.enumerated()), id: \.offset) { index, dot in
                Circle()
                    .fill(AppColors.primary.opacity(dot.opacity))
                    .frame(width: dot.size, height: dot.size)
                    .offset(x: dot.x, y: dot.y + (failureShown || reduceMotion ? 0 : 14))
                    .opacity(failureShown || reduceMotion ? 1 : 0)
                    .animation(
                        reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.9)
                            .delay(0.15 + Double(index) * 0.07),
                        value: failureShown
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
    }

    private static let bandDots: [(x: CGFloat, y: CGFloat, size: CGFloat, opacity: Double)] = [
        (-150, -60, 6, 0.35), (-95, 70, 4, 0.30), (140, -70, 5, 0.30),
        (160, 30, 7, 0.25), (-40, -95, 4, 0.25), (85, 95, 5, 0.30)
    ]

    /// Two tilted chat bubbles, the front one in the primary colour, with a badge saying what
    /// went wrong.
    private var bubblesIllustration: some View {
        ZStack {
            // Incoming bubble, behind.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppColors.cardBackground)
                .frame(width: 156, height: 66)
                .overlay(alignment: .leading) {
                    VStack(alignment: .leading, spacing: 8) {
                        Capsule().fill(AppColors.subtitleGray.opacity(0.35)).frame(width: 92, height: 8)
                        Capsule().fill(AppColors.subtitleGray.opacity(0.22)).frame(width: 60, height: 8)
                    }
                    .padding(.leading, 18)
                }
                .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 8)
                .rotationEffect(.degrees(-7))
                .offset(x: -38, y: -22)

            // Outgoing bubble, in front, waiting to be sent.
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary.opacity(0.85), AppColors.primary],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: 138, height: 60)
                .overlay {
                    HStack(spacing: 7) {
                        ForEach(0..<3, id: \.self) { _ in
                            Circle().fill(Color.white.opacity(0.75)).frame(width: 9, height: 9)
                        }
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: AppColors.primary.opacity(0.35), radius: 16, x: 0, y: 10)
                .rotationEffect(.degrees(5))
                .offset(x: 34, y: 26)

            // Status badge on the front bubble's corner.
            Image(systemName: failureSymbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(
                        LinearGradient(
                            colors: [AppColors.primary.opacity(0.9), AppColors.primary],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
                )
                .overlay(Circle().stroke(AppColors.background, lineWidth: 4))
                .shadow(color: AppColors.primary.opacity(0.4), radius: 10, x: 0, y: 6)
                .offset(x: 100, y: -6)
                .scaleEffect(failureShown || reduceMotion ? 1 : 0.6)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.65).delay(0.25),
                    value: failureShown
                )
        }
        .scaleEffect(failureShown || reduceMotion ? 1 : 0.92)
        .animation(reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.5), value: failureShown)
    }

    // MARK: Automatic retry

    /// "Trying again in 5 s" over a thin bar that empties as the seconds pass.
    private func autoRetryRow(remaining: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(t(ChatTranslationKeys.AUTH_RETRY_COUNTDOWN, args: ["\(remaining)"]))
                .font(.footnote)
                .foregroundColor(AppColors.subtitleGray)
                .monospacedDigit()

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(AppColors.primary.opacity(0.12))
                    Capsule()
                        .fill(AppColors.primary)
                        .frame(width: proxy.size.width * CGFloat(remaining) / CGFloat(max(retryDelay, 1)))
                        .animation(reduceMotion ? nil : .linear(duration: 1), value: remaining)
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func scheduleAutoRetry() {
        cancelAutoRetry()
        let delay = Self.autoRetryDelays[min(autoRetryAttempt, Self.autoRetryDelays.count - 1)]
        autoRetryAttempt += 1
        retryDelay = delay
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { retryCountdown = delay }
        autoRetryTask = Task { @MainActor in
            for remaining in stride(from: delay, to: 0, by: -1) {
                retryCountdown = remaining
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { retryCountdown = nil }
            await viewModel.retry()
        }
    }

    private func cancelAutoRetry() {
        autoRetryTask?.cancel()
        autoRetryTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { retryCountdown = nil }
    }

    private func retryNow() {
        cancelAutoRetry()
        Task { await viewModel.retry() }
    }

    private var failureSymbol: String {
        switch viewModel.failure {
        case .session:
            return "exclamationmark"
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
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

/// Three dots that rise and brighten one after another, driven by the clock so they never drift
/// out of step. Still dots when not animated.
private struct LoadingDots: View {
    let color: Color
    let animated: Bool

    private let period: Double = 1.2

    var body: some View {
        if animated {
            TimelineView(.animation) { timeline in
                dots(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        } else {
            dots(at: nil)
        }
    }

    private func dots(at time: TimeInterval?) -> some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { index in
                let lift = time.map { wave($0, index: index) } ?? 0
                Circle()
                    .fill(color)
                    .frame(width: 10, height: 10)
                    .opacity(0.35 + 0.65 * lift)
                    .offset(y: -7 * lift)
            }
        }
        .frame(height: 20)
    }

    /// 0…1: each dot rises during its own third of the period, then rests.
    private func wave(_ time: TimeInterval, index: Int) -> Double {
        let phase = (time / period - Double(index) * 0.18).truncatingRemainder(dividingBy: 1)
        let p = phase < 0 ? phase + 1 : phase
        guard p < 0.5 else { return 0 }
        return sin(p * 2 * .pi)
    }
}

/// One part of the failure screen arriving: fades in and slides up a little, ~70 ms after the
/// part before it (ease-out-cubic). With reduce motion it is simply there.
private struct Arrive: ViewModifier {
    let shown: Bool
    let index: Int
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .animation(
                reduceMotion ? nil : .timingCurve(0.33, 1, 0.68, 1, duration: 0.5).delay(Double(index) * 0.07),
                value: shown
            )
    }
}

