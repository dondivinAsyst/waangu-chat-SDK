//
//  BubbleWalletMoney.swift
//  chatpreview
//
//  Created by Asyst on 7/3/25.
//

import SwiftUI

struct BubbleWalletMoney: View {
    let message:MessageItem
    @Environment(\.colorScheme) private var colorScheme
    
    let price: Double = 1999.99
    var body: some View {
        HStack{
            VStack {
                
                VStack {
                    Text(price, format: .currency(code: "BIF"))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .bold()
                        .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                    
                }
                
                .frame(maxWidth: .infinity)
                .frame( height: 150)
                .background(ChatBubbleStyle.mutedOverlay(for: colorScheme))
                    .clipShape(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                    .overlay{
//                        Image(.logo)
//                            .resizable()
//                            .scaledToFit()
//                            .frame(width: 32, height: 32)
//                            .clipShape(
//                                RoundedRectangle(cornerRadius: 32, style: .continuous)
//                            )
//                            .padding(.trailing,UIScreen.main.bounds.width - 130)
//                            .padding(.bottom,130)
                    }
                    .overlay{
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.gray.opacity(0.5),style: StrokeStyle(lineWidth: 1, dash: [3], dashPhase: 0,))
                    }
             
                
                if !message.text.isEmpty {
                    
                    if #available(iOS 16.0, *) {
                        ViewThatFits(in: .horizontal) {
                            // 1. Horizontal layout si y'a de la place
                            HStack(alignment: .lastTextBaseline, spacing: 0) {
                                Text(message.text)
                                    .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))

                                Spacer()

                                timeStampView()
                            }

                            // 2. Fallback layout: Vertical
                            VStack(alignment: .leading, spacing: -2) {
                                Text(message.text)
                                    .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))

                                HStack {
                                    Spacer()
                                    timeStampView()
                                }
                            }
                        }
                        .padding(.horizontal, 5)
                    } else {
                        // Fallback pour iOS < 16 (par défaut vertical)
                        VStack(alignment: .leading, spacing: -2) {
                            Text(message.text)
                                .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))

                            HStack {
                                Spacer()
                                timeStampView()
                            }
                        }
                        .padding(.horizontal, 5)
                    }
                 
                }
             
            }
            .padding(10)
            .background(message.backgroundColor)
            .clipShape(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .applyStrokeOnBubbleView()
            .applyTailView(message.direction)
            .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
            
          
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .padding(.leading, message.direction == .received ? 5 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 5)
        .id(message.id)
    }
    
    func timeStampView() -> some View {
        HStack  {
          
            Text("message.timestamp")
                .font(.caption)
                .foregroundColor(ChatBubbleStyle.secondaryForeground(for: colorScheme))
            
            if message.direction == .sent {
                Image.custom("double.stick")
                    .resizable()
                    .renderingMode(.template)
                    .frame(width: 22,height: 22)
                    .foregroundColor(Color(.systemBlue))
                   
            }
            
        }
    }
}

#Preview {
    BubbleWalletMoney(message: .receivedPlaceholder)
}


extension View {
    func dashStyle(lineWidth: CGFloat = 1, dash: [CGFloat] = [5]) -> some View {
        self.overlay(
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0))
                }
                .stroke(style: StrokeStyle(lineWidth: lineWidth, dash: dash))
                .foregroundColor(.gray)
            }
            .frame(height: lineWidth),
            alignment: .top
        )
    }
}
