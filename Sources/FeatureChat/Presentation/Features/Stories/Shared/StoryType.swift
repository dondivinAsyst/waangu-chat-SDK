//import SwiftUI
//
//struct Viewer: Identifiable {
//    let id = UUID().uuidString
//    let username: String
//    let profileImage: String
//    let viewedAt: Date
//}
//
//
//struct Users : Identifiable {
//    let id = UUID().uuidString
//    let pictureUrl : String
//    let username : String
//    let createdAt : Date
//    var status : [Status]
//    
//}
//
//enum StatusType {
//    case image, text, video
//}
//
//
//
//struct StatusItems: Identifiable, Codable {
//    var id: String { _id ?? UUID().uuidString } // fallback if _id is nil
//    
//    var _id: String?
//    var userId: String?
//    var userImage: String?
//    var userName: String        // required
//    var type: String
//    var content: String         // required
//    var caption: String?
//    var thumbnail: String?
//    var background: String?
//    var fontText: String?
//    var fontWeight: String?
//    var seenUsers: [String]?
//    var unseenUsers: [String]?
//    var viewCount: Int?
//    var likeCount: Int?
//    var shareCount: Int?
//    var isActive: Bool?
//    var isPinned: Bool?
//    var createdAt: Date?
//    var expiresAt: Date?
//}
//
