//
//  Notification+Extension.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import Foundation

public extension Notification.Name {
    public static let messageDeleted = Notification.Name("messageDeleted")
    public static let callHistoryPersisted = Notification.Name("callHistoryPersisted")
    /// Posted when chat history or discussion metadata should be re-fetched (e.g. clear chat, settings).
    public  static let discussionsShouldRefresh = Notification.Name("discussionsShouldRefresh")
    /// Posted when a contact's block status changes
    public static let contactBlockStatusChanged = Notification.Name("contactBlockStatusChanged")
    /// Posted after a contact is created or edited on the device, so contact
    /// lists re-sync instead of showing the pre-edit name until relaunch.
    public static let contactsShouldRefresh = Notification.Name("contactsShouldRefresh")
}
