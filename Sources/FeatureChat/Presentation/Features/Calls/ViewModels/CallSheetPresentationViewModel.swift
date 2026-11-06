//
//  CallSheetPresentationViewModel.swift
//  FeatureChat
//
//  Owns which secondary surface sits on top of an active call.
//
//  The connected call views only emit intent (`onMore`, `onAddParticipant`, …);
//  deciding what that opens is state, so it lives here rather than as scattered
//  `@State` flags across AudioCallConnectedView and VideoCallView. One optional
//  value also means two sheets can never race each other open.
//

import Foundation
import Combine

/// A secondary surface presented over an active call.
enum CallSheet: String, Identifiable {
    case moreOptions
    case addParticipant

    var id: String { rawValue }
}

@MainActor
final class CallSheetPresentationViewModel: ObservableObject {

    @Published var activeSheet: CallSheet?

    /// Delay before a replacement sheet appears. SwiftUI ignores a new sheet set
    /// in the same tick as the dismissal of the previous one, so the swap has to
    /// wait for the dismiss transition to land.
    private let swapDelay: Duration

    private var swapTask: Task<Void, Never>?

    init(swapDelay: Duration = .milliseconds(350)) {
        self.swapDelay = swapDelay
    }

    deinit {
        swapTask?.cancel()
    }

    func present(_ sheet: CallSheet) {
        swapTask?.cancel()
        activeSheet = sheet
    }

    func dismiss() {
        swapTask?.cancel()
        activeSheet = nil
    }

    /// Closes whatever is open and brings up `sheet` once the dismissal settles.
    /// Used by the More sheet, whose rows all lead to another surface.
    func replace(with sheet: CallSheet) {
        swapTask?.cancel()

        guard activeSheet != nil else {
            activeSheet = sheet
            return
        }

        activeSheet = nil
        swapTask = Task { [weak self, swapDelay] in
            try? await Task.sleep(for: swapDelay)
            guard !Task.isCancelled else { return }
            self?.activeSheet = sheet
        }
    }
}
