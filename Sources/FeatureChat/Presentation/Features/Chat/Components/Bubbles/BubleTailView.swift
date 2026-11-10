//
//  BubleTailView.swift
//  chatpreview
//
//  Created by Asyst on 6/30/25.
//

import SwiftUI

struct BubleTailView: View {
    let direction:MessageDirection
    private var backgroundColor: Color {
        return direction == .sent ?  Color("bubbleSent", bundle: .module) : Color("bubbleReceived", bundle: .module)
    }
    
    var body: some View {
        VStack{
            Image(direction == .sent ? "outgoingTail" : "incomingTail", bundle: .module)
                .renderingMode(.template)
                .resizable()
                .frame(width: 10, height: 10)
                .offset(y: 3)
                .foregroundColor(backgroundColor)
        }
    }
}

#Preview {
    ScrollView{
        BubleTailView(direction: .received)
        BubleTailView(direction: .sent)
    }
}
