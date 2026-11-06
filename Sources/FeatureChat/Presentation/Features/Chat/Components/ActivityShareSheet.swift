//
//  ActivityShareSheet.swift
//  FeatureChat
//

import SwiftUI
import UIKit

/// Shared wrapper around `UIActivityViewController`.
///
/// Contact profile, group info and the contact bubble all need the system share
/// sheet; this is the single representable they use instead of each declaring a
/// private copy.
struct ActivityShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
