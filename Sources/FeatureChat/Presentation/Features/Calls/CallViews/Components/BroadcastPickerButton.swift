//
//  BroadcastPickerButton.swift
//  FeatureChat
//
//  iOS offers no API to start a broadcast programmatically — the user must tap
//  the system picker, and iOS adds its own confirmation with a 3-second
//  countdown. So the Share control *hosts* the picker rather than calling a
//  start function. Stopping is programmatic, via BroadcastControlChannel.
//

import SwiftUI
import ReplayKit

struct BroadcastPickerButton: UIViewRepresentable {

    /// Must equal the extension target's `PRODUCT_BUNDLE_IDENTIFIER`. This
    /// project's convention is `test.com.Waangu.en.*` — a mismatch silently
    /// degrades the picker to "every broadcast app on the device" instead of
    /// preselecting ours.
    static let extensionBundleIdentifier = "test.com.Waangu.en.BroadcastUpload"

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 0, y: 0, width: 60, height: 60)
        )
        picker.preferredExtension = Self.extensionBundleIdentifier
        picker.showsMicrophoneButton = false
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}
