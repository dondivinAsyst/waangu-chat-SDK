//
//  BubbleWrapper.swift
//  Pods
//
//  Created by Asyst on 7/8/25.
//

import SwiftUI

struct BubbleWrapper<Content: View>: View {
    let topPadding: CGFloat
    let content: Content

    init(topPadding: CGFloat, @ViewBuilder content: () -> Content) {
        self.topPadding = topPadding
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
                .padding(.top, topPadding)
                .padding(.horizontal, 8)
        }
    }
}
