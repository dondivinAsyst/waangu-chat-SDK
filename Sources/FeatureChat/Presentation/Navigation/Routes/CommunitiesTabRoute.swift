//
//  CommunitiesTabRoute.swift
//  FeatureChat
//
//  Communities tab navigation routes
//

import SwiftUI
import WaanguNavigationKit

public enum CommunitiesTabRoute: StackRoute {
    case root
    case communityDetail(communityId: String)
    case communityInfo(communityId: String)
    case communityMembers(communityId: String)
    case communitySettings(communityId: String)
    /// Joining a private community with its invite code.
    ///
    /// Creating one is not a route: it is a sheet raised from the tab, because
    /// it is a modal task with its own cancel — see `CommunityCreateFlowSheet`.
    case joinCommunity
}
