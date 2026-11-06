//
//  BrandedToggle.swift
//  SharedUI
//
//  A reusable toggle component that uses the app's primary brand color
//  for consistent styling across the application.
//

import SwiftUI

/// A branded toggle that uses AppColors.primary for the tint color
public struct BrandedToggle: View {
    @Binding private var isOn: Bool
    private let label: AnyView
    private let labelColor: Color?
    private let iconColor: Color?
    
    // MARK: - Simple Text Label
    
    /// Creates a branded toggle with a simple text label
    /// - Parameters:
    ///   - title: The text to display as the label
    ///   - isOn: Binding to the toggle state
    ///   - labelColor: Optional color for the label text (defaults to primary text color)
    public init(
        _ title: String,
        isOn: Binding<Bool>,
        labelColor: Color? = nil
    ) {
        self._isOn = isOn
        self.labelColor = labelColor
        self.iconColor = nil
        
        if let color = labelColor {
            self.label = AnyView(Text(title).foregroundColor(color))
        } else {
            self.label = AnyView(Text(title))
        }
    }
    
    // MARK: - Text with Icon Label
    
    /// Creates a branded toggle with a text and icon label
    /// - Parameters:
    ///   - title: The text to display as the label
    ///   - systemImage: The SF Symbol name for the icon
    ///   - isOn: Binding to the toggle state
    ///   - labelColor: Optional color for the label text
    ///   - iconColor: Optional color for the icon
    public init(
        _ title: String,
        systemImage: String,
        isOn: Binding<Bool>,
        labelColor: Color? = nil,
        iconColor: Color? = nil
    ) {
        self._isOn = isOn
        self.labelColor = labelColor
        self.iconColor = iconColor
        
        var labelView = Label(title, systemImage: systemImage)
        
        if let textColor = labelColor {
            self.label = AnyView(
                labelView
                    .foregroundColor(textColor)
            )
        } else if let iconColorValue = iconColor {
            self.label = AnyView(
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                        .foregroundColor(iconColorValue)
                }
            )
        } else {
            self.label = AnyView(labelView)
        }
    }
    
    // MARK: - Custom Label (Full Control)
    
    /// Creates a branded toggle with a fully custom label
    /// - Parameters:
    ///   - isOn: Binding to the toggle state
    ///   - label: A view builder that creates the toggle label
    /// - Note: When using custom label, use view modifiers directly on your label for styling
    public init<Label: View>(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) {
        self._isOn = isOn
        self.label = AnyView(label())
        self.labelColor = nil
        self.iconColor = nil
    }
    
    public var body: some View {
        Toggle(isOn: $isOn) {
            label
        }
        .tint(AppColors.primary)
    }
}

// MARK: - Preview

struct BrandedToggle_Previews: PreviewProvider {
    static var previews: some View {
        List {
            Section {
                // Simple toggles
                BrandedToggle("Simple Toggle", isOn: .constant(true))
                BrandedToggle("Disabled Toggle", isOn: .constant(false))
                
                // With custom label color
                BrandedToggle(
                    "Custom Label Color",
                    isOn: .constant(true),
                    labelColor: .red
                )
                
                // With icon (default colors)
                BrandedToggle(
                    "Toggle with Icon",
                    systemImage: "bell.slash",
                    isOn: .constant(true)
                )
                
                // With custom icon color
                BrandedToggle(
                    "Custom Icon Color",
                    systemImage: "lock",
                    isOn: .constant(true),
                    iconColor: .orange
                )
                
                // With both custom colors
                BrandedToggle(
                    "Both Custom Colors",
                    systemImage: "star.fill",
                    isOn: .constant(true),
                    labelColor: .purple,
                    iconColor: .yellow
                )
                
                // Custom label with full control
                BrandedToggle(isOn: .constant(true)) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Toggle with Subtitle")
                            .font(.subheadline)
                        Text("This is a description of what the toggle does")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Branded Toggle Examples")
            }
        }
        .previewDisplayName("Light Mode")
        
        List {
            Section {
                BrandedToggle("Simple Toggle", isOn: .constant(true))
                BrandedToggle(
                    "Custom Colors",
                    systemImage: "moon.fill",
                    isOn: .constant(true),
                    labelColor: .cyan,
                    iconColor: .yellow
                )
            }
        }
        .preferredColorScheme(.dark)
        .previewDisplayName("Dark Mode")
    }
}
