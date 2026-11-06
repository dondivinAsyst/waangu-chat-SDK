//
//  ChannelCreateFlowSheet.swift
//  FeatureChat
//

import SwiftUI

/// Creating a channel, as one sheet: the rules, then the form.
@available(iOS 16.0, *)
struct ChannelCreateFlowSheet: View {

    @ObservedObject var viewModel: ChannelsViewModel
    let onCreated: (Channel) -> Void
    let onDismiss: () -> Void

    @State private var showsForm = false

    var body: some View {
        Group {
            if showsForm {
                CreateChannelView(
                    viewModel: viewModel,
                    onCreated: onCreated,
                    onCancel: onDismiss
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ChannelCreateIntroSheet(
                    translationService: viewModel.translationService,
                    onContinue: { showsForm = true },
                    onDismiss: onDismiss
                )
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: showsForm)
    }
}
