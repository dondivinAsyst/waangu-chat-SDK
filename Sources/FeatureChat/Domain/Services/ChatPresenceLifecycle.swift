import Foundation
import WaanguCoreKit

/// Publishes user presence on app lifecycle and chat auth events, and owns the
/// session-wide typing feed both the chat room and the discussion list read.
enum ChatPresenceLifecycle {

    static func start(
        repository: PresenceRepositoryProtocol,
        eventBus: any EventBusProtocol
    ) -> [Task<Void, Never>] {
        var tasks: [Task<Void, Never>] = []

        // Supervisor loops, same shape as the message inbox's: the realtime
        // client is not connected when the chat feature loads, so the first
        // subscribe attempt throws. Retry with backoff until it takes, and
        // re-attach whenever a feed ends — which it does on every background
        // suspend, since both topics are registered `.disconnect`.
        tasks.append(supervise("typing") { try await repository.runTypingFeed() })
        tasks.append(supervise("presence") { try await repository.runPresenceFeed() })

        if CurrentSessionInfo.shared.isAuthenticated {
           
            tasks.append(Task {
                await repository.sendUserPresence(status: .online, currentRideId: nil)
            })
        }

        tasks.append(Task {
            for await _ in eventBus.subscribe(to: AppDidEnterForegroundEvent.self) {
                await repository.sendUserPresence(status: .online, currentRideId: nil)
            }
        })

        tasks.append(Task {
            for await _ in eventBus.subscribe(to: AppDidEnterBackgroundEvent.self) {
                await repository.sendUserPresence(status: .offline, currentRideId: nil)
                // Whoever was typing when we suspended is not typing when we
                // come back, and no expiry ran while the app was asleep.
                await TypingStore.shared.clearAll()
            }
        })

        tasks.append(Task {
            for await _ in eventBus.subscribe(to: UserChatDidLoginEvent.self) {
                await repository.sendUserPresence(status: .online, currentRideId: nil)
            }
        })

        tasks.append(Task {
            for await _ in eventBus.subscribe(to: UserDidLogoutEvent.self) {
                await repository.sendUserPresence(status: .offline, currentRideId: nil)
                await TypingStore.shared.clearAll()
            }
        })

        return tasks
    }

    /// Runs `feed` forever: retrying while it throws (not connected yet) and
    /// re-attaching each time it returns (subscription cancelled).
    private static func supervise(
        _ category: String,
        _ feed: @escaping @Sendable () async throws -> Void
    ) -> Task<Void, Never> {
        Task {
            var backoffNanoseconds: UInt64 = 500_000_000
            while !Task.isCancelled {
                do {
                    try await feed()
                    backoffNanoseconds = 500_000_000
                } catch {
                    debugLog("attach failed: \(error)", category: category)
                }

                guard !Task.isCancelled else { break }
                try? await Task.sleep(nanoseconds: backoffNanoseconds)
                backoffNanoseconds = min(backoffNanoseconds * 2, 8_000_000_000)
            }
        }
    }
}
