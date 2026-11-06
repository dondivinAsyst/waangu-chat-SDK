//
//  CallTheme.swift
//  FeatureChat
//
//  Design tokens shared by every call surface (incoming, audio, video).
//  Keeping them in one place means the call screens stay visually coherent
//  and a palette change is a one-file edit.
//

import SwiftUI

enum CallTheme {

    // MARK: - Palette

    enum Palette {
        /// Full-screen incoming call backdrop — near-black, cooling to slate at the bottom.
        static let incomingTop = Color(red: 0.106, green: 0.106, blue: 0.118)
        static let incomingBottom = Color(red: 0.157, green: 0.196, blue: 0.220)

        /// In-call canvas behind the doodle pattern.
        static let canvas = Color(red: 0.043, green: 0.078, blue: 0.102)
        static let canvasElevated = Color(red: 0.086, green: 0.086, blue: 0.090)

        /// Doodle stroke — barely-there texture, never competes with content.
        static let doodle = Color.white.opacity(0.035)

        /// Control surfaces.
        static let controlIdle = Color.white.opacity(0.14)
        static let controlActive = Color.white
        static let controlPanel = Color.white.opacity(0.09)
        static let controlIconIdle = Color.white
        static let controlIconActive = Color.black

        /// Call actions.
        static let endCall = Color(red: 0.957, green: 0.196, blue: 0.290)
        static let declineCall = Color(red: 0.702, green: 0.137, blue: 0.122)
        static let acceptVideo = Color(red: 0.106, green: 0.431, blue: 0.953)
        static let acceptAudio = Color(red: 0.204, green: 0.780, blue: 0.349)

        /// Text.
        static let primaryText = Color.white
        static let secondaryText = Color.white.opacity(0.66)
        static let tertiaryText = Color.white.opacity(0.42)
        /// Warm tint used for the remote party's name over video.
        static let remoteName = Color(red: 0.953, green: 0.835, blue: 0.780)

        /// Slide-to-answer knob chevron.
        static let answerChevron = Color(red: 0.039, green: 0.518, blue: 1.0)
    }

    // MARK: - Metrics

    enum Metric {
        /// Grid control button (audio call panel).
        static let gridControlDiameter: CGFloat = 64
        /// Compact control button (video call pill).
        static let pillControlDiameter: CGFloat = 56
        /// Incoming-call secondary action (Message / Remind Me).
        static let secondaryActionDiameter: CGFloat = 54
        /// Incoming-call primary action (Decline / Accept).
        static let primaryActionDiameter: CGFloat = 76
        /// Slide-to-answer track.
        static let slideTrackHeight: CGFloat = 74
        static let slideKnobDiameter: CGFloat = 66
        /// Self-preview picture-in-picture.
        static let pipWidth: CGFloat = 118
        static let pipHeight: CGFloat = 172
        static let pipCornerRadius: CGFloat = 18
        static let pipCompactWidth: CGFloat = 92
        static let pipCompactHeight: CGFloat = 134

        static let panelCornerRadius: CGFloat = 26
        static let topBarControlDiameter: CGFloat = 44
    }

    // MARK: - Typography

    enum TextStyle {
        static let incomingTitle = Font.system(size: 40, weight: .bold)
        static let incomingSubtitle = Font.system(size: 22, weight: .semibold)
        static let connectedName = Font.system(size: 22, weight: .semibold)
        static let remoteNameLarge = Font.system(size: 30, weight: .semibold)
        static let duration = Font.system(size: 15, weight: .regular).monospacedDigit()
        static let controlLabel = Font.system(size: 13, weight: .regular)
        static let actionLabel = Font.system(size: 15, weight: .regular)
        static let slideHint = Font.system(size: 20, weight: .regular)
    }

    // MARK: - Motion

    enum Motion {
        static let controlsFade = Animation.easeInOut(duration: 0.22)
        static let knobReturn = Animation.spring(response: 0.32, dampingFraction: 0.72)
        static let pipSnap = Animation.spring(response: 0.35, dampingFraction: 0.78)
        static let phaseChange = Animation.easeInOut(duration: 0.3)
    }
}
