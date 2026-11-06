//
//  CallAppearanceSheet.swift
//  FeatureChat
//
//  Sheet presentation for surfaces that sit on top of a call.
//
//  Call chrome is unconditionally dark — every call view forces
//  `.environment(\.colorScheme, .dark)` over the `CallTheme` palette. A sheet
//  raised from it has to match, so it pins `.dark` rather than following the
//  user's chat appearance preference.
//
//  This is why `chatAppearanceSheet` is wrong here: it applies
//  `ChatAppearanceStore.defaultAppearance` (which defaults to `.system`) to the
//  presented content, and because that modifier wraps the sheet body from the
//  outside, it also overrides any `.preferredColorScheme` the sheet sets on
//  itself — a light sheet over black call chrome, with no way for the sheet to
//  opt out.
//

import SwiftUI

extension View {

    /// Presents a sheet over call chrome, forced to dark.
    func callAppearanceSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(item: item, onDismiss: onDismiss) { item in
            content(item)
                .preferredColorScheme(.dark)
        }
    }

    /// Presents a sheet over call chrome, forced to dark.
    func callAppearanceSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) {
            content()
                .preferredColorScheme(.dark)
        }
    }
}
