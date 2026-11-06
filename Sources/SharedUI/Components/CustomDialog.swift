// MARK: - SharedUI/Components/CustomDialog.swift

import SwiftUI

// MARK: - Dialog Configuration
public struct DialogConfiguration {
    public let title: String
    public let message: String?
    public let style: DialogStyle
    public let buttons: [DialogButton]
    public let animation: DialogAnimation
    
    public init(
        title: String,
        message: String? = nil,
        style: DialogStyle = .standard,
        buttons: [DialogButton],
        animation: DialogAnimation = .default
    ) {
        self.title = title
        self.message = message
        self.style = style
        self.buttons = buttons
        self.animation = animation
    }
}

// MARK: - Dialog Style
public enum DialogStyle {
    case standard
    case destructive
    case success
    case warning
    
    var titleColor: Color {
        switch self {
        case .standard, .destructive: return AppColors.textPrimary
        case .success: return AppColors.primary
        case .warning: return .orange
        }
    }

    /// Teinte de l'icône d'en-tête. Le rouge système signale le destructif ;
    /// le reste vient du jeu de jetons.
    var iconTint: Color {
        switch self {
        case .standard, .success: return AppColors.primary
        case .destructive: return .red
        case .warning: return .orange
        }
    }
    
    var iconName: String? {
        switch self {
        case .standard: return nil
        case .destructive: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.circle.fill"
        }
    }
}

// MARK: - Dialog Button
public struct DialogButton: Identifiable {
    public let id = UUID()
    public let title: String
    public let role: ButtonRole
    public let action: () -> Void
    
    public init(title: String, role: ButtonRole = .standard, action: @escaping () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
    
    public enum ButtonRole {
        case standard
        case primary
        case destructive
        case cancel
        
        var backgroundColor: Color {
            switch self {
            case .standard, .cancel: return AppColors.primary.opacity(0.10)
            case .primary: return AppColors.primary
            // Teinte légère plutôt qu'un aplat rouge : l'action destructive se
            // lit sans devenir le bouton le plus attirant du dialogue.
            case .destructive: return Color.red.opacity(0.12)
            }
        }

        var foregroundColor: Color {
            switch self {
            case .standard, .cancel: return AppColors.primary
            case .primary: return .white
            case .destructive: return .red
            }
        }
        
        var borderColor: Color? {
            switch self {
            case .standard, .cancel: return AppColors.chipBorder
            case .primary, .destructive: return nil
            }
        }
    }
}

// MARK: - Dialog Animation
public struct DialogAnimation {
    public let entrance: AnimationType
    public let exit: AnimationType
    public let duration: Double
    public let springResponse: Double
    public let springDamping: Double
    
    public init(
        entrance: AnimationType = .scale,
        exit: AnimationType = .scale,
        duration: Double = 0.3,
        springResponse: Double = 0.4,
        springDamping: Double = 0.8
    ) {
        self.entrance = entrance
        self.exit = exit
        self.duration = duration
        self.springResponse = springResponse
        self.springDamping = springDamping
    }
    
    public static let `default` = DialogAnimation()
    public static let spring = DialogAnimation(springResponse: 0.5, springDamping: 0.7)
    public static let smooth = DialogAnimation(duration: 0.4, springResponse: 0.6, springDamping: 0.9)
    public static let bouncy = DialogAnimation(springResponse: 0.3, springDamping: 0.6)
    public static let slideUp = DialogAnimation(entrance: .slideUp, exit: .slideDown)
    public static let fade = DialogAnimation(entrance: .fade, exit: .fade)
    
    public enum AnimationType {
        case scale
        case slideUp
        case slideDown
        case fade
        case scaleAndSlide
    }
}

// MARK: - Custom Dialog View

/// Le dialogue de l'application, dessiné en SwiftUI.
///
/// **Suit l'apparence de l'écran qui l'affiche**, y compris un mode sombre
/// choisi dans l'application : toutes ses teintes viennent de `AppColors`. Une
/// alerte système, elle, suit le réglage de l'appareil — c'est pour cela que ce
/// composant existe.
public struct CustomDialog: View {
    let configuration: DialogConfiguration
    @Binding var isPresented: Bool
    @State private var animateContent = false
    @State private var backgroundOpacity = 0.0

    public init(configuration: DialogConfiguration, isPresented: Binding<Bool>) {
        self.configuration = configuration
        self._isPresented = isPresented
    }

    public var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity * 0.45)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    if let icon = configuration.style.iconName {
                        Image(systemName: icon)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(configuration.style.iconTint)
                            .padding(.bottom, 2)
                    }

                    Text(configuration.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(configuration.style.titleColor)
                        .fixedSize(horizontal: false, vertical: true)

                    if let message = configuration.message {
                        Text(message)
                            .font(.system(size: 15))
                            .foregroundStyle(AppColors.subtitleGray)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, 20)

                VStack(spacing: 10) {
                    ForEach(configuration.buttons) { button in
                        Button {
                            button.action()
                            dismiss()
                        } label: {
                            Text(button.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(button.role.foregroundColor)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(button.role.backgroundColor, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(DialogButtonStyle())
                    }
                }
            }
            .padding(22)
            .frame(maxWidth: 340)
            .background(AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .strokeBorder(AppColors.chipBorder.opacity(0.6), lineWidth: 0.5)
            )
            .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
            .padding(.horizontal, 28)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .modifier(DialogAnimationModifier(
                isPresented: animateContent,
                animation: configuration.animation
            ))
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.2)) { backgroundOpacity = 1 }
            withAnimation(.spring(response: configuration.animation.springResponse,
                                  dampingFraction: configuration.animation.springDamping)) {
                animateContent = true
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeIn(duration: 0.15)) {
            backgroundOpacity = 0
            animateContent = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isPresented = false
        }
    }
}

/// Enfoncement discret : le bouton s'estompe, sans changer de forme.
private struct DialogButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Dialog Animation Modifier
private struct DialogAnimationModifier: ViewModifier {
    let isPresented: Bool
    let animation: DialogAnimation
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(scaleEffect)
            .offset(y: offsetY)
            .opacity(opacity)
    }
    
    private var scaleEffect: CGFloat {
        guard isPresented else { return 0.8 }
        
        switch animation.entrance {
        case .scale, .scaleAndSlide:
            return 1.0
        default:
            return 1.0
        }
    }
    
    private var offsetY: CGFloat {
        guard isPresented else {
            switch animation.exit {
            case .slideDown:
                return 300
            case .slideUp:
                return -300
            case .scaleAndSlide:
                return 100
            default:
                return 0
            }
        }
        
        switch animation.entrance {
        case .slideUp:
            return 0
        case .slideDown:
            return 0
        case .scaleAndSlide:
            return 0
        default:
            return 0
        }
    }
    
    private var opacity: Double {
        isPresented ? 1.0 : 0.0
    }
}

// MARK: - View Extension
public extension View {
    func customDialog(
        isPresented: Binding<Bool>,
        configuration: DialogConfiguration
    ) -> some View {
        ZStack {
            self
            
            if isPresented.wrappedValue {
                CustomDialog(configuration: configuration, isPresented: isPresented)
                    .transition(.opacity)
                    .zIndex(999)
            }
        }
    }
    
    // Convenience method for confirmation dialogs
    func customConfirmationDialog(
        title: String,
        message: String? = nil,
        isPresented: Binding<Bool>,
        destructiveTitle: String = "Confirm",
        cancelTitle: String = "Cancel",
        animation: DialogAnimation = .default,
        onConfirm: @escaping () -> Void
    ) -> some View {
        customDialog(
            isPresented: isPresented,
            configuration: DialogConfiguration(
                title: title,
                message: message,
                style: .destructive,
                buttons: [
                    DialogButton(title: destructiveTitle, role: .destructive, action: onConfirm),
                    DialogButton(title: cancelTitle, role: .cancel, action: {})
                ],
                animation: animation
            )
        )
    }
    
    // Convenience method for alerts
    func customAlert(
        title: String,
        message: String? = nil,
        isPresented: Binding<Bool>,
        okTitle: String = "OK",
        animation: DialogAnimation = .default,
        onDismiss: (() -> Void)? = nil
    ) -> some View {
        customDialog(
            isPresented: isPresented,
            configuration: DialogConfiguration(
                title: title,
                message: message,
                style: .standard,
                buttons: [
                    DialogButton(title: okTitle, role: .primary, action: {
                        onDismiss?()
                    })
                ],
                animation: animation
            )
        )
    }
}
