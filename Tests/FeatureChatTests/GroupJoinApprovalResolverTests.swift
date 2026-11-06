import XCTest
@testable import WaanguFeatureChat

final class GroupJoinApprovalResolverTests: XCTestCase {

    func test_returnsPermissionsApproveNewMembers_whenPermissionsExist() async {
        let permissions = GroupPermissions(approveNewMembers: true)
        let useCases = StubGroupPermissionsUseCases(permissions: permissions)

        let result = await GroupJoinApprovalResolver.isApprovalRequired(
            groupLocalId: "group-1",
            legacySettings: GroupSettings(approvalRequired: false),
            permissionsUseCases: useCases
        )
        XCTAssertTrue(result)
    }

    func test_fallsBackToLegacySettings_whenPermissionsUnavailable() async {
        let result = await GroupJoinApprovalResolver.isApprovalRequired(
            groupLocalId: "group-1",
            legacySettings: GroupSettings(approvalRequired: true),
            permissionsUseCases: nil
        )
        XCTAssertTrue(result)
    }

    func test_returnsFalse_whenNeitherPermissionsNorLegacyRequireApproval() async {
        let result = await GroupJoinApprovalResolver.isApprovalRequired(
            groupLocalId: "group-1",
            legacySettings: GroupSettings(approvalRequired: false),
            permissionsUseCases: nil
        )
        XCTAssertFalse(result)
    }
}

private final class StubGroupPermissionsUseCases: GroupPermissionsUseCasesProtocol {
    let permissions: GroupPermissions?

    init(permissions: GroupPermissions?) {
        self.permissions = permissions
    }

    var getPermissions: GetGroupPermissionsUseCaseProtocol {
        StubGetGroupPermissionsUseCase(permissions: permissions)
    }

    var updatePermissions: UpdateGroupPermissionsUseCaseProtocol {
        fatalError("not used in tests")
    }
}

private struct StubGetGroupPermissionsUseCase: GetGroupPermissionsUseCaseProtocol {
    let permissions: GroupPermissions?

    func execute(groupLocalId: String) async throws -> GroupPermissions? {
        permissions
    }
}
