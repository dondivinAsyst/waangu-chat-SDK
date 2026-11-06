import SwiftUI

struct ResizableTextEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat

    // MARK: - Customization Properties
    var font: UIFont = .systemFont(ofSize: 18)
    var textColor: UIColor = .black
    var placeholder: String = "Type here..."
    var placeholderColor: UIColor = .gray
    var isEditable: Bool = true
    var isScrollEnabled: Bool = true
    var backgroundColor: UIColor = .clear
    var cornerRadius: CGFloat = 0
    var padding: CGFloat = 14
    var autoFocus: Bool = false   // ✅ new toggle

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.isEditable = isEditable
        textView.isScrollEnabled = isScrollEnabled
        textView.font = font
        textView.backgroundColor = backgroundColor
        textView.layer.cornerRadius = cornerRadius
        textView.textContainerInset = UIEdgeInsets(
            top: padding, left: padding, bottom: padding, right: padding
        )

        // Placeholder setup
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = placeholderColor
        } else {
            textView.text = text
            textView.textColor = textColor
        }

        // ✅ Autofocus after small delay (ensures it’s in hierarchy)
        if autoFocus {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                textView.becomeFirstResponder()
            }
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
//        if text.isEmpty && !uiView.isFirstResponder {
//            uiView.text = placeholder
//            uiView.textColor = placeholderColor
//        } else if uiView.textColor == placeholderColor && uiView.isFirstResponder {
//            uiView.text = ""
//            uiView.textColor = textColor
//        } else {
//            uiView.text = text
//            uiView.textColor = textColor
//        }
        // --- Case 1: SHOW placeholder ---
        if text.isEmpty && !uiView.isFirstResponder {
            uiView.text = placeholder
            uiView.textColor = placeholderColor

        // --- Case 2: SwiftUI updated text binding ---
        } else if uiView.textColor == placeholderColor || uiView.text != text {
            uiView.text = text
            uiView.textColor = textColor
        }
//        if uiView.textColor == placeholderColor && text.isEmpty {
//             uiView.text = placeholder
//             uiView.textColor = placeholderColor
//         } else if uiView.textColor != placeholderColor && uiView.text != text {
//             uiView.text = text
//             uiView.textColor = textColor
//         }

        // Auto-resize height
        DispatchQueue.main.async {
            self.height = uiView.contentSize.height
        }
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: ResizableTextEditor

        init(parent: ResizableTextEditor) {
            self.parent = parent
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            if textView.textColor == parent.placeholderColor {
                textView.text = ""
                textView.textColor = parent.textColor
            }
        }

        func textViewDidChange(_ textView: UITextView) {
            DispatchQueue.main.async {
                self.parent.height = textView.contentSize.height
                self.parent.text = textView.text
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = parent.placeholderColor
            }
        }
    }
}
