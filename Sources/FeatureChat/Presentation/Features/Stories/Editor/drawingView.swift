import SwiftUI
import AVKit
import WaanguCoreKit

struct Line :Hashable {
    var points: [CGPoint]
    var color: Color
    var lineWidth: CGFloat
}

struct DrawingView: View {
    @Binding var lines: [Line]
    @Binding  var currentLine: Line?
    @Binding  var selectedColor: Color
    @Binding var drawOnImage : Bool
    @Binding var currentPlayer: AVPlayer
    @Binding var selectedLineWidth: CGFloat
    @Binding var currentInfo: MediaInfo
    var imageRect : CGRect = .zero
    let translationService: (any TranslationServiceProtocol)?
    @State private var showColorPicker = false
    @State private var isAppeared = false

    init(
        lines: Binding<[Line]>,
        currentLine: Binding<Line?>,
        selectedColor: Binding<Color>,
        drawOnImage: Binding<Bool>,
        currentPlayer: Binding<AVPlayer>,
        selectedLineWidth: Binding<CGFloat>,
        currentInfo: Binding<MediaInfo>,
        imageRect: CGRect = .zero,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._lines = lines
        self._currentLine = currentLine
        self._selectedColor = selectedColor
        self._drawOnImage = drawOnImage
        self._currentPlayer = currentPlayer
        self._selectedLineWidth = selectedLineWidth
        self._currentInfo = currentInfo
        self.imageRect = imageRect
        self.translationService = translationService
    }
    
    let availableLineWidths: [CGFloat] = [2, 5, 8, 12, 16]
    
    
    let availableColors: [Color] = [.red, .blue, .green, .yellow, .orange, .purple, .white, .black]
//    let image: UIImage
    
    func fontWeight(for width: CGFloat) -> Font.Weight {
        switch width {
        case 0..<3:
            return .regular
        case 3..<6:
            return .medium
        case 6..<10:
            return .semibold
        default:
            return .bold
        }
    }
    
    var body: some View {
        
        ZStack {
            
//             Background Image
//            Image(uiImage: image)
//                .resizable()
//                .aspectRatio(contentMode: .fit)
            VStack{
                // Drawing Canvas
                Canvas { context, size in
                    for line in lines {
                        var path = Path()
                        path.addLines(line.points)
                        context.stroke(
                            path,
                            with: .color(line.color),
                            lineWidth: line.lineWidth
                        )
                    }
                    
                    if let currentLine = currentLine {
                        var path = Path()
                        path.addLines(currentLine.points)
                        context.stroke(
                            path,
                            with: .color(currentLine.color),
                            lineWidth: currentLine.lineWidth
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let point = value.location
//                            if self.imageRect.contains(point) || self.imageRect == .zero {
                                if currentLine == nil {
                                    currentLine = Line(points: [point], color: selectedColor, lineWidth: selectedLineWidth)
                                } else {
                                    currentLine?.points.append(point)
                                }
//                            }
                        }
                        .onEnded { _ in
                            if let line = currentLine {
                                lines.append(line)
                                currentLine = nil
                            }
                        }
                ).frame(
                    maxWidth: currentInfo.imageRenderedSize.width > 0 ? currentInfo.imageRenderedSize.width : .infinity,
                    maxHeight: currentInfo.imageRenderedSize.height > 0 ? currentInfo.imageRenderedSize.height : .infinity
                )
            }
     
            
            // Color Picker UI
            VStack {
               
                
                HStack(spacing: 15) {
                    Button(action: {
                       debugLog("Done drawing")
                        withAnimation(.easeInOut){
                            drawOnImage = false
                           if currentInfo.media?.type == .video {
                                currentPlayer.play()
                            }
                            
                        }
                    }) {
                        Text(t(ChatTranslationKeys.STORIES_DONE))
                            .foregroundStyle(.primary)
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(28)
                    }
                    Spacer()
                    // Undo Button
                    Button(action: {
                        if !lines.isEmpty {
                            lines.removeLast()
                        }
                    }) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    // Color Selector
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)){
                            showColorPicker.toggle()
                        }
                    }) {
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 50, height: 50)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                            )
                            .shadow(radius: 3)
                    }
                    
                    // Clear All Button
                    Button(action: {
                        lines.removeAll()
                    }) {
                        Image(systemName: "trash")
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(width: 50, height: 50)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                }.padding(.horizontal,10).offset(y:isAppeared ? 0 : -200)
                Spacer()
                
                HStack (spacing:15){
                    Spacer()
                    ForEach(availableLineWidths.indices, id: \.self){ index in
//                        Button(action: {
//                            withAnimation(.easeInOut(duration: 0.3)){
//                                selectedLineWidth = availableLineWidths[index]
//                            }
//                        }) {
//                            Text(availableLineWidths[index] == 2 ? "sm" : availableLineWidths[index] == 5 ? "md" :availableLineWidths[index] == 8 ? "lg" : availableLineWidths[index] == 12 ? "xl" : "xxl")
//                                .font(.caption)
                            Image(systemName: "scribble.variable")
                                .resizable()
                                .scaledToFit()
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.white.opacity(0.2))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 50)
                                        .stroke(selectedColor,
                                                lineWidth: selectedLineWidth == availableLineWidths[index] ? 5 : 0)
                                )
                                .cornerRadius(50)
                                // 💡 Set boldness using font weight
                                .font(.system(size: 20, weight: fontWeight(for: availableLineWidths[index]))).onTapGesture {
                                    withAnimation(.linear(duration: 0.3)){
                                        selectedLineWidth = availableLineWidths[index]
                                    }
                                }

//                                .clipShape(Circle())
//                        }
                        
                    }.offset(y:isAppeared ? 0 : 200).allowsHitTesting(true)
                    Spacer()
                }
                
                // Color Options (shown when color picker is active)
                if showColorPicker {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 15) {
                            ForEach(availableColors, id: \.self) { color in
                                Button(action: {
                                    withAnimation(.easeInOut(duration: 0.3)){
                                        selectedColor = color
                                        showColorPicker = false
                                    }
                                 
                                }) {
                                    Circle()
                                        .fill(color)
                                        .frame(width: 40, height: 40)
                                        .overlay(
                                            Circle()
                                                .stroke(selectedColor == color ? Color.white : Color.clear, lineWidth: 3)
                                        )
                                        .shadow(radius: 2)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 20)
                    .background(Color.black.opacity(0.3))
                }
            }
        }.background(.black.opacity(0.01)).onAppear{
            withAnimation(.easeInOut(duration: 0.5)){
                isAppeared = true
            }
        }

      
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}




