//
//  WaanguChatVersion.swift
//  WaanguChatSDK
//
//  The version of the SDK a host is running (SDK plan, step 1.2).
//

import Foundation

/// The released version of the chat SDK, for a host's logs, support tools and telemetry.
///
/// The release script (`Scripts/publish/publish_waangu_chat.sh`) replaces the placeholder below
/// with the version it publishes, in the same way it stamps the README, and refuses to publish if
/// that did not happen. In a development checkout nothing replaces it, and `current` reports
/// `development`: such a build never claims to be a release.
public enum WaanguChatVersion {

    /// Replaced at release time. Keep it on one line and spelled exactly like this.
    private static let stamped = "0.1.0"

    /// What a build that was not released reports.
    public static let development = "0.0.0-dev"

    /// `true` for a published release, `false` for a development checkout.
    public static var isRelease: Bool { !stamped.hasPrefix("{{") }

    /// `x.y.z` for a release, `0.0.0-dev` otherwise.
    public static var current: String { isRelease ? stamped : development }
}
