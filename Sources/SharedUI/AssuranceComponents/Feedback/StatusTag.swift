import SwiftUI

// MARK: - Tag Style

enum StatusTagStyle {
    case success
    case warning
    case error
    case info
    case neutral
    case custom(foreground: Color, background: Color)

    var foreground: Color {
        switch self {
        case .success: return .appSuccess
        case .warning: return .appWarning
        case .error: return .appError
        case .info: return .appInfo
        case .neutral: return .appSecondaryText
        case .custom(let fg, _): return fg
        }
    }

    var background: Color {
        switch self {
        case .success: return .appSuccess.opacity(0.12)
        case .warning: return .appWarning.opacity(0.12)
        case .error: return .appError.opacity(0.12)
        case .info: return .appInfo.opacity(0.12)
        case .neutral: return Color.appSecondaryBackground
        case .custom(_, let bg): return bg
        }
    }
}

// MARK: - StatusTag

struct StatusTag: View {
    let text: String
    var style: StatusTagStyle = .neutral
    var icon: String? = nil

    var body: some View {
        HStack(spacing: AppSpacing.xxxs) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
            }
            Text(text)
                .font(.appCaption1.weight(.semibold))
        }
        .foregroundStyle(style.foreground)
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxxs)
        .background(
            Capsule().fill(style.background)
        )
    }
}

// MARK: - Badge

struct AppBadge: View {
    let count: Int
    var maxCount: Int = 99

    private var text: String {
        count > maxCount ? "\(maxCount)+" : "\(count)"
    }

    var body: some View {
        if count > 0 {
            Text(text)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, count > 9 ? 6 : 4)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.appError))
                .fixedSize()
        }
    }
}

// MARK: - StepIndicator

struct StepIndicator: View {
    let totalSteps: Int
    let currentStep: Int

    var body: some View {
        HStack(spacing: AppSpacing.xs) {
            ForEach(0..<totalSteps, id: \.self) { step in
                if step < currentStep {
                    Circle()
                        .fill(Color.brandPrimary)
                        .frame(width: 10, height: 10)
                } else if step == currentStep {
                    Capsule()
                        .fill(Color.brandPrimary)
                        .frame(width: 24, height: 10)
                } else {
                    Circle()
                        .fill(Color.appDisabled)
                        .frame(width: 10, height: 10)
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: currentStep)
    }
}

#Preview("Status & Badges") {
    VStack(spacing: 20) {
        HStack(spacing: 8) {
            StatusTag(text: "Active", style: .success, icon: AppIcons.checkmark)
            StatusTag(text: "Pending", style: .warning)
            StatusTag(text: "Failed", style: .error)
            StatusTag(text: "Draft", style: .neutral)
        }

        HStack(spacing: 16) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: AppIcons.notification)
                    .font(.title2)
                AppBadge(count: 5)
                    .offset(x: 8, y: -8)
            }

            ZStack(alignment: .topTrailing) {
                Image(systemName: AppIcons.message)
                    .font(.title2)
                AppBadge(count: 120)
                    .offset(x: 12, y: -8)
            }
        }

        StepIndicator(totalSteps: 4, currentStep: 1)
    }
    .padding()
}
