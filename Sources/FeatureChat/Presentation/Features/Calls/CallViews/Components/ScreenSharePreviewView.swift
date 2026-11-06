//
//  ScreenSharePreviewView.swift
//  FeatureChat
//

import SwiftUI

struct ScreenSharePreviewView: View {

    @ObservedObject var viewModel: ScreenSharePreviewViewModel

    var body: some View {
        VStack(spacing: 12) {
            if let frame = viewModel.latestFrame {
                Image(decorative: frame, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(.black)
                    .overlay { ProgressView().tint(.white) }
            }

            Text(viewModel.stats)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding()
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
    }
}
