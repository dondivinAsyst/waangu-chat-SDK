import SwiftUI

// MARK: - Menu Selection Field (Dropdown)

/// A labeled dropdown that presents a list of options in a Menu.
public struct MenuSelectionField: View {
    let label: String
    @Binding var selection: String?
    let placeholder: String
    let options: [String]

    public init(
        label: String,
        selection: Binding<String?>,
        placeholder: String = "Choose",
        options: [String]
    ) {
        self.label = label
        self._selection = selection
        self.placeholder = placeholder
        self.options = options
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(AppColors.iconLabel.opacity(0.9))

            Menu {
                ForEach(options, id: \.self) { option in
                    Button(option) {
                        selection = option
                    }
                }
            } label: {
                MenuSelectionFieldLabel(
                    text: selection ?? placeholder,
                    isPlaceholder: selection == nil
                )
            }
        }
    }
}

/// Styled text field matching the form (same look as dropdowns).
public struct FormTextField: View {
    let label: String?
    let placeholder: String
    @Binding var text: String
    var keyboardType: UIKeyboardType = .default

    public init(
        placeholder: String,
        text: Binding<String>,
        label: String? = nil,
        keyboardType: UIKeyboardType = .default
    ) {
        self.placeholder = placeholder
        self._text = text
        self.label = label
        self.keyboardType = keyboardType
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let label = label {
                Text(label)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppColors.iconLabel.opacity(0.9))
            }
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .font(.system(size: 16))
                .foregroundColor(AppColors.iconLabel)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.cardBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppColors.iconLabel.opacity(0.2), lineWidth: 1)
                )
        }
    }
}

/// Internal label used by `MenuSelectionField`; exposed for reuse in custom menus.
public struct MenuSelectionFieldLabel: View {
    let text: String
    var isPlaceholder: Bool = false

    public init(text: String, isPlaceholder: Bool = false) {
        self.text = text
        self.isPlaceholder = isPlaceholder
    }

    public var body: some View {
        HStack {
            Text(text)
                .font(.system(size: 16))
                .foregroundColor(isPlaceholder ? AppColors.iconLabel.opacity(0.5) : AppColors.iconLabel)

            Spacer()

            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppColors.iconLabel.opacity(0.4))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.iconLabel.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Terms Checkbox

/// Checkbox with leading text and a tappable link (e.g. "I accept the" + "terms and conditions").
public struct TermsCheckboxView: View {
    @Binding var isAccepted: Bool
    let leadingText: String
    let linkText: String
    var onLinkTap: (() -> Void)? = nil

    public init(isAccepted: Binding<Bool>, leadingText: String, linkText: String, onLinkTap: (() -> Void)? = nil) {
        self._isAccepted = isAccepted
        self.leadingText = leadingText
        self.linkText = linkText
        self.onLinkTap = onLinkTap
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                isAccepted.toggle()
            } label: {
                Image(systemName: isAccepted ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(isAccepted ? AppColors.primary : AppColors.iconLabel.opacity(0.5))
            }
            .buttonStyle(.plain)

            HStack(spacing: 4) {
                Text(leadingText)
                    .font(.system(size: 15))
                    .foregroundColor(AppColors.iconLabel)

                Button(linkText) {
                    onLinkTap?()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.primary)
                .underline()
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Primary Action Button

/// Full-width primary-style button for main actions (e.g. "START", "Continue", "Submit").
public struct PrimaryButton: View {
    let title: String
    var action: () -> Void = {}

    public init(title: String, action: @escaping () -> Void = {}) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
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
    }
}

// MARK: - Info / Warning Banner

/// A compact banner with an icon and message (e.g. "Please set your preferences.").
public struct InfoBannerView: View {
    let message: String
    var systemImage: String = "exclamationmark.triangle.fill"
    var accentColor: Color = Color.orange.opacity(0.85)

    private var iconBackgroundTint: Color {
        accentColor.opacity(0.12)
    }

    public init(message: String, systemImage: String = "exclamationmark.triangle.fill", accentColor: Color = Color.orange.opacity(0.85)) {
        self.message = message
        self.systemImage = systemImage
        self.accentColor = accentColor
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 20))
                .foregroundColor(accentColor)
                .frame(width: 36, height: 36)
                .background(Circle().fill(iconBackgroundTint))

            Text(message)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(AppColors.iconLabel)

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppColors.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(accentColor.opacity(0.35), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// MARK: - Step flow (multi-step forms)

/// Section title for step forms (e.g. "Owner", "Vehicle identification").
public struct FormSectionHeader: View {
    let title: String

    public init(title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.system(size: 17, weight: .bold))
            .foregroundColor(AppColors.iconLabel)
            .padding(.top, 8)
    }
}

/// "Step X of N" text for use in toolbar (e.g. step flow, KYC).
public struct StepIndicatorView: View {
    let current: Int
    let total: Int

    public init(current: Int, total: Int) {
        self.current = current
        self.total = total
    }

    public var body: some View {
        Text("Step \(current) of \(total)")
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(AppColors.iconLabel.opacity(0.8))
    }
}

/// Horizontal step progress: circles with checkmark (completed), number (current), or grey number (upcoming); labels below.
public struct StepProgressBarView: View {
    let currentStep: Int
    let totalSteps: Int
    let stepLabels: [String]

    public init(currentStep: Int, totalSteps: Int, stepLabels: [String]) {
        self.currentStep = currentStep
        self.totalSteps = totalSteps
        self.stepLabels = stepLabels
    }

    public var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(1...totalSteps, id: \.self) { step in
                    stepCircle(step: step)
                    if step < totalSteps {
                        Rectangle()
                            .fill(step < currentStep ? AppColors.primary : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 8)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
                    Text(label)
                        .font(.system(size: 10, weight: index + 1 == currentStep ? .semibold : .regular))
                        .foregroundColor(index + 1 == currentStep ? AppColors.primary : AppColors.iconLabel.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private func stepCircle(step: Int) -> some View {
        let isCompleted = step < currentStep
        let isCurrent = step == currentStep
        return ZStack {
            Circle()
                .fill(isCompleted || isCurrent ? AppColors.primary : Color.gray.opacity(0.3))
                .frame(width: 28, height: 28)
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
            } else {
                Text("\(step)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: 36, height: 36)
    }
}

// MARK: - Gradient screen shell (wallet-style forms)

/// Scroll + app gradient background; use for multi-field flows that match Send Money / wallet screens.
public struct FormGradientScreen<Content: View>: View {
    @ViewBuilder var content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                content()
                    .padding(.top, 8)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 24)
            }
            .background(AppColors.backgroundGradient)
        }
        .background(AppColors.backgroundGradient.ignoresSafeArea())
    }
}

// MARK: - Horizontal icon tab bar

/// Scrollable row of `SendMenuTabButton`-style tabs; reusable for any `Identifiable` tab enum.
public struct HorizontalIconTabBar<Item: Identifiable & Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    let icon: (Item) -> String

    public init(items: [Item], selection: Binding<Item>, title: @escaping (Item) -> String, icon: @escaping (Item) -> String) {
        self.items = items
        self._selection = selection
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        SendMenuTabButton(
                            title: title(item),
                            icon: icon(item),
                            isSelected: selection == item
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                selection = item
                            }
                            proxy.scrollTo(item.id, anchor: .center)
                        }
                        .id(item.id)
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 6)
            }
        }
    }
}

// MARK: - Labeled card + lookup value

/// Icon + small caps title + custom body; use for resolved recipient, verification summary, etc.
public struct FormLabeledCard<Content: View>: View {
    let title: String
    var systemImage: String = "person.crop.circle.fill"
    var iconTint: Color = AppColors.primary.opacity(0.85)
    @ViewBuilder let content: () -> Content

    public init(title: String, systemImage: String = "person.crop.circle.fill", iconTint: Color = AppColors.primary.opacity(0.85), @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.content = content
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 22))
                .foregroundColor(iconTint)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.3)

                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.cardBackground)
                .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(light: 0xECEEF3, dark: 0x2E3A4A), lineWidth: 1.1)
        )
    }
}

/// Typical async lookup row: loading, success text, failure message, or placeholder.
public struct FormLookupValueBody: View {
    var isLoading: Bool
    var loadingMessage: String = "Loading…"
    var resolvedValue: String?
    var lookupFailed: Bool
    var failureMessage: String = "No match found"
    var placeholder: String = "—"

    public init(isLoading: Bool, loadingMessage: String = "Loading…", resolvedValue: String? = nil, lookupFailed: Bool, failureMessage: String = "No match found", placeholder: String = "—") {
        self.isLoading = isLoading
        self.loadingMessage = loadingMessage
        self.resolvedValue = resolvedValue
        self.lookupFailed = lookupFailed
        self.failureMessage = failureMessage
        self.placeholder = placeholder
    }

    public var body: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .scaleEffect(0.95)
                    Text(loadingMessage)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.secondary)
                }
            } else if let name = resolvedValue, !name.isEmpty {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if lookupFailed {
                Text(failureMessage)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
            } else {
                Text(placeholder)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.secondary.opacity(0.85))
            }
        }
    }
}

// MARK: - Validation hint

/// Inline footnote under fields (e.g. invalid amount).
public struct FormValidationHint: View {
    let message: String
    var color: Color = .red

    public init(message: String, color: Color = .red) {
        self.message = message
        self.color = color
    }

    public var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Floating capsule action (FAB)

/// Primary capsule button pinned over content (e.g. “Add recipient”).
public struct FormFloatingCapsuleButton: View {
    let title: String
    var systemImage: String = "plus"
    let action: () -> Void

    public init(title: String, systemImage: String = "plus", action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .bold))
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                Capsule()
                    .fill(AppColors.primary)
                    .shadow(color: Color.black.opacity(0.18), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
        .padding(.trailing, 18)
        .padding(.bottom, 18)
    }
}
