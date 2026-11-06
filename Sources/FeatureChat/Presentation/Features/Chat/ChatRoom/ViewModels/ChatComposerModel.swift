//
//  ChatComposerModel.swift
//  FeatureChat
//

import Foundation

/// Holds the text currently in the chat room's composer.
///
/// Split off `ChatRoomViewModel` because it changes on every keystroke. On the
/// room view model each character published to every observer of the room — the
/// message list and each visible bubble — so typing re-evaluated and re-measured
/// the whole timeline, character by character. Only the composer bar needs to see
/// this, so only the composer bar observes it.
@MainActor
final class ChatComposerModel: ObservableObject {

    /// The live contents of the input field.
    ///
    /// Written both by the field itself (as the user types) and by the room view
    /// model (when an edit is started, or the composer is cleared after a send).
    @Published var text: String = ""

    init() {}
}
