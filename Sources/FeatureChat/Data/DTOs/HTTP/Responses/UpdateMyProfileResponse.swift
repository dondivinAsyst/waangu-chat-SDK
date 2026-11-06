import Foundation

/// Reply to `PUT /identity/users/{id}`.
///
/// Every field is optional on purpose: the call is a write, and the only thing
/// the app needs from it is that it did not throw. Decoding must not be the
/// reason a successful update is reported as a failure, so the shape stays
/// tolerant of whatever identity chooses to echo back.
struct UpdateMyProfileResponse: Codable {
    let message: String?
    let status: Int?
    let data: UpdatedProfileData?
}

struct UpdatedProfileData: Codable {
    let id: String?
    let username: String?
    let avatar: String?
    let bio: String?
}
