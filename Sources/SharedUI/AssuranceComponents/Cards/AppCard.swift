import SwiftUI

// MARK: - AppCard

struct AppCard<Content: View>: View {
    var padding: EdgeInsets = .appCard
    var shadow: AppShadow = .sm
    var cornerRadius: CGFloat = AppCornerRadius.md

    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color.appCard)
        )
        .appShadow(shadow)
    }
}

// MARK: - ListRow

struct ListRow: View {
    var leadingIcon: String? = nil
    var leadingIconColor: Color = .brandPrimary
    let title: String
    var subtitle: String? = nil
    var trailingText: String? = nil
    var showChevron: Bool = true
    var action: (() -> Void)? = nil

    var body: some View {
        Button {
            action?()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if let leadingIcon {
                    Image(systemName: leadingIcon)
                        .font(.body)
                        .foregroundStyle(leadingIconColor)
                        .frame(width: 32, height: 32)
                        .background(leadingIconColor.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appBody)
                        .foregroundStyle(Color.appText)
                    if let subtitle {
                        Text(subtitle)
                            .font(.appFootnote)
                            .foregroundStyle(Color.appSecondaryText)
                    }
                }

                Spacer()

                if let trailingText {
                    Text(trailingText)
                        .font(.appSubheadline)
                        .foregroundStyle(Color.appSecondaryText)
                }

                if showChevron {
                    Image(systemName: AppIcons.chevronRight)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appTertiaryText)
                }
            }
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Expandable Section

struct ExpandableSection<Content: View>: View {
    let title: String
    @State private var isExpanded: Bool

    @ViewBuilder let content: () -> Content

    init(title: String, initiallyExpanded: Bool = false, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self._isExpanded = State(initialValue: initiallyExpanded)
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                HStack {
                    Text(title)
                        .font(.appHeadline)
                        .foregroundStyle(Color.appText)
                    Spacer()
                    Image(systemName: AppIcons.chevronDown)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, AppSpacing.sm)
            }

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - SectionHeader

struct SectionHeader: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.appHeadline)
                .foregroundStyle(Color.appText)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.appButtonSmall)
                        .foregroundStyle(Color.brandPrimary)
                }
            }
        }
    }
}

#Preview("Cards & Rows") {
    ScrollView {
        VStack(spacing: 20) {
            AppCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Card Title").font(.appHeadline)
                    Text("Card content goes here.").font(.appBody).foregroundStyle(Color.appSecondaryText)
                }
            }

            SectionHeader(title: "Settings", actionTitle: "Edit") {}

            VStack(spacing: 0) {
                ListRow(leadingIcon: AppIcons.person, title: "Profile", subtitle: "Manage your account")
                Divider().padding(.leading, 52)
                ListRow(leadingIcon: AppIcons.notification, title: "Notifications", trailingText: "On")
                Divider().padding(.leading, 52)
                ListRow(leadingIcon: AppIcons.lock, title: "Privacy")
            }

            ExpandableSection(title: "More Info", initiallyExpanded: true) {
                Text("Expanded content here")
                    .font(.appBody)
                    .foregroundStyle(Color.appSecondaryText)
                    .padding(.bottom, 8)
            }
        }
        .padding()
    }
}
