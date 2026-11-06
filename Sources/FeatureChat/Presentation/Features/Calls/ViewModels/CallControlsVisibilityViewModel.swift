//
//  CallControlsVisibilityViewModel.swift
//  FeatureChat
//
//  Owns the auto-hide behaviour of the video call chrome.
//
//  Lives here rather than inside the view because it holds state and a
//  cancellable timer: a view should observe this, not run it. Any interaction
//  re-arms the countdown, and the pending hide is cancelled on disappear so a
//  dismissed call screen never mutates state after teardown.
//

import Foundation
import Combine

@MainActor
final class CallControlsVisibilityViewModel: ObservableObject {

    @Published private(set) var isVisible: Bool = true

    private var hideTask: Task<Void, Never>?
    private let autoHideDelay: Duration

    init(autoHideDelay: Duration = .seconds(4)) {
        self.autoHideDelay = autoHideDelay
    }

    deinit {
        hideTask?.cancel()
    }

    /// Reveals the chrome and restarts the countdown.
    func show() {
        isVisible = true
        scheduleHide()
    }

    func hide() {
        cancelPendingHide()
        isVisible = false
    }

    /// Tapping the remote feed flips the chrome; revealing it re-arms auto-hide.
    func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    /// Keeps the chrome up while the user is mid-interaction.
    func registerInteraction() {
        guard isVisible else { return }
        scheduleHide()
    }

    func cancelPendingHide() {
        hideTask?.cancel()
        hideTask = nil
    }

    private func scheduleHide() {
        cancelPendingHide()
        hideTask = Task { [weak self, autoHideDelay] in
            try? await Task.sleep(for: autoHideDelay)
            guard !Task.isCancelled else { return }
            self?.isVisible = false
        }
    }
}
