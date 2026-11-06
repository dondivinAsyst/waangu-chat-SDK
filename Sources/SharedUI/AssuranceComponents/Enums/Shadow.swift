//
//  AppShadow.swift
//  AppModules
//
//  Created by Don divin on 4/3/26.
//


import SwiftUI

public enum AppShadow {
    case none
    case sm
    case md
    case lg

    public var color: Color {
        switch self {
        case .none: return .clear
        case .sm: return .black.opacity(0.06)
        case .md: return .black.opacity(0.10)
        case .lg: return .black.opacity(0.16)
        }
    }

    public var radius: CGFloat {
        switch self {
        case .none: return 0
        case .sm: return 4
        case .md: return 8
        case .lg: return 16
        }
    }

    public var y: CGFloat {
        switch self {
        case .none: return 0
        case .sm: return 2
        case .md: return 4
        case .lg: return 8
        }
    }
}

public extension View {
    func appShadow(_ style: AppShadow) -> some View {
        self.shadow(color: style.color, radius: style.radius, x: 0, y: style.y)
    }
}
