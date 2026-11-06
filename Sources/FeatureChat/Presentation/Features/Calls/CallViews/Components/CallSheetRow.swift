//
//  CallSheetRow.swift
//  FeatureChat
//
//  One action row inside a call sheet.
//
//  Call sheets sit over a dark, always-dark call canvas, so they cannot reuse
//  the chat sheets' system-background rows. This keeps them on CallTheme instead.
//

import SwiftUI

struct CallSheetRow: View {

    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(CallTheme.Palette.controlIdle)
                        .frame(width: 40, height: 40)

                    Image(systemName: icon)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(tint)

                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(CallTheme.Palette.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var tint: Color {
        isDestructive ? CallTheme.Palette.endCall : CallTheme.Palette.primaryText
    }
}
