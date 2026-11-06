//
//  CallAudioRoutePicker.swift
//  FeatureChat
//
//  Bridges AVKit's system route picker into SwiftUI.
//
//  The in-call speaker button is a binary earpiece/speaker toggle, which cannot
//  reach a Bluetooth headset or an AirPlay receiver even though the audio
//  session declares `.allowBluetooth` and `.allowAirPlay`. Only the system
//  picker can enumerate those, and it must be tapped directly — so the styled
//  row draws the visuals and this view sits invisibly on top of it.
//

import SwiftUI
import AVKit

struct CallAudioRoutePicker: UIViewRepresentable {

    func makeUIView(context: Context) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.prioritizesVideoDevices = false
        // Invisible: the row underneath supplies the label and icon. Alpha would
        // also disable hit testing at 0, so the tint carries the transparency.
        picker.tintColor = .clear
        picker.activeTintColor = .clear
        picker.backgroundColor = .clear
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}

/// A call-styled row whose whole surface opens the system output picker.
struct CallAudioRouteRow: View {

    let title: String
    let subtitle: String

    var body: some View {
        CallSheetRow(icon: "airplayaudio", title: title, subtitle: subtitle) {}
            .overlay(CallAudioRoutePicker().accessibilityLabel(Text(title)))
    }
}
