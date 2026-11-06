//
//  AvatarPickerButton.swift
//  FeatureChat
//

import PhotosUI
import SwiftUI
import UIKit

/// Picking and cropping an avatar, as one control.
///
/// Every avatar in the app — the user's own, a group's at creation, a group's
/// afterwards — is picked the same way and framed the same way, so the sequence
/// lives here once rather than in each screen. Callers supply the tappable label
/// and receive a cropped square image; nothing is reported until the user
/// confirms the crop.
struct AvatarPickerButton<Label: View>: View {

    let onPicked: (UIImage) -> Void
    var onLoadFailed: (() -> Void)? = nil
    @ViewBuilder let label: () -> Label

    @State private var selectedItem: PhotosPickerItem?
    @State private var photoAwaitingCrop: UIImage?

    var body: some View {
        PhotosPicker(selection: $selectedItem, matching: .not(.videos)) {
            label()
        }
        .onChange(of: selectedItem) { _, newValue in
            guard let newValue else { return }
            Task { await load(newValue) }
        }
        .chatAppearanceFullScreenCover(
            isPresented: .init(
                get: { photoAwaitingCrop != nil },
                set: { if !$0 { cancel() } }
            )
        ) {
            if let picked = photoAwaitingCrop {
                ImageCropperView(
                    image: picked,
                    onCancel: cancel,
                    onCrop: { cropped in
                        photoAwaitingCrop = nil
                        selectedItem = nil
                        onPicked(cropped)
                    }
                )
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            selectedItem = nil
            onLoadFailed?()
            return
        }
        photoAwaitingCrop = image
    }

    /// Clearing the selection matters: without it, re-picking the same photo is
    /// not a change and the cropper never reopens.
    private func cancel() {
        photoAwaitingCrop = nil
        selectedItem = nil
    }
}
