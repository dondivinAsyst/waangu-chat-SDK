//
//  Font+extensions.swift
//  AppModules
//
//  Created by Don divin on 4/3/26.
//

import SwiftUI

public extension Font {
    // MARK: - Headings
    static let appLargeTitle = Font.system(size: 34, weight: .bold)
    static let appTitle1 = Font.system(size: 28, weight: .bold)
    static let appTitle2 = Font.system(size: 22, weight: .bold)
    static let appTitle3 = Font.system(size: 20, weight: .semibold)

    // MARK: - Body
    static let appHeadline = Font.system(size: 17, weight: .semibold)
    static let appBody = Font.system(size: 17, weight: .regular)
    static let appCallout = Font.system(size: 16, weight: .regular)
    static let appSubheadline = Font.system(size: 15, weight: .regular)

    // MARK: - Small
    static let appFootnote = Font.system(size: 13, weight: .regular)
    static let appCaption1 = Font.system(size: 12, weight: .regular)
    static let appCaption2 = Font.system(size: 11, weight: .regular)

    // MARK: - Buttons
    static let appButtonLarge = Font.system(size: 17, weight: .semibold)
    static let appButtonMedium = Font.system(size: 15, weight: .semibold)
    static let appButtonSmall = Font.system(size: 13, weight: .semibold)

    // MARK: - Input
    static let appInputLabel = Font.system(size: 14, weight: .bold)
    static let appInputText = Font.system(size: 16, weight: .regular)
    static let appInputError = Font.system(size: 12, weight: .regular)
}

public extension Text {
    func appStyle(_ font: Font, color: Color = .appText) -> Text {
        self.font(font).foregroundColor(color)
    }
}
