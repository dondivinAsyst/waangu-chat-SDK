import SwiftUI
import WaanguSharedUI

struct MiniAudioPlayerView: View {
    @ObservedObject var globalManager: GlobalAudioPlaybackManager
    
    var body: some View {
        if let audio = globalManager.currentlyPlayingAudio,
           let coordinator = globalManager.coordinator(for: audio.messageId) {
            MiniAudioPlayerContent(
                audio: audio,
                coordinator: coordinator,
                globalManager: globalManager
            )
        } else {
            EmptyView()
        }
    }
}

// MARK: - Content (observes live coordinator progress)

private struct MiniAudioPlayerContent: View {
    let audio: PlayingAudioInfo
    @ObservedObject var coordinator: PlaybackCoordinator
    @ObservedObject var globalManager: GlobalAudioPlaybackManager
    
    private var elapsedTime: TimeInterval {
        Double(coordinator.progress) * audio.duration
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Button(action: togglePlayback) {
                Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 32, height: 32)
                    .background(AppColors.primary)
                    .clipShape(Circle())
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("\(audio.senderName) • \(audio.chatName)")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(height: 2)
                        
                        Rectangle()
                            .fill(AppColors.primary)
                            .frame(width: geo.size.width * coordinator.progress, height: 2)

                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 10, height: 10)
                            .offset(x: max(0, min(geo.size.width * coordinator.progress - 5, geo.size.width - 10)))
                    }
                    .frame(maxHeight: .infinity, alignment: .center)
                    .contentShape(Rectangle())
                    .gesture(miniPlayerSeekGesture(width: geo.size.width))
                }
                .frame(height: 16)
                
                HStack {
                    Text(timeString(from: elapsedTime))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    if !globalManager.playbackQueue.isEmpty {
                        Text("+\(globalManager.playbackQueue.count)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                    
                    Text(timeString(from: audio.duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Button(action: { globalManager.stop() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 24, height: 24)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 60)
        .background(Color(.systemBackground))
        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
    }
    
    private func togglePlayback() {
        if coordinator.isPlaying {
            globalManager.pause()
        } else {
            globalManager.resume()
        }
    }

    private func miniPlayerSeekGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let fraction = fractionAt(x: value.location.x, width: width)
                if !coordinator.isDragging {
                    coordinator.setDragging(true)
                }
                coordinator.seekTo(fraction)
            }
            .onEnded { _ in
                coordinator.setDragging(false)
                globalManager.seek(to: coordinator.progress)
            }
    }

    private func fractionAt(x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return max(0, min(1, x / width))
    }
    
    private func timeString(from seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
