import Foundation

/// Whether an inbound message may speak for its conversation in the chat list.
///
/// A group event is written into the thread by the backend, not sent by anyone. It
/// must not become the conversation's last message, must not reorder the list, and
/// must not raise an unread badge — all three would tell the user someone wrote to
/// them when nobody did.
/// Asked of the content, not of `typeMessage`: on the pull-events and inbox-summary
/// paths the type still reads `"SYSTEM"`, and a rule that trusted it would let a
/// group event badge the conversation on exactly the paths nobody normalizes.
enum ConversationPreviewPolicy {

    static func updatesPreview(_ dto: InboundMessageDTO) -> Bool {
        dto.resolvedGroupEvent == nil && ConversationSystemRecord.kind(of: dto) == nil
    }
}
