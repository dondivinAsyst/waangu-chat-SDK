//
//  BubleTailViewModifier.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  CustomModifier.swift
//  chatpreview
//
//  Created by Asyst on 6/30/25.
//

import Foundation
import SwiftUI


private struct BubleTailViewModifier: ViewModifier {
    
    let direction : MessageDirection
    
    func body(content: Content) -> some View {
        // Background, not overlay: the tail must sit *behind* the bubble, not on
        // top of it. Every call site applies this after .background + .clipShape,
        // so the part of the tail inside the rounded rect is hidden by the opaque
        // bubble fill and only the nub outside the corner shows -- unchanged for
        // inset content like text, and no longer a coloured notch stamped over
        // edge-to-edge media (media group, single image, location).
        content.background(alignment: direction == .received ? .bottomLeading : .bottomTrailing ){
            BubleTailView(direction: direction)
        }
    }
}

private struct BubbleStringView: ViewModifier {
    
    func body(content: Content) -> some View {
        content.overlay{
           
         RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(Color.gray.opacity(0.3), lineWidth: 0.4)
            
        }
            
    }
    
}

extension View {
    public func applyTailView(_ direction: MessageDirection) -> some View {
        self.modifier(BubleTailViewModifier(direction: direction))
    }
    
   public func applyStrokeOnBubbleView() -> some View {
       self.modifier(BubbleStringView())
   }
}
