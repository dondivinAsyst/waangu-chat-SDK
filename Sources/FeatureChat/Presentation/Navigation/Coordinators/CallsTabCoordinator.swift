//
//  CallsTabCoordinator.swift
//  FeatureChat
//
//  Calls tab coordinator following FeatureWallet pattern
//

import SwiftUI
import WaanguNavigationKit

@MainActor
@Observable
public final class CallsTabCoordinator: TabStackCoordinator {
    
    public var navigationPath = NavigationPath()
    public var onCrossFeature: ((NavigationIntent) -> Void)?
    public var pendingAction: (() -> Void)?
    
    public let feature: ChatFeature
    
    public init(feature: ChatFeature) {
        self.feature = feature
    }
    
    public func view() -> some View {
        CallsTabView(coordinator: self)
    }
    
    public func start() { }
    
    public func navigate(to route: CallsTabRoute) {
        push(route)
    }
}
