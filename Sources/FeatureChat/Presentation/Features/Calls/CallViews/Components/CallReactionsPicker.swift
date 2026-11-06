import SwiftUI

/// The eight contract emoji, as a strip inside the call's More sheet.
///
/// Reactions belong to a group call: in a one-to-one there is one other face on
/// screen and a voice already open, so the sheet only offers this when more than
/// two people are in the room.
@available(iOS 16.0, *)
struct CallReactionsPicker: View {

    let onReaction: (String) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(CallReactionFeed.palette, id: \.self) { emoji in
                Button {
                    onReaction(emoji)
                } label: {
                    Text(emoji)
                        .font(.system(size: 26))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(emoji)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 4)
    }
}
