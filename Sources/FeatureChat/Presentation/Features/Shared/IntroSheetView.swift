//
//  IntroSheetView.swift
//  FeatureChat
//
//  The explain-then-continue sheet used before creating a community or a
//  channel, and once before channels are used at all.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// One line of an intro sheet: a symbol, a heading, a sentence.
struct IntroSheetPoint: Identifiable {

    let symbol: String
    let title: String
    let detail: String

    var id: String { symbol + title }

    init(symbol: String, title: String, detail: String) {
        self.symbol = symbol
        self.title = title
        self.detail = detail
    }
}

/// Explains what a thing is before the user commits to making one.
///
/// A picture band in the app blue carries the subject's badge; the title, the
/// text and the points arrive one after another under it. The structure follows
/// the convention users already know for these sheets; the palette (the app's
/// blue only) and the glyphs are ours.
@available(iOS 16.0, *)
struct IntroSheetView: View {

    let symbol: String
    let title: String
    /// Shown under the title when the sheet explains rather than lists.
    let body_: String?
    let points: [IntroSheetPoint]
    let confirmTitle: String
    let onConfirm: () -> Void
    let onDismiss: () -> Void

    init(
        symbol: String,
        title: String,
        body: String? = nil,
        points: [IntroSheetPoint] = [],
        confirmTitle: String,
        onConfirm: @escaping () -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.symbol = symbol
        self.title = title
        self.body_ = body
        self.points = points
        self.confirmTitle = confirmTitle
        self.onConfirm = onConfirm
        self.onDismiss = onDismiss
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    ChatHeroBand(symbol: symbol, height: 200)

                    VStack(spacing: 14) {
                        Text(title)
                            .font(.title2.weight(.bold))
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AppColors.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .staggeredAppear(1)

                        if let body_ {
                            Text(body_)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .staggeredAppear(2)
                        }
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 24)

                    if !points.isEmpty {
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                                pointRow(point)
                                    .staggeredAppear(3 + index)
                            }
                        }
                        .padding(20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 22, style: .continuous)
                                .fill(AppColors.primary.opacity(0.05))
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollBounceBehavior(.basedOnSize)

            confirmButton()
                .staggeredAppear(3 + points.count)
        }
        .overlay(alignment: .topTrailing) { closeButton() }
        .background(AppColors.background)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func closeButton() -> some View {
        Button(action: onDismiss) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .accessibilityLabel(Text(verbatim: "Close"))
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    @ViewBuilder
    private func pointRow(_ point: IntroSheetPoint) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ChatSymbolBadge(symbol: point.symbol, size: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(point.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private func confirmButton() -> some View {
        Button(action: onConfirm) {
            Text(confirmTitle)
                .font(.headline)
                .foregroundStyle(Color.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(AppColors.primary, in: Capsule())
                .shadow(color: AppColors.primary.opacity(0.30), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
    }
}
