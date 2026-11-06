import SwiftUI
import UIKit
import WaanguCoreKit

struct TextInputToolbarAreaViewWrapper: UIViewRepresentable {
    @Binding var text: String

    var voiceRecordingViewModel: VoiceRecordingViewModel?
    var translationService: (any TranslationServiceProtocol)?
    var localeToken: Int = 0
    var userInterfaceStyle: UIUserInterfaceStyle = .unspecified
    var onPresentSheet: (() -> Void)?
    var onOpenCamera: (() -> Void)?
    /// A long press on the camera button. Nil leaves the button tap-only, as in
    /// channels.
    var onOpenVideoNote: (() -> Void)? = nil
    var onOpenPayments: (() -> Void)? = nil
    var onSendMessage: ((String) -> Void)?
    var onRecordAudio: (() -> Void)?
    var onHeightChange: (() -> Void)?
    var onSendAudio: (() -> Void)?
    var onStartRecording: (() -> Void)?
    var onStopRecording: (() -> Void)?
    var onReadOnce: ((Bool) -> Void)?
    var onPauseOrResumeRecording: ((Bool) -> Void)?
    var onTextChanged: ((String) -> Void)?

    @Binding var contentHeight: CGFloat

    func makeUIView(context: Context) -> TextInputToolbarAreaView {
        let toolbarView = TextInputToolbarAreaView()

        context.coordinator.toolbarView = toolbarView

        if let viewModel = voiceRecordingViewModel {
            toolbarView.configure(with: viewModel)
        }

        toolbarView.updatePlaceholder(resolvedPlaceholder())
        applyAccessibilityLabels(to: toolbarView)

        toolbarView.onPresentSheet = onPresentSheet
        toolbarView.onOpenCamera = onOpenCamera
        toolbarView.configurePayments(action: onOpenPayments, label: FinanceStrings.hubTitle)
        toolbarView.onSendMessage = onSendMessage
        toolbarView.onRecordAudio = onRecordAudio

        toolbarView.onHeightChange = {
            onHeightChange?()
        }

        toolbarView.onRecorderLockChange = { [weak toolbarView] isLocked in
            guard let toolbarView else { return }
            if isLocked {
                // 110 pt of recorder plus the 17 pt it sits above the bar's bottom.
                contentHeight = 127
            } else {
                updateHeight(for: toolbarView)
            }
        }

        toolbarView.onSendAudio = onSendAudio
        toolbarView.onStartRecording = onStartRecording
        toolbarView.onStopRecording = onStopRecording
        toolbarView.onReadOnce = onReadOnce
        toolbarView.onPauseOrResumeRecording = onPauseOrResumeRecording

        toolbarView.onTextChanged = { newText in
            text = newText
            onTextChanged?(newText)

            let cursorPosition = toolbarView.textField.selectedRange.location
            context.coordinator.lastCursorPosition = cursorPosition

            DispatchQueue.main.async {
                self.updateHeight(for: toolbarView)
            }
        }

        toolbarView.textField.text = text
        toolbarView.overrideUserInterfaceStyle = userInterfaceStyle

        return toolbarView
    }

    func updateUIView(_ uiView: TextInputToolbarAreaView, context: Context) {
        uiView.configurePayments(action: onOpenPayments, label: FinanceStrings.hubTitle)
        let isUserEditing = uiView.textField.isFirstResponder

        if uiView.textField.text != text && !isUserEditing {
            uiView.textField.text = text
        } else if uiView.textField.text != text && isUserEditing {
            let lengthDiff = abs(uiView.textField.text.count - text.count)
            if lengthDiff > 1 {
                uiView.textField.text = text

                let newPosition = min(context.coordinator.lastCursorPosition, text.count)
                uiView.textField.selectedRange = NSRange(location: newPosition, length: 0)
            }
        }

        if context.coordinator.lastLocaleToken != localeToken {
            context.coordinator.lastLocaleToken = localeToken
            uiView.updatePlaceholder(resolvedPlaceholder())
            applyAccessibilityLabels(to: uiView)
        }

        if context.coordinator.lastUserInterfaceStyle != userInterfaceStyle {
            context.coordinator.lastUserInterfaceStyle = userInterfaceStyle
            uiView.overrideUserInterfaceStyle = userInterfaceStyle
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    private func applyAccessibilityLabels(to toolbarView: TextInputToolbarAreaView) {
        func name(_ key: String, fallback: String) -> String {
            translationService?
                .resolve(key: key, module: ChatTranslationKeys.MODULE)
                .value ?? fallback
        }
        toolbarView.configureAccessibility(
            camera: name(ChatTranslationKeys.CHAT_A11Y_OPEN_CAMERA, fallback: "Open camera"),
            attach: name(ChatTranslationKeys.CHAT_A11Y_ATTACH, fallback: "Attach"),
            send: name(ChatTranslationKeys.CHAT_A11Y_SEND_MESSAGE, fallback: "Send message"),
            voice: name(ChatTranslationKeys.CALLS_RECORD_VOICE_MESSAGE, fallback: "Record voice message")
        )
        toolbarView.configureViewOnce(
            label: name(ChatTranslationKeys.CHAT_A11Y_VIEW_ONCE, fallback: "View once")
        )
        toolbarView.configureVideoNote(
            action: onOpenVideoNote,
            label: name(ChatTranslationKeys.CHAT_A11Y_RECORD_VIDEO_NOTE, fallback: "Record video note")
        )
    }

    private func resolvedPlaceholder() -> String {
        translationService?
            .resolve(
                key: ChatTranslationKeys.CHAT_MESSAGE_PLACEHOLDER,
                module: ChatTranslationKeys.MODULE
            )
            .value ?? "Type a message..."
    }

    private func updateHeight(for toolbarView: TextInputToolbarAreaView) {
        let size = toolbarView.textField.sizeThatFits(
            CGSize(width: toolbarView.textField.frame.width, height: .greatestFiniteMagnitude)
        )

        let maxTextHeight: CGFloat = 100
        let shouldScroll = size.height > maxTextHeight

        toolbarView.textField.isScrollEnabled = shouldScroll

        let baseHeight: CGFloat = 60
        let textFieldHeight = shouldScroll ? maxTextHeight : min(maxTextHeight, size.height + 20)
        let newHeight = max(baseHeight, textFieldHeight)

        contentHeight = min(150, newHeight)
    }

    class Coordinator: NSObject {
        var parent: TextInputToolbarAreaViewWrapper
        weak var toolbarView: TextInputToolbarAreaView?
        var lastLocaleToken: Int = 0
        var lastUserInterfaceStyle: UIUserInterfaceStyle = .unspecified
        var lastCursorPosition: Int = 0

        init(_ parent: TextInputToolbarAreaViewWrapper) {
            self.parent = parent
            self.lastLocaleToken = parent.localeToken
            self.lastUserInterfaceStyle = parent.userInterfaceStyle
        }

        var previousSelectedRange: NSRange?
    }
}

// MARK: - Helper extension to get/set cursor position
extension UITextView {
    var selectedRange: NSRange {
        get {
            guard let selectedTextRange = selectedTextRange else { return NSRange(location: 0, length: 0) }
            let location = offset(from: beginningOfDocument, to: selectedTextRange.start)
            let length = offset(from: selectedTextRange.start, to: selectedTextRange.end)
            return NSRange(location: location, length: length)
        }
        set {
            guard let startPosition = position(from: beginningOfDocument, offset: newValue.location),
                  let endPosition = position(from: beginningOfDocument, offset: newValue.location + newValue.length),
                  let textRange = textRange(from: startPosition, to: endPosition) else { return }
            selectedTextRange = textRange
        }
    }
}
