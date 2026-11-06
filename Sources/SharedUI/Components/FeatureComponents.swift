// MARK: - FeatureItemView
import SwiftUI

// Local icon view used by wallet features. Renders an SF Symbol or asset
// centered on a rounded-rectangle fill, or — when `showsBackground` is false —
// the same icon tinted with `color` (no tile).
public struct FeatureIconView: View {
    let name: String
    let color: Color
    let size: CGFloat
    let cornerRadius: CGFloat
    let iconColor: Color
    let showsBackground: Bool

    public init(
        _ name: String,
        color: Color = .primary,
        size: CGFloat = 24,
        cornerRadius: CGFloat = 8,
        iconColor: Color = .white,
        showsBackground: Bool = true
    ) {
        self.name = name
        self.color = color
        self.size = size
        self.cornerRadius = cornerRadius
        self.iconColor = iconColor
        self.showsBackground = showsBackground
    }

    private var foregroundTint: Color {
        showsBackground ? iconColor : color
    }

    public var body: some View {
        let bgSize = max(size + 16, 48)
        ZStack {
            if showsBackground {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color)
                    .frame(width: bgSize, height: bgSize)
            }

            if name.hasPrefix("http://") || name.hasPrefix("https://") {
                AsyncImage(url: URL(string: name)) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                    case .failure:
                        Image(systemName: "questionmark.square")
                            .resizable()
                            .scaledToFit()
                            .frame(width: size, height: size)
                            .foregroundColor(foregroundTint)
                    @unknown default:
                        EmptyView()
                    }
                }
            } else if UIImage(systemName: name) != nil {
                Image(systemName: name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(foregroundTint)
            } else if UIImage(named: name) != nil {
                Image(name)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(foregroundTint)
            } else {
                Image(systemName: "questionmark.square")
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .foregroundColor(foregroundTint)
            }
        }
        .frame(width: bgSize, height: bgSize)
    }
}



// MARK: - Feature Header (shared)
public struct FeatureHeader: View {
    let title: String
    let large: Bool
    @Environment(\.dismiss) private var dismiss

    public init(_ title: String, large: Bool = false) {
        self.title = title
        self.large = large
    }

    public var body: some View {
        if large {
            ZStack(alignment: .top) {
                Rectangle()
                    .fill(AppColors.primary)
                    .ignoresSafeArea(edges: .top)

                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Text(title)
                        .foregroundColor(.white)

                    Spacer()
                }

                .frame(maxWidth: .infinity)
            }
        } else {
            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(AppColors.primary)
        }
    }
}

// MARK: - Shared Send Money Components

public struct SendMenuTabButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    public init(title: String, icon: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(Color(hex: 0x5460A5))

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.75))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(height: 34)
            }
            .frame(width: 138, height: 94)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppColors.cardBackground.opacity(isSelected ? 0.98 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? Color.green.opacity(0.45) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

public struct InputField: View {
    let placeholder: String
    @Binding var text: String
    var trailingText: String? = nil
    var trailingSystemImage: String? = nil
    /// When set, the trailing SF Symbol is tappable (e.g. open contacts).
    var onTrailingTap: (() -> Void)? = nil
    var isEditable: Bool = true
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isFocused: Bool

    public init(
        placeholder: String,
        text: Binding<String>,
        trailingText: String? = nil,
        trailingSystemImage: String? = nil,
        onTrailingTap: (() -> Void)? = nil,
        isEditable: Bool = true,
        onFocusChange: ((Bool) -> Void)? = nil
    ) {
        self.placeholder = placeholder
        self._text = text
        self.trailingText = trailingText
        self.trailingSystemImage = trailingSystemImage
        self.onTrailingTap = onTrailingTap
        self.isEditable = isEditable
        self.onFocusChange = onFocusChange
    }

    public var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .font(.system(size: 16, weight: .medium))
                .focused($isFocused)
                .disabled(!isEditable)

            if let systemName = trailingSystemImage {
                if let onTrailingTap {
                    Button(action: onTrailingTap) {
                        Image(systemName: systemName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.primary.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary.opacity(0.7))
                }
            } else if let trailingText {
                Text(trailingText)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.7))
            }
        }
        .opacity(isEditable ? 1 : 0.72)
        .contentShape(Rectangle())
        .onTapGesture {
            if isEditable { isFocused = true }
        }
        .onChange(of: isFocused) { new in
            onFocusChange?(new)
        }
        .padding(.horizontal, 12)
        .frame(height: 56)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(light: 0xE5E8EF, dark: 0x2E3A4A), lineWidth: 1.2)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(AppColors.cardBackground)
                )
        )
    }
}

public struct MultilineInputField: View {
    let placeholder: String
    @Binding var text: String
    var onFocusChange: ((Bool) -> Void)? = nil

    @FocusState private var isFocused: Bool

    public init(placeholder: String, text: Binding<String>, onFocusChange: ((Bool) -> Void)? = nil) {
        self.placeholder = placeholder
        self._text = text
        self.onFocusChange = onFocusChange
    }

    public var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .font(.system(size: 16, weight: .medium))
                .scrollContentBackground(.hidden)
                .padding(8)
                .focused($isFocused)

            if text.isEmpty {
                Text(placeholder)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
            }
        }
        .frame(height: 140)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(light: 0xE5E8EF, dark: 0x2E3A4A), lineWidth: 1.2)
                .background(RoundedRectangle(cornerRadius: 10).fill(AppColors.cardBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture { isFocused = true }
        .onChange(of: isFocused) { new in onFocusChange?(new) }
    }
}

public struct RadioChoice: View {
    let title: String
    let selected: Bool
    let onTap: () -> Void

    public init(title: String, selected: Bool, onTap: @escaping () -> Void) {
        self.title = title
        self.selected = selected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .stroke(selected ? AppColors.primary : Color.gray.opacity(0.6), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if selected {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 12, height: 12)
                    }
                }

                Text(title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.primary.opacity(0.72))
            }
        }
        .buttonStyle(.plain)
    }
}

public struct LabelValueRow: View {
    let label: String
    let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary.opacity(0.65))

                Spacer()

                HStack(spacing: 8) {
                    Image(systemName: "hexagon.fill")
                        .foregroundColor(Color.green.opacity(0.75))
                    Text(value)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.primary.opacity(0.75))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 74)

            Rectangle()
                .fill(AppColors.white)
                .frame(height: 1)
        }
        .background(AppColors.cardBackground)
    }
}

public struct PrimaryActionButton: View {
    let title: String
    let enabled: Bool
    var systemImage: String? = nil
    var action: () -> Void = {}

    public init(title: String, enabled: Bool, systemImage: String? = nil, action: @escaping () -> Void = {}) {
        self.title = title
        self.enabled = enabled
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .bold))
                }

                Text(title)
                    .font(.system(size: 18, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(enabled ? AppColors.primary : Color.gray.opacity(0.7))
            )
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.84)
    }
}
