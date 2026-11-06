//
//  CallsTabRoute.swift
//  FeatureChat
//
//  Calls tab navigation routes
//

import SwiftUI
import WaanguNavigationKit

public enum CallsTabRoute: StackRoute {
    case root
    case createCall
    case callHistory
    case callDetails(callId: String)
}
