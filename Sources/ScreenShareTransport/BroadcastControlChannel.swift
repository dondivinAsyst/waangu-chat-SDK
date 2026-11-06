//
//  BroadcastControlChannel.swift
//  ScreenShareTransport
//
//  App → extension stop signalling.
//
//  The app cannot terminate a broadcast extension. Only the extension can, by
//  calling `finishBroadcastWithError`. A Darwin notification is the one channel
//  that crosses into a process we hold no handle to.
//
//  Coalescing — the reason this mechanism was rejected for the frame path — is
//  harmless here: "stop" carries no payload and is idempotent.
//

import Foundation
// `notify_post` and friends live in their own clang module. Neither `Darwin`
// nor `Darwin.notify` re-exports them, and Foundation does not either.
import notify

public enum BroadcastControlChannel {

    /// Must be identical in both processes. Darwin notification names are a
    /// global namespace, so this carries the bundle domain as a prefix.
    public static let stopNotificationName = "com.waangu.screenshare.stop"

    /// `NOTIFY_TOKEN_INVALID` from `notify.h`, restated rather than imported:
    /// the macro does not reliably surface in Swift.
    public static let invalidToken: Int32 = -1

    public static func requestStop() {
        notify_post(stopNotificationName)
    }

    /// Returns a token for `removeObserver`. `handler` runs on `queue`.
    public static func observeStopRequests(
        on queue: DispatchQueue = .main,
        _ handler: @escaping () -> Void
    ) -> Int32 {
        var token = invalidToken
        let status = notify_register_dispatch(
            stopNotificationName,
            &token,
            queue
        ) { _ in handler() }

        guard status == NOTIFY_STATUS_OK else { return invalidToken }
        return token
    }

    public static func removeObserver(_ token: Int32) {
        guard token != invalidToken else { return }
        notify_cancel(token)
    }
}
