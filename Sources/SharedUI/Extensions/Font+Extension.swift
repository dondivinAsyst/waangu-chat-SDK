//
//  Font+Extension.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


import SwiftUI
import UIKit

extension Font {
   public func toUIFont() -> UIFont {
        switch self {
        case .largeTitle: return .preferredFont(forTextStyle: .largeTitle)
        case .title: return .preferredFont(forTextStyle: .title1)
        case .title2: return .preferredFont(forTextStyle: .title2)
        case .title3: return .preferredFont(forTextStyle: .title3)
        case .headline: return .preferredFont(forTextStyle: .headline)
        case .subheadline: return .preferredFont(forTextStyle: .subheadline)
        case .body: return .preferredFont(forTextStyle: .body)
        case .callout: return .preferredFont(forTextStyle: .callout)
        case .footnote: return .preferredFont(forTextStyle: .footnote)
        case .caption: return .preferredFont(forTextStyle: .caption1)
        case .caption2: return .preferredFont(forTextStyle: .caption2)
        default: return .systemFont(ofSize: UIFont.systemFontSize)
        }
    }
}
