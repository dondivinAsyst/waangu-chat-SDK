//
//  ForwardMessageSource.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// A room that can hand messages to the forward picker.
///
/// The picker used to be typed to `ChatRoomViewModel`, which is the only reason a
/// channel post could not be forwarded. It needs three things from a room — what
/// to forward, how to say it, and somewhere to send it — so those are the three
/// things it asks for.
@MainActor
protocol ForwardMessageSource: AnyObject {

    /// What the user picked. Empty means there is nothing to forward.
    var messagesToForward: [MessageDataItem] { get }

    var translationService: (any TranslationServiceProtocol)? { get }

    /// Sends them on, and clears whatever selection the room was holding.
    func forward(
        to targets: [ForwardTarget],
        caption: String?,
        statusPoster: (any ForwardStatusPosting)?
    ) async
}
