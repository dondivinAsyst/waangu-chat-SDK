//
//  SettingsItem.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 8.01.2025.
//

import SwiftUI

struct SettingsItem {
    let imageName: String
    let imageColor: Color = .primary
    var imageType: ImageType = .systemImage
    let backgroundColor: Color
    let titleKey: String
    var isArrow: Bool = true
    
    enum ImageType {
        case systemImage, assetImage
    }
}

// MARK: Settings Data
extension SettingsItem {
    static let avatar = SettingsItem(
        imageName: "photo",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_CHANGE_PROFILE_PHOTO
    )
    
    /// Entrée vers la surface financière.
    ///
    /// Le hub n'était atteignable que depuis la feuille d'actions d'une
    /// conversation : sans fil ouvert, aucune de ces fonctions n'existait pour
    /// l'utilisateur. Les Réglages en font une destination de premier niveau.
    static let finance = SettingsItem(
        imageName: "creditcard",
        backgroundColor: .clear,
        titleKey: "settings_finance"
    )

    /// Mon QR code — à côté des Paiements, parce qu'un même code sert à payer
    /// et à se faire ajouter.
    static let myQRCode = SettingsItem(
        imageName: "qrcode",
        backgroundColor: .clear,
        titleKey: "settings_my_qr_code"
    )

    static let broadcastLists = SettingsItem(
        imageName: "megaphone",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_BROADCAST_LISTS
    )
    
    static let starredMessages = SettingsItem(
        imageName: "star",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_STARRED_MESSAGES
    )
    
    static let linkedDevices = SettingsItem(
        imageName: "laptopcomputer",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_LINKED_DEVICES
    )
    
    static let account = SettingsItem(
        imageName: "key",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_ACCOUNT
    )
    
    static let privacy = SettingsItem(
        imageName: "lock",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.PRIVACY_TITLE
    )
    
    static let chats = SettingsItem(
        imageName: "message",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_CHATS_MENU
    )
    
    static let notifications = SettingsItem(
        imageName: "bell.badge",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_NOTIFICATIONS
    )
    
    static let storage = SettingsItem(
        imageName: "arrow.up.arrow.down",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_STORAGE_DATA
    )

    static let appLanguage = SettingsItem(
        imageName: "globe",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_LANGUAGE_TITLE
    )
    
    static let help = SettingsItem(
        imageName: "info",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_HELP
    )
    
    static let tellFriend = SettingsItem(
        imageName: "heart",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_TELL_FRIEND
    )
    
    static let logout = SettingsItem(
        imageName: "door.right.hand.open",
        backgroundColor: .clear,
        titleKey: ChatTranslationKeys.SETTINGS_LOG_OUT
    )
}

// MARK: Contact Info Data
extension SettingsItem {
    static let media = SettingsItem(
        imageName: "photo",
        backgroundColor: .blue,
        titleKey: ChatTranslationKeys.CONTACT_INFO_MEDIA_LINKS_DOCS
    )
    
    static let mute = SettingsItem(
        imageName: "speaker.wave.2.fill",
        backgroundColor: .green,
        titleKey: ChatTranslationKeys.CONTACT_INFO_MUTE_NOTIFICATIONS
    )
    
    static let wallpaper = SettingsItem(
        imageName: "circles.hexagongrid",
        backgroundColor: .mint,
        titleKey: ChatTranslationKeys.SETTINGS_WALLPAPER_SOUND
    )
    
    static let saveToCameraRoll = SettingsItem(
        imageName: "square.and.arrow.down",
        backgroundColor: .yellow,
        titleKey: ChatTranslationKeys.GROUP_INFO_SAVE_TO_PHOTOS
    )
    
    static let encryption = SettingsItem(
        imageName: "lock.fill",
        backgroundColor: .blue,
        titleKey: ChatTranslationKeys.GROUP_INFO_ENCRYPTION
    )
    
    static let disappearingMessages = SettingsItem(
        imageName: "timer",
        backgroundColor: .blue,
        titleKey: ChatTranslationKeys.CONTACT_INFO_DISAPPEARING
    )
    
    static let lockChat = SettingsItem(
        imageName: "lock.doc.fill",
        backgroundColor: .blue,
        titleKey: ChatTranslationKeys.GROUP_INFO_LOCK_CHAT
    )
    
    static let contactDetails = SettingsItem(
        imageName: "person.circle",
        backgroundColor: .gray,
        titleKey: ChatTranslationKeys.SETTINGS_CONTACT_DETAILS
    )
}
