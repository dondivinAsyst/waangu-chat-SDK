//
//  CropWindowShape.swift
//  FeatureChat
//

import CoreGraphics

/// The window the crop gesture draws, and the shape the mask punches out of the
/// dimmed surround.
///
/// `freeform` is what the chat and stories editors have always used. `circle`
/// exists for avatars, which are rendered round everywhere in the app — cropping
/// them through a rectangle asks the user to guess what will survive.
enum CropWindowShape: Equatable {
    /// Rectangle with independently draggable corners.
    case freeform
    /// 1:1 window drawn as a circle.
    case circle

    /// Width ÷ height the crop window must keep, or `nil` when unconstrained.
    var lockedAspectRatio: CGFloat? {
        switch self {
        case .freeform: return nil
        case .circle: return 1
        }
    }

    /// The rule-of-thirds grid only makes sense inside a rectangle.
    var showsGrid: Bool {
        self == .freeform
    }
}
