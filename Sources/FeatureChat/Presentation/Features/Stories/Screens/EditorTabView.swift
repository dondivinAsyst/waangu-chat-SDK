import SwiftUI
import UIKit
import WaanguCoreKit
import WaanguSharedUI

struct EditorTabView: View {
    @StateObject private var switcher: WSegmentedSwitcherModel<EditorTab>
    /// Last camera mode used, so returning from .text doesn't reset to photo.
    @State private var lastCameraMode: CameraMode = .photo

    let statusStore: StoriesViewModel
    let translationService: (any TranslationServiceProtocol)?

    init(
        initialTab: EditorTab = .text,
        statusStore: StoriesViewModel,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _switcher = StateObject(wrappedValue: WSegmentedSwitcherModel(selection: initialTab))
        self.statusStore = statusStore
        self.translationService = translationService
    }

    func onMainTabAppearance() {
        withAnimation(.easeInOut) {
            statusStore.isFirstPageStory = true
        }
    }

    private var selectedTab: EditorTab { switcher.selection }

    /// SharedUI has no access to CoreKit, so titles are resolved here.
    private var segments: [WSegment<EditorTab>] {
        [
            WSegment(id: .video, title: t(ChatTranslationKeys.STORIES_VIDEO_LABEL)),
            WSegment(id: .photo, title: t(ChatTranslationKeys.STORIES_PHOTO_LABEL)),
            WSegment(id: .text,  title: t(ChatTranslationKeys.STORIES_TEXT))
        ]
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer().toolbar(statusStore.isFirstPageStory ? .visible : .hidden, for: .tabBar)

            ZStack {
                // Mounted ONCE for the composer's lifetime. Switching photo↔video
                // only mutates `mode`; the session is never rebuilt, which is what
                // removes the black flash between modes.
                CameraView(
                    mode: selectedTab.cameraMode ?? lastCameraMode,
                    onAppearTab: onMainTabAppearance
                )
                .navigationBarBackButtonHidden()
                .opacity(selectedTab == .text ? 0 : 1)
                .allowsHitTesting(selectedTab != .text)

                StatusEditorView(
                    statusStore: statusStore,
                    translationService: translationService,
                    onAppearTab: onMainTabAppearance,
                    isActive: selectedTab == .text
                )
                .opacity(selectedTab == .text ? 1 : 0)
                .allowsHitTesting(selectedTab == .text)
            }
            .animation(.easeInOut(duration: 0.25), value: selectedTab)
            .wSegmentedSwipe(switcher, items: EditorTab.allCases)

            WSegmentedSwitcher(
                segments: segments,
                model: switcher,
                style: .composer
            )
        }
        .edgesIgnoringSafeArea(.top)
        .onChange(of: switcher.selection) { _, tab in
            guard let mode = tab.cameraMode else { return }
            lastCameraMode = mode
            // The text editor keeps first responder otherwise, leaving the
            // keyboard over the camera preview.
            dismissKeyboard()
        }
        .onAppear {
            withAnimation(.easeInOut) {
                statusStore.isFirstPageStory = false
            }
        }
    }

    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
