//
//  ChatFeatureEnvironment.swift
//  FeatureChat
//
//  Created by Refactoring on 5/6/26.
//

import SwiftUI

// MARK: - Environment Key

private struct ChatFeatureKey: EnvironmentKey {
    static let defaultValue: ChatFeature? = nil
}

extension EnvironmentValues {
    var chatFeature: ChatFeature? {
        get { self[ChatFeatureKey.self] }
        set { self[ChatFeatureKey.self] = newValue }
    }
}

// MARK: - View Extension

extension View {
    public func chatFeature(_ feature: ChatFeature) -> some View {
        environment(\.chatFeature, feature)
    }
}
