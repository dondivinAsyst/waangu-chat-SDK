//
//  ChannelCommunityDebugConfiguration.swift
//  FeatureChat
//
//  Which channel/community routes are served from memory while Identity has no
//  endpoint for them. Same shape as JoinRequestDebugConfiguration.
//

import Foundation

#if DEBUG

/// Four capabilities the integration doc describes but Identity does not expose:
/// a channel description, channel admins, community permissions, and joining a
/// sub-group. Each is served from `ChannelCommunityDebugMockStore` until the
/// route exists.
///
/// Flip a flag to `false` and that call goes to the network instead — the
/// endpoints, DTOs and repositories are already written for the real thing, so
/// nothing else changes.
enum ChannelCommunityDebugConfiguration {
    static var useMockChannelDescription = true
    static var useMockChannelAdmins = true
    static var useMockCommunitySettings = true
    static var useMockCommunityGroupJoin = true
}

#endif
