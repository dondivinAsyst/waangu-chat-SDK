//
//  UpdatesTabRoute.swift
//  FeatureChat
//
//  Updates/Stories tab navigation routes
//

import SwiftUI
import WaanguNavigationKit

public enum UpdatesTabRoute: StackRoute {
    case root
    case storieView(storyId: String)
    case myStoriesView
    case createStoryView
    case editTabStoryView(initialTab: EditorTab)
    case camera
    case statusEditorView(selectedMedia: [GalleryMedia])
    // Canaux Updates — creating one is a sheet, not a route.
    //
    // The room is here rather than in the chats tab: a subscription is not a
    // conversation the reader started, and sending them to Chats to read one
    // loses the way back to the channel list.
    case channelRoom(channelId: String)
    case channelDetail(channelId: String)
    case exploreChannels
}
