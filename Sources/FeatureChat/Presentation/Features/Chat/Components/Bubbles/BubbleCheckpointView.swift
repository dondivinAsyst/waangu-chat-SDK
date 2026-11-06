//
//  BubbleCheckpointView.swift
//  FeatureChat
//
//  Checkpoint-style bubble for system actions (member joined, left, admin changes, etc.)
//  Uses TranslationKit for all displayed text.
//

import SwiftUI
import WaanguCoreKit

struct BubbleCheckpointView: View {

    let action: ChatActionItem
    var translator: (any TranslationServiceProtocol)?
    var isTappable: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            Spacer()

            Group {
                if isTappable {
                    Button(action: { onTap?() }) {
                        checkpointContent
                    }
                    .buttonStyle(.plain)
                } else {
                    checkpointContent
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isTappable ? Color.accentColor.opacity(0.12) : Color.gray.opacity(0.15))
            )
            .overlay {
                if isTappable {
                    Capsule()
                        .stroke(Color.accentColor.opacity(0.25), lineWidth: 0.5)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var checkpointContent: some View {
        HStack(spacing: 6) {
            Image(systemName: action.iconName)
                .font(.caption2)
                .foregroundColor(isTappable ? .accentColor : .secondary)

            // Use translator if available, fall back to key string if not
            Text(resolvedText)
                .font(.caption)
                .foregroundColor(isTappable ? .primary : .secondary)

            if isTappable {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var resolvedText: String {
        if let t = translator {
            return action.displayText(using: t)
        }
        // Graceful fallback: return the action type raw value so nothing is blank
        return action.actionType.rawValue
    }
}
