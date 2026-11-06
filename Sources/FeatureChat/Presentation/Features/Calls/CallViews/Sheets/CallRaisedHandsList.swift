import SwiftUI

/// One person in the speaking queue.
struct CallRaisedHandsEntry: Identifiable {
    let peerId: String
    let name: String
    var id: String { peerId }
}

/// The speaking queue, in the order the server gave, with the host's action.
///
/// A list rather than an action on the tile: the order is the point of the
/// queue, and with up to 32 participants whoever raised first may not be on
/// screen at all.
@available(iOS 16.0, *)
struct CallRaisedHandsList: View {

    let entries: [CallRaisedHandsEntry]
    let acknowledgeTitle: String
    let onAcknowledge: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: 12) {
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CallTheme.Palette.secondaryText)
                        .frame(width: 20)

                    Text(entry.name)
                        .font(.system(size: 15))
                        .foregroundStyle(CallTheme.Palette.primaryText)
                        .lineLimit(1)

                    Spacer()

                    Button(acknowledgeTitle) {
                        onAcknowledge(entry.peerId)
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)

                if index < entries.count - 1 {
                    Divider().padding(.leading, 50)
                }
            }
        }
    }
}
