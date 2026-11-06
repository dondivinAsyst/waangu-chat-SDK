//
//  GroupAdminRuleTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 3.2 — qui est administrateur d'un groupe, du point de vue de l'appareil.
//
//  L'appareil ne décide de rien (le serveur refuse l'action d'un non-administrateur, invariant
//  003) : cette règle ne fait que choisir quels boutons s'affichent. Ces tests fixent la règle
//  actuelle pour qu'un changement soit voulu.
//
//  Constat de l'étape : les rôles stockés ne changent que par les actions de l'utilisateur
//  lui-même (`GroupRepository`). Aucun événement du serveur ne les met à jour. Si un autre
//  administrateur me rétrograde ou me retire, cet appareil continue d'afficher mes boutons
//  d'administrateur. L'événement de membre et de rôle est dans le lot de contrat demandé à
//  Chat Core (membership, révocation).
//

import XCTest
@testable import WaanguFeatureChat

final class GroupAdminRuleTests: XCTestCase {

    private func member(_ userId: String, role: GroupRole, active: Bool = true) -> GroupMember {
        GroupMember(userId: userId, name: userId, phone: "+257000", role: role, isActive: active)
    }

    private func group(createdBy: String = "creator", members: [GroupMember]) -> GroupChat {
        GroupChat(name: "g", createdBy: createdBy, members: members)
    }

    func test_anActiveAdmin_isAdmin() {
        let g = group(members: [member("me", role: .ADMIN)])

        XCTAssertTrue(g.isCurrentUserAdmin(currentUserId: "me"))
    }

    func test_aMember_isNotAdmin() {
        let g = group(members: [member("me", role: .MEMBER)])

        XCTAssertFalse(g.isCurrentUserAdmin(currentUserId: "me"))
    }

    /// Une fois le rôle réécrit sur le groupe, les droits suivent : rétrogradé, plus administrateur.
    func test_whenTheStoredRoleBecomesMember_theAdminControlsGoAway() {
        var g = group(members: [member("me", role: .ADMIN)])
        XCTAssertTrue(g.isCurrentUserAdmin(currentUserId: "me"))

        g.members[0].role = .MEMBER

        XCTAssertFalse(g.isCurrentUserAdmin(currentUserId: "me"))
    }

    func test_aRemovedAdmin_isNotAdmin() {
        let g = group(members: [member("me", role: .ADMIN, active: false)])

        XCTAssertFalse(g.isCurrentUserAdmin(currentUserId: "me"))
    }

    func test_someoneElsesAdminRole_isNotMine() {
        let g = group(members: [member("other", role: .ADMIN), member("me", role: .MEMBER)])

        XCTAssertFalse(g.isCurrentUserAdmin(currentUserId: "me"))
    }

    func test_anUnknownCurrentUser_isNeverAdmin() {
        let g = group(createdBy: "", members: [member("", role: .ADMIN)])

        XCTAssertFalse(g.isCurrentUserAdmin(currentUserId: ""), "une session pas encore posée ne donne aucun droit")
    }

    /// Règle actuelle, à confirmer avec le serveur (la spec liste un rôle OWNER) : le créateur reste
    /// administrateur même si la liste des membres le montre comme simple membre ou sorti.
    func test_theCreator_staysAdmin_whateverTheMemberListSays() {
        let demoted = group(createdBy: "me", members: [member("me", role: .MEMBER)])
        let removed = group(createdBy: "me", members: [member("me", role: .MEMBER, active: false)])
        let absent = group(createdBy: "me", members: [])

        XCTAssertTrue(demoted.isCurrentUserAdmin(currentUserId: "me"))
        XCTAssertTrue(removed.isCurrentUserAdmin(currentUserId: "me"))
        XCTAssertTrue(absent.isCurrentUserAdmin(currentUserId: "me"))
    }
}
