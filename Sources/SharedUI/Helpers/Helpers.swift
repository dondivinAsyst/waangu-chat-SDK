//
//  KeyboardResponder.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


////
////  Helpers.swift
////  Pods
////
////  Created by Asyst on 6/19/25.
////
//import SwiftUI
//
//func presentZoomableOverlay(
//    from parent: UIViewController,
//    image: GalleryImage,
//    isSelected: Bool,
//    onSelect: @escaping () -> Void = {},
//    sourceRect: CGRect
//) {
//    let vc = UIHostingController(
//        rootView: ZoomableImageOverlay(
//            image: image,
//            isSelected: isSelected,
//            onDismiss: {
//                parent.dismiss(animated: false)
//            },
//            onSelect: {
//                onSelect()
//                parent.dismiss(animated: false)
//            },
//            sourceRect: sourceRect
//        )
//    )
//    
//    vc.modalPresentationStyle = .overFullScreen
//    vc.view.backgroundColor = .clear
//    parent.present(vc, animated: false)
//
//}
//
//
// func topMostViewController(base: UIViewController? = UIApplication.shared.connectedScenes
//  .compactMap { ($0 as? UIWindowScene)?.keyWindow }
//  .first?.rootViewController) -> UIViewController? {
//  if let nav = base as? UINavigationController {
//    return topMostViewController(base: nav.visibleViewController)
//  }
//  if let tab = base as? UITabBarController {
//    return topMostViewController(base: tab.selectedViewController)
//  }
//  if let presented = base?.presentedViewController {
//    return topMostViewController(base: presented)
//  }
//  return base
//}
//
//
//
//

import SwiftUI
import Combine
//import Libopusenc
//import OpusHybrid
//import OpusHybrid
//import OpusLib
//import OpusHybrid

//import Opusenc
public final class KeyboardResponder: ObservableObject {
    @Published public var currentHeight: CGFloat = 0
    private var cancellableSet: Set<AnyCancellable> = []

    public  init() {
        let keyboardWillShow = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillShowNotification)
            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
            .map { $0.height }

        let keyboardWillHide = NotificationCenter.default
            .publisher(for: UIResponder.keyboardWillHideNotification)
            .map { _ in CGFloat(0) }

        Publishers.Merge(keyboardWillShow, keyboardWillHide)
            .receive(on: RunLoop.main)
            .assign(to: \.currentHeight, on: self)
            .store(in: &cancellableSet)
    }
}

public var safeAreaInsets: UIEdgeInsets {
    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
          let window = windowScene.windows.first else {
        return .zero
    }
    return window.safeAreaInsets
}

public extension Bundle {
    public  static var nativeUi: Bundle? { .main }
}

public extension Image {
    public static func custom(_ name: String) -> Image {
        Image(name, bundle: .main)
    }
}

public extension Color {
    static func custom(_ name: String) -> Color {
        Color(name, bundle: .main)
    }
}


//MARK READ HEIGHT OF VIEW

public struct HeightPreferenceKey: PreferenceKey {
    public  static var defaultValue: CGFloat = 0

    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}


public struct ReadHeight: ViewModifier {
    public   func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { geometry in
                    Color.clear
                        .preference(key: HeightPreferenceKey.self, value: geometry.size.height)
                }
            )
    }
}

public extension View {
    func readHeight() -> some View {
        self.modifier(ReadHeight())
    }
}


//CORNERS RADIUS EXTENSIONS
public struct RoundedCorner: Shape {
     var radius: CGFloat = .infinity
      var corners: UIRectCorner = .allCorners

    public func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

public extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}


public struct PhoneNumberFormatter {
    public  static func format(_ phoneNumber: String) -> String {
        let cleaned = phoneNumber.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        switch cleaned.count {
        case 10: // Format français
            let pattern = "(\\d{2})(\\d{2})(\\d{2})(\\d{2})(\\d{2})"
            let replacement = "$1 $2 $3 $4 $5"
            return cleaned.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            
        case 12:
            let pattern = "(\\d{2})(\\d{1})(\\d{2})(\\d{2})(\\d{2})(\\d{2})"
            let replacement = "+$1 $2 $3 $4 $5 $6"
            return cleaned.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
            
        default:
            return phoneNumber
        }
    }
}

