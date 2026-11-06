//
//  CommunityCreateFlowSheet.swift
//  FeatureChat
//

import SwiftUI

/// Creating a community, as one sheet: what a community is, then the form.
///
/// Two pages inside a single presentation rather than two sheets — dismissing
/// one sheet to present another drops a frame and reads as a stutter, and the
/// explainer and the form are one task.
@available(iOS 16.0, *)
struct CommunityCreateFlowSheet: View {

    @ObservedObject var viewModel: CommunitiesViewModel
    let onCreated: (Community) -> Void
    let onDismiss: () -> Void

    @State private var showsForm = false

    var body: some View {
        Group {
            if showsForm {
                CreateCommunityView(
                    viewModel: viewModel,
                    onCreated: onCreated,
                    onCancel: onDismiss
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                CommunityIntroSheet(
                    translationService: viewModel.translationService,
                    onStart: { showsForm = true },
                    onDismiss: onDismiss
                )
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: showsForm)
    }
}
