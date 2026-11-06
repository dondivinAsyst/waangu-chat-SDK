//
//  DiscussionListToastOverlay.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI

struct DiscussionListToastOverlay: ViewModifier {
    let message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message, !message.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.primary)
                    Text(message)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.25), value: message)
            }
        }
    }
}

extension View {
    func discussionListToast(message: String?) -> some View {
        modifier(DiscussionListToastOverlay(message: message))
    }
}
