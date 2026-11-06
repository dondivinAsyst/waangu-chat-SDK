//
//  CircularProgressView.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  CircularProgressView.swift
//  Pods
//
//  Created by Asyst on 8/19/25.
//
import SwiftUI

public struct CircularProgressView: View {
    var size: CGFloat = 40
    var lineWidth: CGFloat = 3
    var color: Color = .accentColor
    var progress: Double
    var repeatForever : Bool = false
    var showBackground : Bool = true
    var cancelIcon : String = "stop.fill"
    var action: () -> Void
    public init(size: CGFloat = 40, lineWidth: CGFloat = 3, color: Color = .accentColor, progress: Double, repeatForever: Bool = false, showBackground: Bool = true, cancelIcon: String = "stop.fill", action: @escaping () -> Void) {
        self.size = size
        self.lineWidth = lineWidth
        self.color = color
        self.progress = progress
        self.repeatForever = repeatForever
        self.showBackground = showBackground
        self.cancelIcon = cancelIcon
        self.action = action
    }
    
   public var body: some View {
        Button(action:action) {
            ZStack {
                // Fond plein (background)
                if showBackground {
                    Circle()
    //                    .fill(.regularMaterial)
                        .fill(Color.black.opacity(0.8))
                        .frame(width: 52, height: 52)
                }
           
           
                
                if repeatForever {
                    CircularLoader(size: size,lineWidth: lineWidth,color: color)
                }else {
                    Circle()
                        .stroke(lineWidth: 3)
                        .opacity(0.3)
                        .foregroundColor(.blue)
                        .padding(5)
                    
                    Circle()
                        .trim(from: 0.0, to: CGFloat(progress))
                        .stroke(style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .foregroundColor(.blue)
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.3), value: progress)
                        .padding(5)
                }
                
              
                
                Image(systemName: cancelIcon)
                    .foregroundColor(color)
                    .font(.system(size: 13))
                    .padding(4)
            }
            .frame(width: 33, height: 33)
//            .background(.black.opacity(0.8))
        }
        .buttonStyle(.plain)
    }
}


public struct CircularLoader: View {
    var size: CGFloat = 40
    var lineWidth: CGFloat = 3
    var color: Color = .accentColor
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isAnimating = false
    
  public  var body: some View {
        Circle()
            .trim(from: 0, to: 0.75)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .frame(width: size, height: size)
            .rotationEffect(.degrees(isAnimating ? 360 : 0))
            .animation(reduceMotion ? nil : .linear(duration: 1).repeatForever(autoreverses: false),
                       value: isAnimating)
            .onAppear { isAnimating = true }
            .accessibilityLabel("Loading")
    }
}
