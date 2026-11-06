//
//  ForwardSelectionActionBar.swift
//  FeatureChat
//
//  Created by Kiro on 2/12/26.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

struct ForwardSelectionActionBar: View {
    let selectedCount: Int
    let translationService: (any TranslationServiceProtocol)?
    let onCancel: () -> Void
    let onForward: () -> Void
    
    var body: some View {
        HStack(spacing: 16) {
            // Cancel button
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Selected count
            Text(t(ChatTranslationKeys.FORWARD_SELECTED_COUNT, args: ["\(selectedCount)"]))
                .font(.headline)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Forward button
            Button(action: onForward) {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                    Text(t(ChatTranslationKeys.MENU_FORWARD))
                        .font(.headline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(AppColors.primary)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .disabled(selectedCount == 0)
            .opacity(selectedCount == 0 ? 0.6 : 1.0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color.gray.opacity(0.2))
                .frame(height: 0.5),
            alignment: .top
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
}

#Preview {
    VStack {
        Spacer()
        ForwardSelectionActionBar(
            selectedCount: 3,
            translationService: nil,
            onCancel: {},
            onForward: {}
        )
    }
}