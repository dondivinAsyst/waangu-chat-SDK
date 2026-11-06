//
//  AppSpacing.swift
//  AppModules
//
//  Created by Don divin on 4/3/26.
//


//
//  AppSpacing.swift
//  AppModules
//
//  Created by Don divin on 4/3/26.
//


import SwiftUI

public enum AppSpacing {
    /// 4pt
    public static let xxxs: CGFloat = 4
    /// 6pt
    public static let xxs: CGFloat = 6
    /// 8pt
    public static let xs: CGFloat = 8
    /// 12pt
    public static let sm: CGFloat = 12
    /// 16pt
    public static let md: CGFloat = 16
    /// 20pt
    public static let lg: CGFloat = 20
    /// 24pt
    public static let xl: CGFloat = 24
    /// 32pt
    public static let xxl: CGFloat = 32
    /// 40pt
    public static let xxxl: CGFloat = 40
    /// 48pt
    public static let huge: CGFloat = 48

    // MARK: - Screen Padding
    public static let screenHorizontal: CGFloat = 16
    public static let screenVertical: CGFloat = 16

    // MARK: - Section
    public static let sectionSpacing: CGFloat = 24
    public static let itemSpacing: CGFloat = 12
    public static let inlineSpacing: CGFloat = 8
}

public extension EdgeInsets {
    public static let appScreen = EdgeInsets(
        top: AppSpacing.screenVertical,
        leading: AppSpacing.screenHorizontal,
        bottom: AppSpacing.screenVertical,
        trailing: AppSpacing.screenHorizontal
    )

    public static let appCard = EdgeInsets(
        top: AppSpacing.md,
        leading: AppSpacing.md,
        bottom: AppSpacing.md,
        trailing: AppSpacing.md
    )
}
