//
//  CallsDestinationView.swift
//  FeatureChat
//
//  Calls tab destination routing
//

import SwiftUI

@available(iOS 16.0, *)
struct CallsDestinationView: View {
    let route: CallsTabRoute
    let coordinator: CallsTabCoordinator
    
    var body: some View {
        switch route {
        case .root:
            EmptyView()
            
        case .createCall:
            EmptyView() // Placeholder for create call view
            
        case .callHistory:
            EmptyView() // Placeholder for call history view
            
        case .callDetails(let callId):
            EmptyView() // Placeholder for call details view
        }
    }
}
