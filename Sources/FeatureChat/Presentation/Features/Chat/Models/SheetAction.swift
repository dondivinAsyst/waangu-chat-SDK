//
//  SheetAction.swift
//  chatpreview
//
//  Created by Asyst on 7/5/25.
//

import Foundation
import SwiftUI

enum TabAction {
    case gallery, wallet, file, location, contact, poll, reply, unknown

    var label: String {
        switch self {
        case .gallery: return "Recents"
        case .wallet: return "Waangu Wallet"
        case .file: return "File"
        case .location: return "Location"
        case .contact: return "Contact"
        case .poll: return "Poll"
        case .reply: return "Reply"
        case .unknown: return "Title"
        }
    }
    

}
