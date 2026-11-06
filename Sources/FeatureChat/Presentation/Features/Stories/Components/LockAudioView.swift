import SwiftUI
import Combine
import WaanguSharedUI

struct LockAudioView : View {
    @State private var seconds = 0
    @State var isRecording  = true
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    let timerAudio = Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()
    @State private var audioText = ""
    @State private var isAnimating = true
    
    
    var body: some View {
        VStack{
            HStack{
                Text(timeString(from: seconds)).font(.system(size: 25)).onReceive(timer){ _ in
                    if isRecording {
                        seconds += 1
                    }
                    
                }
                Text(audioText).animation(.easeInOut(duration: 0.1)).onReceive(timer){ _ in
                    if isAnimating {
                        audioText.append(".")
                    }
                    
                }.multilineTextAlignment(.trailing)
                    .lineLimit(1)
                    .frame(width: 300)
             
            }
        }
    }
}

#Preview {
    LockAudioView()
}
