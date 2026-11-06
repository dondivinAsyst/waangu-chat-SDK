import SwiftUI
import UIKit
import WaanguCoreKit

struct SecureScreen<Content: View>: View {

    @Environment(\.scenePhase) private var phase
    @State private var blurred = false
    let content: () -> Content
    let translationService: (any TranslationServiceProtocol)? = nil

    var body: some View {
        ZStack {
            content()
                .blur(radius: blurred ? 20 : 0)

            if UIScreen.main.isCaptured {
                Color.black
                Text(translationService?.resolve(key: ChatTranslationKeys.SECURE_SCREEN_RECORDING_BLOCKED, module: ChatTranslationKeys.MODULE).value ?? "Screen recording blocked")
                    .foregroundColor(.white)
            }
        }
        .onChange(of: phase) { newPhase in
            blurred = newPhase != .active
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: UIApplication.userDidTakeScreenshotNotification
            )
        ) { _ in
            blurred = true
        }
    }
}
