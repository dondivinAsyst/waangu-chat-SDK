//
//  ImageCropperView.swift
//  FeatureChat
//

import SwiftUI
import UIKit

/// Standalone crop screen: a `UIImage` goes in, a cropped `UIImage` comes out.
///
/// Shares its canvas, gestures, view model and renderer with the chat/stories
/// editor — the only thing it doesn't share is `PhotoCropEditor`'s shell, which
/// is bound to `MediaInfo` and round-trips a `cropSession` so a sent image stays
/// re-editable. Avatars need none of that, so this shell stays plain.
///
/// The output is a rectangle even when `shape` is `.circle`: avatars are stored
/// square and masked where they're drawn, so baking a circle into the bitmap
/// would only bake in a background colour too.
struct ImageCropperView: View {

    let image: UIImage
    var shape: CropWindowShape = .circle
    let onCancel: () -> Void
    let onCrop: (UIImage) -> Void

    @StateObject private var viewModel = CropViewModel()
    @State private var panStart: CGSize = .zero
    @State private var pinchStart: CGFloat = 1.0

    var body: some View {
        // `safeAreaInset` rather than a plain stack row: it pins the bar inside
        // the safe area whatever the presenting container does with its own,
        // which a VStack child does not — that's how the close and confirm
        // buttons ended up under the status bar.
        VStack(spacing: 0) {
            Spacer()

            GeometryReader { geo in
                CropCanvasView(
                    cropRect: $viewModel.cropRect,
                    containerSize: geo.size,
                    viewModel: viewModel,
                    panStart: $panStart,
                    pinchStart: $pinchStart,
                    shape: shape
                )
                .onAppear {
                    viewModel.configure(
                        source: image,
                        session: nil,
                        containerSize: geo.size,
                        lockedAspectRatio: shape.lockedAspectRatio
                    )
                    panStart = viewModel.transform.panOffset
                    pinchStart = viewModel.transform.userZoomScale
                }
            }
            .padding(.horizontal, 10)

            bottomControls
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            topBar
        }
        // Applied after the inset so the black sits behind the bar too, rather
        // than leaving it on the cover's default background.
        .background(Color.black.ignoresSafeArea())
    }

    // MARK: - Chrome

    private var topBar: some View {
        HStack(spacing: 20) {
            circularButton("xmark") {
                onCancel()
            }

            Spacer()

            if viewModel.hasChanges {
                circularButton("arrow.counterclockwise") {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.resetAll()
                    }
                    panStart = .zero
                    pinchStart = 1.0
                }
            }

            circularButton("checkmark") {
                guard let cropped = viewModel.applyCrop() else { return }
                onCrop(cropped)
            }
            .disabled(!viewModel.canApplyCrop)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .zIndex(999)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    viewModel.rotateQuarterTurn()
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }
                .disabled(viewModel.isProcessing)

                Spacer()
            }
            .padding(.horizontal, 30)

            DraggableCompass(
                viewModel: viewModel,
                onBegin: { viewModel.beginStraightening() },
                onChange: { degrees in viewModel.updateFineAngle(degrees: degrees) },
                onDismiss: {
                    viewModel.finishStraightening()
                    pinchStart = viewModel.transform.userZoomScale
                },
                limit: 90
            )
        }
    }

    private func circularButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .resizable().scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(.white)
        }
        .padding()
        .background(.black.opacity(0.5))
        .cornerRadius(50)
    }
}
