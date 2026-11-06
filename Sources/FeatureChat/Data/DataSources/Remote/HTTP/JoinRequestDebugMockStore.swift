//
//  JoinRequestDebugMockStore.swift
//  FeatureChat
//
//  In-memory join-request mocks for DEBUG builds.
//  Set JoinRequestDebugConfiguration.useMockJoinRequestAPI = false to hit real API.
//

import Foundation

#if DEBUG

enum JoinRequestDebugConfiguration {
    /// When `true`, join-request list/approve/decline use in-memory mocks instead of HTTP.
    static var useMockJoinRequestAPI = true
}

enum JoinRequestDebugMockStore {
    private static var store: [String: [GroupJoinRequestDto]] = [:]
    private static let lock = NSLock()

    static func fetch(groupId: String) -> [GroupJoinRequestDto] {
        lock.lock()
        defer { lock.unlock() }

        if store[groupId] == nil {
            store[groupId] = defaultMocks(for: groupId)
        }
        return store[groupId] ?? []
    }

    static func remove(groupId: String, requestId: String) {
        lock.lock()
        defer { lock.unlock() }
        store[groupId]?.removeAll { $0.id == requestId }
    }

    /// Re-seed mocks for a group (useful when testing again in the same session).
    static func reset(groupId: String) {
        lock.lock()
        defer { lock.unlock() }
        store[groupId] = defaultMocks(for: groupId)
    }

    private static func defaultMocks(for groupId: String) -> [GroupJoinRequestDto] {
        [
            GroupJoinRequestDto(
                id: "mock-join-req-1",
                groupId: groupId,
                userId: "mock-user-jane",
                userName: "Jane Doe",
                userPhone: "+243900000001",
                userAvatar: nil,
                requestedAt: Date().addingTimeInterval(-3600)
            ),
            GroupJoinRequestDto(
                id: "mock-join-req-2",
                groupId: groupId,
                userId: "mock-user-john",
                userName: "John Smith",
                userPhone: "+243900000002",
                userAvatar: nil,
                requestedAt: Date().addingTimeInterval(-900)
            )
        ]
    }
}

#endif
