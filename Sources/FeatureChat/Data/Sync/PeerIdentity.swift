//
//  PeerIdentity.swift
//  FeatureChat
//
//  Everything we know that identifies one person.
//

import Foundation

/// The set of identities that point at one person.
///
/// A peer is not identified by a single value, and assuming otherwise is what
/// leaves duplicates on screen. The two rows for one person are typically
/// identified *differently*: a conversation started on this device knows only a
/// phone number — and `upsertDirectPeerParticipant` used to store that phone in
/// the `user_id` column — while the row that came back from the server knows
/// only an account id. Comparing one value against one value, they never match.
///
/// So identity is a set, two peers are the same when the sets *overlap* on any
/// value, and a phone number found in the account-id column is filed as a phone
/// rather than taken at face value.
struct PeerIdentity: Equatable {

    private(set) var userIds: Set<String> = []
    private(set) var phones: Set<String> = []

    var isEmpty: Bool { userIds.isEmpty && phones.isEmpty }

    init(userId: String? = nil, phone: String? = nil) {
        add(userId: userId)
        add(phone: phone)
    }

    /// Files an account id — unless it is a phone number in disguise.
    mutating func add(userId: String?) {
        guard let raw = userId?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return
        }
        if let digits = Self.phoneDigits(raw) {
            phones.insert(digits)
            return
        }
        userIds.insert(raw.lowercased())
    }

    mutating func add(phone: String?) {
        guard let digits = Self.phoneDigits(phone) else { return }
        phones.insert(digits)
    }

    mutating func formUnion(_ other: PeerIdentity) {
        userIds.formUnion(other.userIds)
        phones.formUnion(other.phones)
    }

    /// Any shared value means the same person.
    func overlaps(_ other: PeerIdentity) -> Bool {
        !userIds.isDisjoint(with: other.userIds) || !phones.isDisjoint(with: other.phones)
    }

    /// The digits, when the value is shaped like a phone number.
    ///
    /// Bounded above as well as below: E.164 tops out at 15 digits, so a long
    /// run of digits is an identifier of some other kind and must not be
    /// mistaken for a number that would then match somebody.
    static func phoneDigits(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }

        let allowed = Set("+0123456789 -().")
        guard trimmed.allSatisfy({ allowed.contains($0) }) else { return nil }

        let digits = trimmed.onlyDigits
        return (6...15).contains(digits.count) ? digits : nil
    }
}

/// Groups things by the person they belong to, joining any two that share an
/// identity — including transitively, when a third row is what links them.
enum PeerGrouping {

    static func groups<T>(_ items: [T], identity: (T) -> PeerIdentity) -> [[T]] {
        var buckets: [(identity: PeerIdentity, items: [T])] = []

        for item in items {
            let itemIdentity = identity(item)
            guard !itemIdentity.isEmpty else {
                // Nothing identifies it, so nothing proves it is a duplicate.
                buckets.append((itemIdentity, [item]))
                continue
            }

            let matches = buckets.indices.filter { buckets[$0].identity.overlaps(itemIdentity) }

            guard let first = matches.first else {
                buckets.append((itemIdentity, [item]))
                continue
            }

            buckets[first].identity.formUnion(itemIdentity)
            buckets[first].items.append(item)

            // This row may be the link between buckets that looked unrelated —
            // one holding the phone, another the account id. Fold them together.
            for index in matches.dropFirst().reversed() {
                buckets[first].identity.formUnion(buckets[index].identity)
                buckets[first].items.append(contentsOf: buckets[index].items)
                buckets.remove(at: index)
            }
        }

        return buckets.map(\.items)
    }
}
