//
//  MediasoupVideoRendererFactory.swift
//  CallMediaKit
//
//  Builds the actual video surface. Kept behind `CallVideoRendererFactoryProtocol`
//  so the call UI can show video without linking WebRTC.
//

#if canImport(UIKit)
import UIKit
import WaanguCoreKit
import WebRTC

@MainActor
public struct MediasoupVideoRendererFactory: CallVideoRendererFactoryProtocol {

    public init() {}

    public func makeVideoView(
        for track: any CallVideoTrackProtocol,
        mirrored: Bool,
        fillsBounds: Bool
    ) -> UIView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = fillsBounds ? .scaleAspectFill : .scaleAspectFit

        // The front camera preview is flipped so it reads as a mirror, which is
        // what every other call app does and what users expect of themselves.
        if mirrored {
            view.transform = CGAffineTransform(scaleX: -1, y: 1)
        }

        if let mediasoupTrack = track as? MediasoupVideoTrack {
            mediasoupTrack.track.add(view)
        }
        return view
    }

    public func makePictureInPictureView(
        for track: any CallVideoTrackProtocol
    ) -> UIView {
        guard let mediasoupTrack = track as? MediasoupVideoTrack else {
            return UIView()
        }
        return MediasoupPictureInPictureVideoView(track: mediasoupTrack.track)
    }
}
#endif
