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
/// The mark at the top is an SF Symbol on a disc tinted with `AppColors.primary`
/// — the app's own colour. Nothing here is traced from another product: the
/// structure follows the convention users already know, the palette and the
/// glyphs are ours.
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
            closeButton()

            ScrollView {
                VStack(spacing: 24) {
                    mark()

                    Text(title)
                        .font(.title.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 24)

                    if let body_ {
                        Text(body_)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }

                    if !points.isEmpty {
                        VStack(alignment: .leading, spacing: 20) {
                            ForEach(points) { point in
                                pointRow(point)
                            }
                        }
                        .padding(.horizontal, 28)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }

            confirmButton()
        }
        .background(AppColors.background)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func closeButton() -> some View {
        HStack {
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(Circle().fill(Color(.systemGray5)))
            }
            .accessibilityLabel(Text(verbatim: "Close"))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    @ViewBuilder
    private func mark() -> some View {
        Image(systemName: symbol)
            .font(.system(size: 44, weight: .semibold))
            .foregroundStyle(AppColors.primary)
            .frame(width: 108, height: 108)
            .background(
                Circle().fill(AppColors.primary.opacity(0.12))
            )
    }

    @ViewBuilder
    private func pointRow(_ point: IntroSheetPoint) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: point.symbol)
                .font(.system(size: 18))
                .foregroundStyle(AppColors.primary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 3) {
                Text(point.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(point.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func confirmButton() -> some View {
        Button(action: onConfirm) {
            Text(confirmTitle)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppColors.primary)
                .foregroundStyle(AppColors.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 28)
    }
}
