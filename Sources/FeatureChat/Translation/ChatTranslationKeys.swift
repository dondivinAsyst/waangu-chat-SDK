//
//  ChatTranslationKeys.swift
//  FeatureChat
//

import Foundation

// MARK: - ChatTranslationKeys

public struct ChatTranslationKeys {

    // MARK: Module identifier
    public static let MODULE = "chat"
    public static let COMMON_MODULE = "common"

    // MARK: Membership events

    /// "%1$s a rejoint le groupe"  args: [actorName]
    public static let USER_JOINED             = "user_joined"
    /// "Vous avez rejoint le groupe"  args: none
    public static let USER_JOINED_YOU         = "user_joined_you"
    /// "%1$s a ajouté %2$s"  args: [actorName, targetName]
    public static let USER_ADDED_ACTOR        = "user_added_actor"
    /// "Vous avez ajouté %1$s"  args: [targetName]
    public static let USER_ADDED_YOU_ACTOR    = "user_added_you_actor"
    /// "%1$s vous a ajouté"  args: [actorName]
    public static let USER_ADDED_YOU_TARGET   = "user_added_you_target"
    /// "%1$s a quitté le groupe"  args: [actorName]
    public static let USER_LEFT               = "user_left"
    /// "Vous avez quitté le groupe"  args: none
    public static let USER_LEFT_YOU           = "user_left_you"
    /// "%1$s a retiré %2$s"  args: [actorName, targetName]
    public static let USER_REMOVED_ACTOR      = "user_removed_actor"
    /// "Vous avez retiré %1$s"  args: [targetName]
    public static let USER_REMOVED_YOU_ACTOR  = "user_removed_you_actor"
    /// "%1$s vous a retiré"  args: [actorName]
    public static let USER_REMOVED_YOU_TARGET = "user_removed_you_target"

    // MARK: Admin events

    /// "%1$s a promu %2$s en administrateur"  args: [actorName, targetName]
    public static let ADD_ADMIN_ACTOR          = "add_admin_actor"
    /// "Vous avez promu %1$s en administrateur"  args: [targetName]
    public static let ADD_ADMIN_YOU_ACTOR      = "add_admin_you_actor"
    /// "%1$s vous a promu en administrateur"  args: [actorName]
    public static let ADD_ADMIN_YOU_TARGET     = "add_admin_you_target"
    /// "%1$s a retiré les droits d'admin de %2$s"  args: [actorName, targetName]
    public static let REMOVE_ADMIN_ACTOR       = "remove_admin_actor"
    /// "Vous avez retiré les droits d'admin de %1$s"  args: [targetName]
    public static let REMOVE_ADMIN_YOU_ACTOR   = "remove_admin_you_actor"
    /// "%1$s vous a retiré les droits d'admin"  args: [actorName]
    public static let REMOVE_ADMIN_YOU_TARGET  = "remove_admin_you_target"

    // MARK: Group lifecycle

    /// "%1$s a créé le groupe"  args: [actorName]
    public static let GROUP_CREATED_ACTOR       = "group_created_actor"
    /// "Vous avez créé le groupe"  args: none
    public static let GROUP_CREATED_YOU         = "group_created_you"
    /// "%1$s a modifié le groupe"  args: [actorName]
    public static let GROUP_UPDATED_ACTOR       = "group_updated_actor"
    /// "Vous avez modifié le groupe"  args: none
    public static let GROUP_UPDATED_YOU         = "group_updated_you"
    /// "%1$s a changé le nom du groupe"  args: [actorName]
    public static let GROUP_NAME_CHANGED_ACTOR  = "group_name_changed_actor"
    /// "Vous avez changé le nom du groupe"  args: none
    public static let GROUP_NAME_CHANGED_YOU    = "group_name_changed_you"
    /// "%1$s a changé la photo du groupe"  args: [actorName]
    public static let GROUP_PIC_CHANGED_ACTOR   = "group_picture_changed_actor"
    /// "Vous avez changé la photo du groupe"  args: none
    public static let GROUP_PIC_CHANGED_YOU     = "group_picture_changed_you"

    // MARK: Security

    /// "Les messages sont chiffrés de bout en bout"  args: none
    public static let ENCRYPTION_ENABLED        = "encryption_enabled"

    // MARK: Disappearing messages

    /// "%1$s a activé les messages éphémères"  args: [actorName]
    public static let DISAPPEARING_ON_ACTOR     = "disappearing_on_actor"
    /// "Vous avez activé les messages éphémères"  args: none
    public static let DISAPPEARING_ON_YOU       = "disappearing_on_you"
    /// "%1$s a désactivé les messages éphémères"  args: [actorName]
    public static let DISAPPEARING_OFF_ACTOR    = "disappearing_off_actor"
    /// "Vous avez désactivé les messages éphémères"  args: none
    public static let DISAPPEARING_OFF_YOU      = "disappearing_off_you"

    // MARK: Real-time presence

    /// "%1$s est en train d'écrire..."  args: [userName]
    public static let TYPING_TEXT               = "typing_text"
    /// "%1$s enregistre un message vocal..."  args: [userName]
    public static let RECORDING_AUDIO           = "recording_audio"
    /// "en train d'écrire..."  args: none — direct chats, where the row title
    /// already names the person
    public static let TYPING_TEXT_DIRECT        = "typing_text_direct"
    /// "enregistre un message vocal..."  args: none — direct chats
    public static let RECORDING_AUDIO_DIRECT    = "recording_audio_direct"
    /// "%1$s personnes sont en train d'écrire..."  args: [count] — groups
    public static let TYPING_MULTIPLE           = "typing_multiple"

    // MARK: Contact actions

    /// "Vous avez supprimé ce message"  args: none
    public static let MESSAGE_DELETED_YOU       = "message_deleted_you"
    /// "Ce message a été supprimé"  args: none
    public static let MESSAGE_DELETED           = "message_deleted"
    /// "Vous avez bloqué %1$s"  args: [contactName]
    public static let CONTACT_BLOCKED_YOU       = "contact_blocked_you"
    /// "Vous avez débloqué %1$s"  args: [contactName]
    public static let CONTACT_UNBLOCKED_YOU     = "contact_unblocked_you"
    /// "Vous avez effacé les messages"  args: none
    public static let MESSAGES_CLEARED_YOU      = "messages_cleared_you"
    /// "Les messages ont été effacés"  args: none
    public static let MESSAGES_CLEARED          = "messages_cleared"
    /// "Conversation archivée"  args: none
    public static let CONVERSATION_ARCHIVED     = "conversation_archived"
    /// "Conversation désarchivée"  args: none
    public static let CONVERSATION_UNARCHIVED   = "conversation_unarchived"
    /// "%1$s a demandé à rejoindre"  args: [requesterName]
    public static let JOIN_REQUEST_RECEIVED     = "join_request_received"

    // MARK: Media type labels (used in chat list last-message preview)

    /// "Brouillon" — prefix shown before unsent composer text  args: none
    public static let DRAFT_LABEL               = "draft_label"
    /// "Photo"  args: none
    public static let MEDIA_TYPE_PHOTO          = "media_type_photo"
    /// "Vocal"  args: none
    public static let MEDIA_TYPE_VOICE          = "media_type_voice"
    /// "Vidéo"  args: none
    public static let MEDIA_TYPE_VIDEO          = "media_type_video"
    /// "Document"  args: none
    public static let MEDIA_TYPE_DOCUMENT       = "media_type_document"
    /// "Contact"  args: none
    public static let MEDIA_TYPE_CONTACT        = "media_type_contact"
    /// "Localisation"  args: none
    public static let MEDIA_TYPE_LOCATION       = "media_type_location"
    /// "Sondage"  args: none
    public static let MEDIA_TYPE_POLL           = "media_type_poll"
    /// Aperçu d'une opération financière dans la liste — "Paiement", "Demande d'argent"…
    public static let MEDIA_TYPE_PAYMENT        = "media_type_payment"
    public static let MEDIA_TYPE_MONEY_REQUEST  = "media_type_money_request"
    public static let MEDIA_TYPE_SPLIT_BILL     = "media_type_split_bill"
    public static let MEDIA_TYPE_BILL           = "media_type_bill"
    public static let MEDIA_TYPE_RECHARGE       = "media_type_recharge"
    public static let MEDIA_TYPE_REFUND         = "media_type_refund"
    public static let MEDIA_TYPE_DISPUTE        = "media_type_dispute"
    public static let MEDIA_TYPE_FX_QUOTE       = "media_type_fx_quote"

    // MARK: Call labels

    /// "Appel vocal"  args: none
    public static let CALL_AUDIO                = "call_audio"
    /// "Appel vidéo"  args: none
    public static let CALL_VIDEO                = "call_video"
    /// "Appel vocal manqué"  args: none
    public static let CALL_AUDIO_MISSED         = "call_audio_missed"
    /// "Appel vidéo manqué"  args: none
    public static let CALL_VIDEO_MISSED         = "call_video_missed"

    // MARK: Common UI actions (swipe/context menus)

    /// "Lire"  args: none
    public static let ACTION_MARK_READ          = "action_mark_read"
    /// "Épingler"  args: none
    public static let ACTION_PIN                = "action_pin"
    /// "Archiver"  args: none
    public static let ACTION_ARCHIVE            = "action_archive"
    /// "Désarchiver"  args: none
    public static let ACTION_UNARCHIVE          = "action_unarchive"
    /// "Plus"  args: none
    public static let ACTION_MORE               = "action_more"
    /// "Supprimer"  args: none
    public static let ACTION_DELETE             = "action_delete"

    // MARK: Message context menu actions

    /// "Répondre"  args: none
    public static let MENU_REPLY                = "menu_reply"
    /// "Transférer"  args: none
    public static let MENU_FORWARD              = "menu_forward"
    /// "Copier"  args: none
    public static let MENU_COPY                 = "menu_copy"
    /// "Modifier"  args: none
    public static let MENU_EDIT                 = "menu_edit"
    /// "Supprimer"  args: none
    public static let MENU_DELETE               = "menu_delete"

    // MARK: Chat list section / status labels

    /// "Modifié"  args: none
    public static let MESSAGE_EDITED            = "message_edited"
    /// "Transféré"  args: none
    public static let FORWARDED                 = "forwarded"
    /// "Archivées"  args: none
    public static let ARCHIVED_LABEL            = "archived_label"
    /// "Création des groupes"  args: none
    public static let CREATING_GROUPS_HEADER    = "creating_groups_header"
    /// "Vos messages sont chiffrés de bout en bout."  args: none
    public static let E2EE_BANNER               = "e2ee_banner"
    /// "Nouvelle tentative..."  args: none
    public static let GROUP_SYNC_RETRYING       = "group_sync_retrying"
    /// "Échec"  args: none
    public static let GROUP_SYNC_FAILED         = "group_sync_failed"
    /// "Création..."  args: none
    public static let GROUP_SYNC_CREATING       = "group_sync_creating"

    // MARK: Forwarding flow

    /// "Envoyer à" args: none
    public static let FORWARD_SEND_TO                  = "forward_send_to"
    /// "Rechercher" args: none
    public static let FORWARD_SEARCH_PLACEHOLDER       = "forward_search_placeholder"
    /// "Discussions récentes" args: none
    public static let FORWARD_SECTION_RECENT_CHATS     = "forward_section_recent_chats"
    /// "Autres contacts Waangu" args: none
    public static let FORWARD_SECTION_OTHER_CONTACTS   = "forward_section_other_contacts"
    /// "Chargement des contacts..." args: none
    public static let FORWARD_LOADING_CONTACTS         = "forward_loading_contacts"
    /// "Aucun contact disponible" args: none
    public static let FORWARD_EMPTY_TITLE              = "forward_empty_title"
    /// "Invitez des amis sur Waangu pour commencer à discuter" args: none
    public static let FORWARD_EMPTY_SUBTITLE           = "forward_empty_subtitle"
    /// "Mon statut" args: none
    public static let FORWARD_MY_STATUS                = "forward_my_status"
    /// "Aucune actualité" args: none
    public static let FORWARD_STATUS_EMPTY             = "forward_status_empty"
    /// "%1$s actualité(s)" args: [count]
    public static let FORWARD_STATUS_UPDATE_COUNT      = "forward_status_update_count"
    /// "Impossible d'ajouter à votre statut" args: none
    public static let FORWARD_STATUS_FAILED            = "forward_status_failed"
    /// "Groupe" args: none
    public static let FORWARD_GROUP                    = "forward_group"
    /// "%1$s et %2$s autres" args: [names, remaining count]
    public static let FORWARD_GROUP_MEMBERS_MORE       = "forward_group_members_more"
    /// "Utilisateur Waangu" args: none
    public static let FORWARD_WAANGU_USER              = "forward_waangu_user"
    /// "Ajouter un message..." args: none
    public static let FORWARD_ADD_MESSAGE_PLACEHOLDER  = "forward_add_message_placeholder"
    /// "Envoyer" args: none
    public static let FORWARD_SEND                     = "forward_send"
    /// "%1$s sélectionné(s)" args: [count]
    public static let FORWARD_SELECTED_COUNT           = "forward_selected_count"

    // MARK: Discussion lists

    /// "Aucune liste pour l'instant" args: none
    public static let DISCUSSION_LIST_EMPTY_TITLE      = "discussion_list_empty_title"
    /// "Appuyez sur + dans l'écran Discussions..." args: none
    public static let DISCUSSION_LIST_EMPTY_SUBTITLE   = "discussion_list_empty_subtitle"
    /// "Ajouter à une liste" args: none
    public static let DISCUSSION_LIST_ADD_TO_LIST      = "discussion_list_add_to_list"

    // MARK: Chat room actions

    /// "En ligne" args: none
    public static let CHAT_ONLINE                      = "chat_online"
    /// "Supprimer %1$s message(s) ?" args: [count]
    public static let CHAT_DELETE_SELECTION_TITLE      = "chat_delete_selection_title"
    /// "Supprimer pour moi" args: none
    public static let CHAT_DELETE_FOR_ME               = "chat_delete_for_me"
    /// "Supprimer pour tout le monde" args: none
    public static let CHAT_DELETE_FOR_EVERYONE         = "chat_delete_for_everyone"

    // MARK: Contact info

    public static let CONTACT_INFO_TITLE               = "contact_info_title"
    public static let CONTACT_INFO_MOBILE              = "contact_info_mobile"
    public static let CONTACT_INFO_MEDIA_LINKS_DOCS    = "contact_info_media_links_docs"
    public static let CONTACT_INFO_MUTE_NOTIFICATIONS  = "contact_info_mute_notifications"
    public static let CONTACT_INFO_CHAT_APPEARANCE     = "contact_info_chat_appearance"
    public static let CONTACT_INFO_DISAPPEARING        = "contact_info_disappearing"
    public static let CONTACT_INFO_SHARE_CONTACT       = "contact_info_share_contact"
    public static let CONTACT_INFO_CLEAR_CHAT_TITLE    = "contact_info_clear_chat_title"
    public static let CONTACT_INFO_CLEAR_CHAT_MESSAGE  = "contact_info_clear_chat_message"
    public static let CONTACT_INFO_CLEAR_CHAT_ACTION   = "contact_info_clear_chat_action"
    public static let CONTACT_INFO_BLOCK_TITLE         = "contact_info_block_title"
    public static let CONTACT_INFO_UNBLOCK_TITLE       = "contact_info_unblock_title"
    public static let CONTACT_INFO_BLOCK_MESSAGE       = "contact_info_block_message"
    public static let CONTACT_INFO_UNBLOCK_MESSAGE     = "contact_info_unblock_message"
    public static let CONTACT_INFO_BLOCK_ERROR         = "contact_info_block_error"
    public static let CONTACT_INFO_COULD_NOT_SAVE      = "contact_info_could_not_save"
    public static let CONTACT_INFO_AUDIO               = "contact_info_audio"
    public static let CONTACT_INFO_VIDEO               = "contact_info_video"
    public static let CONTACT_INFO_EDIT                = "contact_info_edit"

    // MARK: Group info

    public static let GROUP_INFO_ADD_PARTICIPANTS      = "group_info_add_participants"
    public static let GROUP_INFO_SEARCH                = "group_info_search"
    public static let GROUP_INFO_DISAPPEARING          = "group_info_disappearing"
    public static let GROUP_INFO_CHAT_APPEARANCE       = "group_info_chat_appearance"
    public static let GROUP_INFO_ERROR_TITLE           = "group_info_error_title"
    public static let GROUP_INFO_CLEAR_CHAT_TITLE      = "group_info_clear_chat_title"
    public static let GROUP_INFO_CLEAR_CHAT_MESSAGE    = "group_info_clear_chat_message"
    public static let GROUP_INFO_CLEAR_CHAT_ACTION     = "group_info_clear_chat_action"
    public static let GROUP_INFO_MEDIA_LINKS_DOCS      = "group_info_media_links_docs"
    public static let GROUP_INFO_ADD_PARTICIPANT       = "group_info_add_participant"
    public static let GROUP_INFO_INVITE_VIA_LINK       = "group_info_invite_via_link"
    public static let GROUP_INFO_ADMINS                = "group_info_admins"
    public static let GROUP_INFO_PARTICIPANT_COUNT     = "group_info_participant_count"
    public static let GROUP_INFO_ADMIN_BADGE           = "group_info_admin_badge"
    public static let GROUP_INFO_MAKE_ADMIN            = "group_info_make_admin"
    public static let GROUP_INFO_DISMISS_ADMIN         = "group_info_dismiss_admin"
    public static let GROUP_INFO_REMOVE_FROM_GROUP     = "group_info_remove_from_group"
    public static let GROUP_INFO_MUTE_NOTIFICATIONS    = "group_info_mute_notifications"
    public static let GROUP_INFO_STARRED               = "group_info_starred"
    public static let GROUP_INFO_NONE                  = "group_info_none"
    public static let GROUP_INFO_SAVE_TO_PHOTOS        = "group_info_save_to_photos"
    public static let GROUP_INFO_LOCK_CHAT             = "group_info_lock_chat"
    public static let GROUP_INFO_ADVANCED_PRIVACY      = "group_info_advanced_privacy"
    public static let GROUP_INFO_ENCRYPTION            = "group_info_encryption"
    public static let GROUP_INFO_ENCRYPTION_SUBTITLE   = "group_info_encryption_subtitle"
    public static let GROUP_INFO_ADD_TO_COMMUNITY      = "group_info_add_to_community"
    public static let GROUP_INFO_CREATE_SIMILAR_GROUP  = "group_info_create_similar_group"
    public static let GROUP_INFO_COMMUNITY_SOON        = "group_info_community_soon"
    public static let GROUP_INFO_SIMILAR_GROUP_SOON    = "group_info_similar_group_soon"
    public static let GROUP_INFO_PENDING_JOIN_REQUESTS = "group_info_pending_join_requests"
    public static let GROUP_INFO_WAITING_APPROVAL      = "group_info_waiting_approval"
    public static let GROUP_INFO_REVIEW_REQUESTS       = "group_info_review_requests"
    public static let GROUP_INFO_PERMISSIONS           = "group_info_permissions"
    public static let GROUP_INFO_MANAGE_PERMISSIONS    = "group_info_manage_permissions"
    public static let GROUP_INFO_VIEW_PERMISSIONS      = "group_info_view_permissions"
    public static let GROUP_INFO_DELETE_GROUP          = "group_info_delete_group"
    public static let GROUP_INFO_CLEAR_CHAT            = "group_info_clear_chat"
    public static let GROUP_INFO_EXIT_GROUP            = "group_info_exit_group"
    public static let GROUP_INFO_DELETE_CONVERSATION   = "group_info_delete_conversation"
    public static let GROUP_INFO_MEMBER_DM_SOON        = "group_info_member_dm_soon"
    public static let GROUP_INFO_MEMBER_AUDIO_SOON     = "group_info_member_audio_soon"
    public static let GROUP_INFO_MEMBER_VIDEO_SOON     = "group_info_member_video_soon"
    public static let GROUP_INFO_MEMBER_PROFILE_SOON   = "group_info_member_profile_soon"
    public static let GROUP_INFO_AUDIO_SOON            = "group_info_audio_soon"
    public static let GROUP_INFO_VIDEO_SOON            = "group_info_video_soon"
    public static let GROUP_INFO_COULD_NOT_CLEAR_CHAT  = "group_info_could_not_clear_chat"
    public static let GROUP_INFO_COULD_NOT_SAVE        = "group_info_could_not_save"
    public static let GROUP_INFO_ACTION_UNAVAILABLE    = "group_info_action_unavailable"
    public static let GROUP_INFO_DELETION_FAILED       = "group_info_deletion_failed"
    public static let GROUP_INFO_TITLE                 = "group_info_title"
    public static let GROUP_INFO_ADDING_PARTICIPANTS   = "group_info_adding_participants"
    public static let GROUP_INFO_DEFAULT_STATUS        = "group_info_default_status"
    public static let GROUP_INFO_ADD_PARTICIPANTS_TITLE = "group_info_add_participants_title"
    public static let GROUP_INFO_ADD_ACTION            = "group_info_add_action"
    public static let GROUP_INFO_SEARCH_CONTACTS       = "group_info_search_contacts"
    public static let GROUP_INFO_EDIT_TITLE            = "group_info_edit_title"
    public static let GROUP_INFO_GROUP_NAME            = "group_info_group_name"
    public static let GROUP_INFO_GROUP_DESCRIPTION     = "group_info_group_description"
    public static let GROUP_INFO_INVITE_LINK_LOADING   = "group_info_invite_link_loading"
    public static let GROUP_INFO_INVITE_LINK_SECTION   = "group_info_invite_link_section"
    public static let GROUP_INFO_COPY_LINK             = "group_info_copy_link"
    public static let GROUP_INFO_SHARE_LINK            = "group_info_share_link"
    public static let GROUP_INFO_RESET_LINK            = "group_info_reset_link"
    public static let GROUP_INFO_QR_SECTION            = "group_info_qr_section"
    public static let GROUP_INFO_NO_INVITE_LINK        = "group_info_no_invite_link"
    public static let GROUP_INFO_GENERATE_INVITE_DESC  = "group_info_generate_invite_desc"
    public static let GROUP_INFO_GENERATE_INVITE       = "group_info_generate_invite"
    public static let GROUP_INFO_INVITE_VIA_LINK_TITLE = "group_info_invite_via_link_title"
    public static let GROUP_INFO_GROUP_ADMINS_TITLE    = "group_info_group_admins_title"
    public static let GROUP_INFO_ADMIN                 = "group_info_admin"
    public static let GROUP_INFO_SEARCH_MEMBERS        = "group_info_search_members"
    public static let GROUP_INFO_SEARCH_MEMBERS_TITLE  = "group_info_search_members_title"
    public static let GROUP_INFO_MEMBER_ACTIONS_TITLE  = "group_info_member_actions_title"
    public static let GROUP_INFO_MESSAGE               = "group_info_message"
    public static let GROUP_INFO_CLOSE                 = "group_info_close"
    public static let GROUP_INFO_REMOVE_PHOTO          = "group_info_remove_photo"
    public static let GROUP_INFO_SAVING                = "group_info_saving"
    public static let GROUP_INFO_UPDATE_FAILED         = "group_info_update_failed"
    public static let GROUP_INFO_AVATAR_UPLOAD_FAILED  = "group_info_avatar_upload_failed"
    public static let GROUP_INFO_AVATAR_UPLOAD_FAILED_REASON = "group_info_avatar_upload_failed_reason"
    public static let GROUP_INFO_UPDATING_ROLE         = "group_info_updating_role"
    public static let GROUP_INFO_REMOVING_MEMBER       = "group_info_removing_member"
    public static let GROUP_INFO_ADDING_PARTICIPANT    = "group_info_adding_participant"
    public static let GROUP_INFO_LEAVING_GROUP         = "group_info_leaving_group"
    public static let GROUP_INFO_DELETING              = "group_info_deleting"
    public static let GROUP_INFO_CLEARING_MESSAGES     = "group_info_clearing_messages"
    public static let GROUP_INFO_PROMOTE_FAILED        = "group_info_promote_failed"
    public static let GROUP_INFO_DEMOTE_FAILED         = "group_info_demote_failed"
    public static let GROUP_INFO_REMOVE_MEMBER_FAILED  = "group_info_remove_member_failed"
    public static let GROUP_INFO_ADD_MEMBERS_FAILED    = "group_info_add_members_failed"
    public static let GROUP_INFO_SETTINGS_FAILED       = "group_info_settings_failed"
    public static let GROUP_INFO_ELIGIBILITY_FAILED    = "group_info_eligibility_failed"

    // MARK: Deletion dialog

    public static let DELETION_EXIT_GROUP              = "deletion_exit_group"
    public static let DELETION_DELETE                  = "deletion_delete"
    public static let DELETION_LEAVE_GROUP             = "deletion_leave_group"
    public static let DELETION_CLEAR_MESSAGES          = "deletion_clear_messages"
    public static let DELETION_DELETE_FOR_ME           = "deletion_delete_for_me"
    public static let DELETION_EXIT                    = "deletion_exit"
    public static let DELETION_EXIT_DELETE_FOR_ME      = "deletion_exit_delete_for_me"

    // MARK: Group join requests

    public static let JOIN_REQUESTS_LOADING            = "join_requests_loading"
    public static let JOIN_REQUESTS_TITLE              = "join_requests_title"
    public static let JOIN_REQUESTS_EMPTY_TITLE        = "join_requests_empty_title"
    public static let JOIN_REQUESTS_EMPTY_SUBTITLE     = "join_requests_empty_subtitle"
    public static let JOIN_REQUESTS_DECLINE            = "join_requests_decline"
    public static let JOIN_REQUESTS_ACCEPT             = "join_requests_accept"

    // MARK: Chat room state bars

    public static let CHAT_LEFT_GROUP_READONLY         = "chat_left_group_readonly"
    public static let CHAT_BLOCKED_CONTACT             = "chat_blocked_contact"
    public static let CHAT_UNBLOCK                     = "chat_unblock"
    public static let CHAT_DELETE_CHAT                 = "chat_delete_chat"

    // MARK: Search / group intro / reply / permissions / communities

    public static let CHAT_SEARCH_MESSAGES             = "chat_search_messages"
    public static let CHAT_SEARCH_MESSAGES_DESC        = "chat_search_messages_desc"
    public static let CHAT_SEARCH_NO_RESULTS           = "chat_search_no_results"
    public static let CHAT_SEARCH_TRY_ANOTHER          = "chat_search_try_another"
    public static let CHAT_SEARCH_TITLE                = "chat_search_title"
    public static let CHAT_SEARCH_IN_CONVERSATION      = "chat_search_in_conversation"
    public static let GROUP_INTRO_CREATED_YOU          = "group_intro_created_you"
    public static let GROUP_INTRO_CREATED_OTHER        = "group_intro_created_other"
    public static let GROUP_INTRO_MEMBERS              = "group_intro_members"
    public static let GROUP_INTRO_ADD_DESCRIPTION      = "group_intro_add_description"
    public static let GROUP_INTRO_ADD_MEMBERS          = "group_intro_add_members"
    public static let PERMISSIONS_LOADING              = "permissions_loading"
    public static let PERMISSIONS_SHARE_HISTORY        = "permissions_share_history"
    public static let PERMISSIONS_SHARE_HISTORY_DESC   = "permissions_share_history_desc"
    public static let PERMISSIONS_ENABLED              = "permissions_enabled"
    public static let PERMISSIONS_DISABLED             = "permissions_disabled"
    public static let PERMISSIONS_GROUP_NOT_SYNCED     = "permissions_group_not_synced"
    public static let PERMISSIONS_UPDATE_FAILED        = "permissions_update_failed"
    public static let COMMUNITIES_EMPTY_TITLE          = "communities_empty_title"
    public static let COMMUNITIES_EMPTY_SUBTITLE       = "communities_empty_subtitle"
    public static let COMMUNITIES_TITLE                = "communities_title"
    public static let COMMUNITIES_NEW                  = "communities_new"

    // Communities — structure, membership, administration
    public static let COMMUNITIES_LOADING              = "communities_loading"
    public static let COMMUNITIES_RETRY                = "communities_retry"
    public static let COMMUNITIES_CREATE_TITLE         = "communities_create_title"
    public static let COMMUNITIES_NAME                 = "communities_name"
    public static let COMMUNITIES_DESCRIPTION          = "communities_description"
    public static let COMMUNITIES_PRIVATE              = "communities_private"
    public static let COMMUNITIES_PRIVATE_DESC         = "communities_private_desc"
    public static let COMMUNITIES_CREATE               = "communities_create"
    public static let COMMUNITIES_CREATE_GROUPS        = "communities_create_groups"
    public static let COMMUNITIES_NEW_GROUP            = "communities_new_group"
    public static let COMMUNITIES_GROUP_NAME           = "communities_group_name"
    public static let COMMUNITIES_JOIN_WITH_CODE       = "communities_join_with_code"
    public static let COMMUNITIES_INVITE_CODE          = "communities_invite_code"
    public static let COMMUNITIES_JOIN                 = "communities_join"
    public static let COMMUNITIES_ANNOUNCEMENTS        = "communities_announcements"
    public static let COMMUNITIES_GROUPS               = "communities_groups"
    public static let COMMUNITIES_NO_GROUPS            = "communities_no_groups"
    public static let COMMUNITIES_MEMBERS              = "communities_members"
    public static let COMMUNITIES_MEMBER_COUNT         = "communities_member_count"
    public static let COMMUNITIES_NO_MEMBERS           = "communities_no_members"
    public static let COMMUNITIES_LEAVE                = "communities_leave"
    public static let COMMUNITIES_DELETE               = "communities_delete"
    public static let COMMUNITIES_CONVERSATION_PENDING = "communities_conversation_pending"
    public static let COMMUNITIES_ROLE_OWNER           = "communities_role_owner"
    public static let COMMUNITIES_ROLE_ADMIN           = "communities_role_admin"
    public static let COMMUNITIES_ROLE_MODERATOR       = "communities_role_moderator"
    public static let COMMUNITIES_ROLE_MEMBER          = "communities_role_member"
    public static let COMMUNITIES_MAKE_ADMIN           = "communities_make_admin"
    public static let COMMUNITIES_MAKE_MEMBER          = "communities_make_member"
    public static let COMMUNITIES_REMOVE_MEMBER        = "communities_remove_member"
    public static let COMMUNITIES_TRANSFER_OWNER       = "communities_transfer_owner"
    public static let COMMUNITIES_DETACH_GROUP         = "communities_detach_group"
    public static let COMMUNITIES_ADMIN_ONLY_POST      = "communities_admin_only_post"

    // Channels — canaux Updates
    public static let CHANNELS_TITLE                   = "channels_title"
    public static let CHANNELS_NEW                     = "channels_new"
    public static let CHANNELS_CREATE                  = "channels_create"
    public static let CHANNELS_NAME                    = "channels_name"
    public static let CHANNELS_EXPLORE                 = "channels_explore"
    public static let CHANNELS_FOLLOW                  = "channels_follow"
    public static let CHANNELS_FOLLOWING               = "channels_following"
    public static let CHANNELS_UNFOLLOW                = "channels_unfollow"
    public static let CHANNELS_FOLLOWER_COUNT          = "channels_follower_count"
    public static let CHANNELS_OPEN                    = "channels_open"
    public static let CHANNELS_NOT_READY               = "channels_not_ready"
    public static let CHANNELS_READ_ONLY               = "channels_read_only"
    public static let CHANNELS_NONE_FOLLOWED           = "channels_none_followed"
    public static let CHANNELS_NO_POSTS_YET            = "channels_no_posts_yet"
    public static let CHANNELS_FIND_TO_FOLLOW          = "channels_find_to_follow"
    public static let CHANNELS_INTRO_TITLE             = "channels_intro_title"
    public static let CHANNELS_INTRO_UPDATES           = "channels_intro_updates"
    public static let CHANNELS_INTRO_UPDATES_DESC      = "channels_intro_updates_desc"
    public static let CHANNELS_INTRO_DISCOVER          = "channels_intro_discover"
    public static let CHANNELS_INTRO_DISCOVER_DESC     = "channels_intro_discover_desc"
    public static let CHANNELS_INTRO_PRIVACY           = "channels_intro_privacy"
    public static let CHANNELS_INTRO_PRIVACY_DESC      = "channels_intro_privacy_desc"
    public static let CHANNELS_INTRO_AGREE             = "channels_intro_agree"
    public static let CHANNELS_CREATE_INTRO_TITLE      = "channels_create_intro_title"
    public static let CHANNELS_CREATE_INTRO_PUBLIC     = "channels_create_intro_public"
    public static let CHANNELS_CREATE_INTRO_PUBLIC_DESC = "channels_create_intro_public_desc"
    public static let CHANNELS_CREATE_INTRO_HIDDEN     = "channels_create_intro_hidden"
    public static let CHANNELS_CREATE_INTRO_HIDDEN_DESC = "channels_create_intro_hidden_desc"
    public static let CHANNELS_CREATE_INTRO_RESPONSIBLE = "channels_create_intro_responsible"
    public static let CHANNELS_CREATE_INTRO_RESPONSIBLE_DESC = "channels_create_intro_responsible_desc"
    public static let CHANNELS_CONTINUE                = "channels_continue"
    public static let COMMUNITIES_INTRO_TITLE          = "communities_intro_title"
    public static let COMMUNITIES_INTRO_BODY           = "communities_intro_body"
    public static let COMMUNITIES_INTRO_GROUPS         = "communities_intro_groups"
    public static let COMMUNITIES_INTRO_GROUPS_DESC    = "communities_intro_groups_desc"
    public static let COMMUNITIES_INTRO_ANNOUNCE       = "communities_intro_announce"
    public static let COMMUNITIES_INTRO_ANNOUNCE_DESC  = "communities_intro_announce_desc"
    public static let COMMUNITIES_INTRO_MEMBERS        = "communities_intro_members"
    public static let COMMUNITIES_INTRO_MEMBERS_DESC   = "communities_intro_members_desc"
    public static let COMMUNITIES_GET_STARTED          = "communities_get_started"
    public static let COMMUNITIES_SEE_ALL              = "communities_see_all"
    public static let COMMUNITIES_ADD_PHOTO            = "communities_add_photo"
    public static let COMMUNITIES_ADD_GROUP            = "communities_add_group"
    public static let COMMUNITIES_MANAGE_GROUPS        = "communities_manage_groups"
    public static let COMMUNITIES_CREATE_NEW_GROUP     = "communities_create_new_group"
    public static let COMMUNITIES_ADD_EXISTING_GROUP   = "communities_add_existing_group"
    public static let COMMUNITIES_YOUR_GROUPS          = "communities_your_groups"
    public static let COMMUNITIES_NO_LINKABLE_GROUPS   = "communities_no_linkable_groups"
    public static let COMMUNITIES_GROUPS_YOURE_IN      = "communities_groups_youre_in"
    public static let COMMUNITIES_OTHER_GROUPS         = "communities_other_groups"
    public static let COMMUNITIES_OTHER_GROUPS_HINT    = "communities_other_groups_hint"
    public static let COMMUNITIES_INFO                 = "communities_info"
    public static let COMMUNITIES_INVITE_MEMBERS       = "communities_invite_members"
    public static let COMMUNITIES_INVITE_SHARE_TEXT    = "communities_invite_share_text"
    public static let COMMUNITIES_SUBTITLE             = "communities_subtitle"
    public static let COMMUNITIES_GROUP_COUNT          = "communities_group_count"
    public static let COMMUNITIES_DESCRIPTION_HINT     = "communities_description_hint"
    public static let CHANNELS_ADD_PHOTO               = "channels_add_photo"
    public static let CHANNELS_DISMISS_SUGGESTION     = "channels_dismiss_suggestion"
    public static let CHANNELS_YOURS                  = "channels_yours"
    public static let CHANNELS_INFO                   = "channels_info"
    public static let CHANNELS_POST_PLACEHOLDER       = "channels_post_placeholder"
    public static let CHANNELS_ONLY_OWNER_POSTS       = "channels_only_owner_posts"
    public static let CHANNELS_POST_EDITED            = "channels_post_edited"
    public static let CHANNELS_FORWARD_POST           = "channels_forward_post"
    public static let CHANNELS_MUTED                  = "channels_muted"
    public static let CHANNELS_PUBLIC_TITLE           = "channels_public_title"
    public static let CHANNELS_PUBLIC_DESC            = "channels_public_desc"
    public static let CHANNELS_PRIVACY_TITLE          = "channels_privacy_title"
    public static let CHANNELS_PRIVACY_DESC           = "channels_privacy_desc"
    public static let CHANNELS_EDIT                   = "channels_edit"
    public static let CHANNELS_EDIT_TITLE             = "channels_edit_title"
    public static let CHANNELS_SAVE                   = "channels_save"
    public static let CHANNELS_SYSTEM_PUBLIC_NOTICE   = "channels_system_public_notice"
    public static let CHANNELS_SYSTEM_CREATED         = "channels_system_created"
    public static let CHANNELS_START_GROWING          = "channels_start_growing"
    public static let CHANNELS_ADD_DESCRIPTION        = "channels_add_description"
    public static let CHANNELS_SHARE_TO_STATUS        = "channels_share_to_status"
    public static let CHANNELS_SHARE_CHANNEL          = "channels_share_channel"
    public static let CHANNELS_POLL_NEEDS_OPTIONS     = "channels_poll_needs_options"
    public static let CHANNELS_SEARCH_POSTS           = "channels_search_posts"
    public static let CHANNELS_DESCRIPTION_HINT       = "channels_description_hint"
    public static let CHANNELS_ADMINS                 = "channels_admins"
    public static let CHANNELS_INVITE_ADMINS          = "channels_invite_admins"
    public static let CHANNELS_NO_ADMINS              = "channels_no_admins"
    public static let CHANNELS_NO_FOLLOWERS_FOR_ADMIN = "channels_no_followers_for_admin"
    public static let CHANNELS_NO_FOLLOWERS_FOR_ADMIN_DESC = "channels_no_followers_for_admin_desc"
    
    // MARK: Channel Invitations
    
    /// "Invite" — section header in Channel Detail
    public static let CHANNELS_INVITE                 = "channels_invite"
    /// "Invite Contacts" — button to send DM invites
    public static let CHANNELS_INVITE_CONTACTS        = "channels_invite_contacts"
    /// "Invite Link" — button title in Channel Detail
    public static let CHANNELS_INVITE_LINK            = "channels_invite_link"
    /// "Share this channel via link or WhatsApp" — button subtitle
    public static let CHANNELS_INVITE_LINK_DESC       = "channels_invite_link_desc"
    /// "Anyone with this link can subscribe to your channel" — section footer
    public static let CHANNELS_INVITE_LINK_FOOTER     = "channels_invite_link_footer"
    
    // Channel Invite Link Sheet
    /// "Active Link" — status badge
    public static let CHANNELS_LINK_STATUS_ACTIVE     = "channels_link_status_active"
    /// "Expired" — status text
    public static let CHANNELS_LINK_STATUS_EXPIRED    = "channels_link_status_expired"
    /// "Max Uses Reached" — status text
    public static let CHANNELS_LINK_STATUS_MAX_USES   = "channels_link_status_max_uses"
    /// "Inactive" — status text
    public static let CHANNELS_LINK_STATUS_INACTIVE   = "channels_link_status_inactive"
    /// "Copy Link" — button
    public static let CHANNELS_LINK_COPY              = "channels_link_copy"
    /// "Link copied to clipboard" — success message
    public static let CHANNELS_LINK_COPIED            = "channels_link_copied"
    /// "Share Link" — button
    public static let CHANNELS_LINK_SHARE             = "channels_link_share"
    /// "Regenerate Link" — button
    public static let CHANNELS_LINK_REGENERATE        = "channels_link_regenerate"
    /// "Revoke Link" — button
    public static let CHANNELS_LINK_REVOKE            = "channels_link_revoke"
    /// "Revoke this link?" — confirmation title
    public static let CHANNELS_LINK_REVOKE_TITLE      = "channels_link_revoke_title"
    /// "The current link will stop working. You can generate a new one." — confirmation message
    public static let CHANNELS_LINK_REVOKE_MESSAGE    = "channels_link_revoke_message"
    /// "Generate Invite Link" — button when no link exists
    public static let CHANNELS_LINK_GENERATE          = "channels_link_generate"
    /// "No Active Link" — title when inactive
    public static let CHANNELS_LINK_NO_ACTIVE         = "channels_link_no_active"
    /// "This link has been revoked or expired" — subtitle
    public static let CHANNELS_LINK_INACTIVE_DESC     = "channels_link_inactive_desc"
    /// "Create a shareable link" — onboarding title
    public static let CHANNELS_LINK_ONBOARDING_TITLE  = "channels_link_onboarding_title"
    /// "Grow your channel with invite links" — onboarding subtitle
    public static let CHANNELS_LINK_ONBOARDING_SUBTITLE = "channels_link_onboarding_subtitle"
    /// "Shareable anywhere" — feature title
    public static let CHANNELS_LINK_FEATURE_SHAREABLE = "channels_link_feature_shareable"
    /// "WhatsApp, SMS, Email, Social" — feature subtitle
    public static let CHANNELS_LINK_FEATURE_SHAREABLE_DESC = "channels_link_feature_shareable_desc"
    /// "Easy Discovery" — feature title
    public static let CHANNELS_LINK_FEATURE_DISCOVERY = "channels_link_feature_discovery"
    /// "No need for phone numbers" — feature subtitle
    public static let CHANNELS_LINK_FEATURE_DISCOVERY_DESC = "channels_link_feature_discovery_desc"
    /// "Usage" — stats label
    public static let CHANNELS_LINK_USAGE             = "channels_link_usage"
    /// "Expiration" — stats label
    public static let CHANNELS_LINK_EXPIRATION        = "channels_link_expiration"
    /// "Created" — stats label
    public static let CHANNELS_LINK_CREATED           = "channels_link_created"
    /// "%1$s / %2$s uses" — args: [used, total]
    public static let CHANNELS_LINK_USAGE_LIMITED     = "channels_link_usage_limited"
    /// "%1$s uses" — args: [count] (unlimited)
    public static let CHANNELS_LINK_USAGE_UNLIMITED   = "channels_link_usage_unlimited"
    /// "Expires in %1$s" — args: [duration]
    public static let CHANNELS_LINK_EXPIRES_IN        = "channels_link_expires_in"
    /// "Never expires" — expiration text
    public static let CHANNELS_LINK_NEVER_EXPIRES     = "channels_link_never_expires"
    
    // Channel Join Preview Sheet
    /// "Channel Invite" — navigation title
    public static let CHANNELS_JOIN_TITLE             = "channels_join_title"
    /// "Loading channel..." — loading state
    public static let CHANNELS_JOIN_LOADING           = "channels_join_loading"
    /// "Join Channel" — button
    public static let CHANNELS_JOIN_BUTTON            = "channels_join_button"
    /// "Joining..." — button state during join
    public static let CHANNELS_JOIN_JOINING           = "channels_join_joining"
    /// "Open Channel" — button after successful join
    public static let CHANNELS_JOIN_OPEN              = "channels_join_open"
    /// "Welcome to the Channel!" — success title
    public static let CHANNELS_JOIN_SUCCESS_TITLE     = "channels_join_success_title"
    /// "You're now subscribed and will receive updates" — success message
    public static let CHANNELS_JOIN_SUCCESS_MESSAGE   = "channels_join_success_message"
    /// "You're Already a Member" — already subscribed title
    public static let CHANNELS_JOIN_ALREADY_TITLE     = "channels_join_already_title"
    /// "You're subscribed to this channel" — already subscribed message
    public static let CHANNELS_JOIN_ALREADY_MESSAGE   = "channels_join_already_message"
    /// "Unable to Load Channel" — error title
    public static let CHANNELS_JOIN_ERROR_TITLE       = "channels_join_error_title"
    /// "Try Again" — error retry button
    public static let CHANNELS_JOIN_RETRY             = "channels_join_retry"
    /// "Get Notified" — benefit title
    public static let CHANNELS_JOIN_BENEFIT_NOTIFY    = "channels_join_benefit_notify"
    /// "Receive channel updates" — benefit description
    public static let CHANNELS_JOIN_BENEFIT_NOTIFY_DESC = "channels_join_benefit_notify_desc"
    /// "View Content" — benefit title
    public static let CHANNELS_JOIN_BENEFIT_CONTENT   = "channels_join_benefit_content"
    /// "Access all channel posts" — benefit description
    public static let CHANNELS_JOIN_BENEFIT_CONTENT_DESC = "channels_join_benefit_content_desc"
    /// "Curated Content" — benefit title (verified channels)
    public static let CHANNELS_JOIN_BENEFIT_VERIFIED  = "channels_join_benefit_verified"
    /// "Content from verified admins" — benefit description
    public static let CHANNELS_JOIN_BENEFIT_VERIFIED_DESC = "channels_join_benefit_verified_desc"
    /// "%1$s subscribers" — formatted count, args: [count]
    public static let CHANNELS_JOIN_SUBSCRIBER_COUNT  = "channels_join_subscriber_count"
    
    // Channel Invite Contact Picker
    /// "Invite to Channel" — sheet title
    public static let CHANNELS_INVITE_PICKER_TITLE    = "channels_invite_picker_title"
    /// "Search contacts..." — search placeholder
    public static let CHANNELS_INVITE_SEARCH          = "channels_invite_search"
    /// "Send %1$s invite(s)" — button, args: [count]
    public static let CHANNELS_INVITE_SEND_COUNT      = "channels_invite_send_count"
    /// "Sending invites..." — loading state
    public static let CHANNELS_INVITE_SENDING         = "channels_invite_sending"
    /// "Invites sent!" — success message
    public static let CHANNELS_INVITE_SENT            = "channels_invite_sent"
    /// "Failed to send invites" — error message
    public static let CHANNELS_INVITE_FAILED          = "channels_invite_failed"
    /// "Select contacts to invite" — empty state
    public static let CHANNELS_INVITE_EMPTY           = "channels_invite_empty"
    
    // Channel Invite Bubble
    /// "invited you to a channel" — message preview text
    public static let CHANNELS_INVITE_BUBBLE_TEXT     = "channels_invite_bubble_text"
    /// "View Channel" — button in bubble
    public static let CHANNELS_INVITE_BUBBLE_VIEW     = "channels_invite_bubble_view"
    /// "Channel Invitation" — bubble header
    public static let CHANNELS_INVITE_BUBBLE_HEADER   = "channels_invite_bubble_header"
    public static let COMMUNITIES_SETTINGS            = "communities_settings"
    public static let COMMUNITIES_WHO_ADDS_MEMBERS    = "communities_who_adds_members"
    public static let COMMUNITIES_WHO_ADDS_GROUPS     = "communities_who_adds_groups"
    public static let COMMUNITIES_EVERYONE            = "communities_everyone"
    public static let COMMUNITIES_ADMINS_ONLY         = "communities_admins_only"
    public static let COMMUNITIES_JOIN_GROUP          = "communities_join_group"
    public static let CHANNELS_LOADING                 = "channels_loading"

    /// Generic cancel, shared by the communities and channels forms.
    public static let CHAT_CANCEL                      = "chat_cancel"

    // Read-only rooms
    public static let CHAT_BROADCAST_READONLY          = "chat_broadcast_readonly"
    public static let CHAT_ANNOUNCEMENTS_READONLY      = "chat_announcements_readonly"

    // MARK: New chat / share

    public static let NEW_CHAT_IOS_REQUIRED            = "new_chat_ios_required"
    public static let NEW_CHAT_SEARCH_PLACEHOLDER      = "new_chat_search_placeholder"
    public static let NEW_CHAT_TITLE                   = "new_chat_title"
    public static let NEW_CHAT_CONTACTS_ON_WAANGU      = "new_chat_contacts_on_waangu"
    public static let NEW_CHAT_INVITE_ON_WAANGU        = "new_chat_invite_on_waangu"
    public static let NEW_CHAT_INVITE                  = "new_chat_invite"
    public static let NEW_CHAT_OPTION_GROUP            = "new_chat_option_group"
    public static let NEW_CHAT_OPTION_CONTACT          = "new_chat_option_contact"
    public static let NEW_CHAT_OPTION_COMMUNITY        = "new_chat_option_community"
    public static let GROUP_PICKER_ADD_PARTICIPANTS    = "group_picker_add_participants"
    public static let GROUP_PICKER_SELECTED_COUNT      = "group_picker_selected_count"
    public static let GROUP_PICKER_NEXT                = "group_picker_next"
    public static let SHARE_SEARCH_PLACEHOLDER         = "share_search_placeholder"
    public static let SHARE_TITLE                      = "share_title"
    public static let SHARE_RECENT                     = "share_recent"
    public static let SHARE_RECENT_TODO                = "share_recent_todo"
    public static let SHARE_CONTACTS_ON_WAANGU         = "share_contacts_on_waangu"

    // MARK: Remaining chat helpers

    public static let CREATE_GROUP_TITLE               = "create_group_title"
    public static let CREATE_GROUP_NAME                = "create_group_name"
    public static let CREATE_GROUP_DESCRIPTION         = "create_group_description"
    public static let CREATE_GROUP_SEARCH_CONTACTS     = "create_group_search_contacts"
    public static let CREATE_GROUP_MEMBERS_SELECTED    = "create_group_members_selected"
    public static let NEW_GROUP_PARTICIPANTS           = "new_group_participants"
    public static let NEW_GROUP_SETTINGS               = "new_group_settings"
    public static let NEW_GROUP_PERMISSIONS            = "new_group_permissions"
    public static let NEW_GROUP_PERMISSIONS_DESC       = "new_group_permissions_desc"
    public static let NEW_GROUP_NAME                   = "new_group_name"
    public static let NEW_GROUP_CREATE                 = "new_group_create"
    public static let GROUP_PERMS_ONLY_ADMINS_SEND     = "group_perms_only_admins_send"
    public static let GROUP_PERMS_ONLY_ADMINS_SEND_DESC = "group_perms_only_admins_send_desc"
    public static let GROUP_PERMS_ONLY_ADMINS_EDIT     = "group_perms_only_admins_edit"
    public static let GROUP_PERMS_ONLY_ADMINS_EDIT_DESC = "group_perms_only_admins_edit_desc"
    public static let GROUP_PERMS_ONLY_ADMINS_ADD      = "group_perms_only_admins_add"
    public static let GROUP_PERMS_ONLY_ADMINS_ADD_DESC = "group_perms_only_admins_add_desc"
    public static let GROUP_PERMS_APPROVE_NEW          = "group_perms_approve_new"
    public static let GROUP_PERMS_APPROVE_NEW_DESC     = "group_perms_approve_new_desc"
    public static let GROUP_PERMS_SECTION_TITLE        = "group_perms_section_title"
    public static let GROUP_PERMS_SECTION_DESC         = "group_perms_section_desc"
    public static let GROUP_PERMS_MEDIA_SHARING        = "group_perms_media_sharing"
    public static let GROUP_PERMS_MEDIA_SHARING_DESC   = "group_perms_media_sharing_desc"
    public static let GROUP_PERMS_MEDIA_SETTINGS       = "group_perms_media_settings"
    public static let GROUP_PERMS_SEND_MESSAGES        = "group_perms_send_messages"
    public static let GROUP_PERMS_SEND_MESSAGES_DESC   = "group_perms_send_messages_desc"
    public static let GROUP_PERMS_ADD_MEMBERS          = "group_perms_add_members"
    public static let GROUP_PERMS_ADD_MEMBERS_DESC     = "group_perms_add_members_desc"
    public static let GROUP_PERMS_INVITE_LINK          = "group_perms_invite_link"
    public static let GROUP_PERMS_INVITE_LINK_DESC     = "group_perms_invite_link_desc"
    public static let GROUP_PERMS_EDIT_GROUP_INFO      = "group_perms_edit_group_info"
    public static let GROUP_PERMS_EDIT_GROUP_INFO_DESC = "group_perms_edit_group_info_desc"
    public static let GROUP_PERMS_APPROVE_NEW_MEMBERS  = "group_perms_approve_new_members"
    public static let GROUP_PERMS_APPROVE_NEW_MEMBERS_DESC = "group_perms_approve_new_members_desc"
    public static let GROUP_PERMS_ONLY_ADMINS_POST     = "group_perms_only_admins_post"
    public static let GROUP_PERMS_ONLY_ADMINS_POST_DESC = "group_perms_only_admins_post_desc"
    public static let GROUP_PERMS_WHO_CAN_MODIFY       = "group_perms_who_can_modify"
    public static let GROUP_PERMS_ALL_PARTICIPANTS     = "group_perms_all_participants"
    public static let GROUP_PERMS_ONLY_ADMINS          = "group_perms_only_admins"
    public static let CONTACT_BUBBLE_MESSAGE           = "contact_bubble_message"
    public static let CONTACT_BUBBLE_SHARED_CONTACTS   = "contact_bubble_shared_contacts"
    public static let CONTACT_BUBBLE_VIEW_ALL          = "contact_bubble_view_all"
    public static let CONTACT_BUBBLE_CALL              = "contact_bubble_call"
    public static let CONTACT_BUBBLE_ADD_CONTACT       = "contact_bubble_add_contact"
    public static let CONTACT_BUBBLE_OTHER_CONTACTS    = "contact_bubble_other_contacts"
    public static let REPLY_MEDIA_COUNT                = "reply_media_count"
    public static let REPLY_AUDIO                      = "reply_audio"
    public static let REPLY_PHOTO                      = "reply_photo"
    public static let REPLY_VIDEO                      = "reply_video"
    public static let REPLY_STATUS                     = "reply_status"
    public static let REPLY_VOICE_MESSAGE              = "reply_voice_message"
    public static let REPLY_VOICE_CALL                 = "reply_voice_call"
    public static let REPLY_VIDEO_CALL                 = "reply_video_call"
    public static let REPLY_MISSED_VOICE_CALL          = "reply_missed_voice_call"
    public static let REPLY_MISSED_VIDEO_CALL          = "reply_missed_video_call"
    public static let REPLY_DOCUMENT                   = "reply_document"
    public static let REPLY_CONTACT                    = "reply_contact"
    public static let REPLY_LOCATION                   = "reply_location"
    public static let REPLY_POLL                       = "reply_poll"
    public static let REPLY_PAYMENT                    = "reply_payment"
    public static let REPLY_GROUP_CREATED              = "reply_group_created"
    public static let REPLY_CHANNEL_INVITE             = "reply_channel_invite"
    public static let REPLY_FALLBACK_MESSAGE           = "reply_fallback_message"
    public static let MESSAGE_SEARCH_TITLE             = "message_search_title"
    public static let MESSAGE_SEARCH_PLACEHOLDER       = "message_search_placeholder"
    public static let LOCATION_OPEN_TITLE              = "location_open_title"
    public static let LOCATION_OPEN_APPLE_MAPS         = "location_open_apple_maps"
    public static let LOCATION_OPEN_GOOGLE_MAPS        = "location_open_google_maps"
    public static let LOCATION_DIRECTIONS              = "location_directions"
    public static let LOCATION_OPEN_IN_MAPS            = "location_open_in_maps"
    public static let LOCATION_APPLE_MAPS              = "location_apple_maps"
    public static let LOCATION_GOOGLE_MAPS             = "location_google_maps"
    public static let LOCATION_GET_DIRECTIONS          = "location_get_directions"
    public static let LOCATION_SCREEN_TITLE            = "location_screen_title"
    public static let LOCATION_SEARCH                  = "location_search"
    public static let LOCATION_SEARCH_NEARBY           = "location_search_nearby"
    public static let LOCATION_PLACES_IN_AREA          = "location_places_in_area"
    public static let LOCATION_LIVE_SHARE_PROMPT       = "location_live_share_prompt"
    public static let LOCATION_FOR_15_MIN              = "location_for_15_min"
    public static let LOCATION_FOR_1_HOUR              = "location_for_1_hour"
    public static let LOCATION_FOR_8_HOURS             = "location_for_8_hours"
    public static let LOCATION_UNTIL_TURNED_OFF        = "location_until_turned_off"
    public static let LOCATION_NO_PLACES               = "location_no_places"
    public static let LOCATION_NO_PLACES_QUERY         = "location_no_places_query"
    public static let LOCATION_LIVE_BADGE              = "location_live_badge"
    public static let LOCATION_LIVE_ENDED              = "location_live_ended"
    public static let LOCATION_LIVE_STOP               = "location_live_stop"
    public static let CONTACT_PICKER_SEARCH_BY_NAME    = "contact_picker_search_by_name"
    public static let CONTACT_PICKER_TITLE             = "contact_picker_title"
    public static let CONTACT_PICKER_CLOSE             = "contact_picker_close"
    public static let CONTACT_PICKER_SEND              = "contact_picker_send"
    public static let NEW_CONTACT_FIRST_NAME           = "new_contact_first_name"
    public static let NEW_CONTACT_LAST_NAME            = "new_contact_last_name"
    public static let NEW_CONTACT_PHONE                = "new_contact_phone"
    public static let NEW_CONTACT_NOT_ON_WAANGU        = "new_contact_not_on_waangu"
    public static let NEW_CONTACT_INVITE_TO_WAANGU     = "new_contact_invite_to_waangu"
    public static let NEW_CONTACT_SYNC_TO_PHONE        = "new_contact_sync_to_phone"
    public static let NEW_CONTACT_EDIT_TITLE           = "new_contact_edit_title"
    public static let NEW_CONTACT_CREATE_TITLE         = "new_contact_create_title"
    public static let NEW_CONTACT_SAVE_ERROR           = "new_contact_save_error"
    public static let NEW_CONTACT_SAVED_TO_PHONE_NOTE = "new_contact_saved_to_phone_note"
    public static let NEW_CONTACT_SELECT_COUNTRY       = "new_contact_select_country"
    public static let CHAT_LIST_MESSAGES               = "chat_list_messages"
    public static let CHAT_LIST_TITLE                  = "chat_list_title"
    public static let CHAT_LIST_NEW_LIST               = "chat_list_new_list"
    public static let CHAT_LIST_LIST_NAME              = "chat_list_list_name"
    public static let CHAT_LIST_CREATE_LIST_DESC       = "chat_list_create_list_desc"
    public static let CHAT_LIST_DELETE_LIST_TITLE      = "chat_list_delete_list_title"
    public static let CHAT_LIST_DELETE_LIST_MESSAGE    = "chat_list_delete_list_message"
    public static let CHAT_LIST_DELETION_FAILED        = "chat_list_deletion_failed"
    public static let ARCHIVE_EDIT                     = "archive_edit"
    public static let FILTER_ADD_LIST                  = "filter_add_list"
    public static let FILTER_ALL                       = "filter_all"
    public static let FILTER_UNREAD                    = "filter_unread"
    public static let FILTER_FAVORITES                 = "filter_favorites"
    public static let FILTER_GROUPS                    = "filter_groups"
    public static let CHAT_LIST_SEARCH_PLACEHOLDER     = "chat_list_search_placeholder"
    public static let CHAT_LIST_SEARCH_IN_LIST         = "chat_list_search_in_list"
    public static let CHAT_LIST_EMPTY_FILTER           = "chat_list_empty_filter"
    public static let CHAT_LIST_DELETED_LIST           = "chat_list_deleted_list"
    public static let CHAT_LIST_ADDED_TO_LIST          = "chat_list_added_to_list"
    public static let CHAT_LIST_REMOVED_FROM_LIST      = "chat_list_removed_from_list"
    public static let SHARED_MEDIA_TITLE               = "shared_media_title"
    public static let SHARED_MEDIA_TAB_MEDIA           = "shared_media_tab_media"
    public static let SHARED_MEDIA_TAB_DOCS            = "shared_media_tab_docs"
    public static let SHARED_MEDIA_TAB_LINKS           = "shared_media_tab_links"
    public static let SHARED_MEDIA_EMPTY_MEDIA         = "shared_media_empty_media"
    public static let SHARED_MEDIA_EMPTY_DOCS          = "shared_media_empty_docs"
    public static let SHARED_MEDIA_EMPTY_LINKS         = "shared_media_empty_links"
    public static let GALLERY_EDIT                     = "gallery_edit"
    public static let GALLERY_MEDIA                    = "gallery_media"
    public static let GALLERY_LINKS                    = "gallery_links"
    public static let GALLERY_DOCS                     = "gallery_docs"
    public static let GALLERY_DELETE_FOR_ME            = "gallery_delete_for_me"
    public static let GALLERY_DELETE_FOR_ME_AND_USER   = "gallery_delete_for_me_and_user"
    public static let GALLERY_CHOOSE_ACTION            = "gallery_choose_action"
    public static let GALLERY_NO_LINKS                 = "gallery_no_links"
    public static let GALLERY_NO_DOCS                  = "gallery_no_docs"
    public static let GALLERY_DOCUMENT                 = "gallery_document"
    public static let GALLERY_MEDIA_COUNT              = "gallery_media_count"
    public static let GALLERY_VIDEO_UNAVAILABLE        = "gallery_video_unavailable"
    public static let POST_LEAVE_TITLE                 = "post_leave_title"
    public static let POST_LEAVE_KEEP_CHAT             = "post_leave_keep_chat"
    public static let POST_LEAVE_DELETE_FOR_ME         = "post_leave_delete_for_me"
    public static let SHARE_PROCESSING                 = "share_processing"
    public static let SHARE_FAILED_TITLE               = "share_failed_title"
    public static let SHARE_TRY_AGAIN                  = "share_try_again"
    public static let SHARE_SUCCESS_TITLE              = "share_success_title"
    public static let SHARE_SUCCESS_MESSAGE            = "share_success_message"
    public static let SETTINGS_LANGUAGE_FOOTER         = "settings_language_footer"
    public static let SETTINGS_LANGUAGE_TITLE          = "settings_language_title"
    public static let GROUP_LEFT_NOTICE                = "group_left_notice"
    public static let GROUP_PARTICIPANTS_COUNT         = "group_participants_count"
    public static let GROUP_EDIT_INFO                  = "group_edit_info"
    public static let FILE_SELECT_FROM_FILES           = "file_select_from_files"
    public static let FILE_SELECTED_FILES              = "file_selected_files"
    public static let FILE_RECENTLY_SENT               = "file_recently_sent"
    public static let FILE_EMPTY                       = "file_empty"
    public static let FILE_DOCUMENT                    = "file_document"
    public static let FILE_PREVIEW_TITLE               = "file_preview_title"
    public static let FILE_ADD_CAPTION                 = "file_add_caption"
    public static let FILE_PAGES                       = "file_pages"
    public static let SHEET_MEDIA                      = "sheet_media"
    public static let SHEET_WAANGU                     = "sheet_waangu"
    public static let SHEET_FILE                       = "sheet_file"
    public static let SHEET_LOCATION                   = "sheet_location"
    public static let SHEET_CONTACT                    = "sheet_contact"
    public static let SHEET_REPLY                      = "sheet_reply"
    public static let SHEET_POLL                       = "sheet_poll"

    // Sondages
    public static let POLL_CREATE_TITLE                = "poll_create_title"
    public static let POLL_QUESTION_PLACEHOLDER        = "poll_question_placeholder"
    public static let POLL_OPTION_PLACEHOLDER          = "poll_option_placeholder"
    public static let POLL_ADD_OPTION                  = "poll_add_option"
    public static let POLL_SEND                        = "poll_send"
    public static let POLL_VOTES_COUNT                 = "poll_votes_count"
    public static let POLL_SECTION_QUESTION            = "poll_section_question"
    public static let POLL_SECTION_OPTIONS             = "poll_section_options"
    public static let POLL_ALLOW_MULTIPLE              = "poll_allow_multiple"
    public static let POLL_SELECT_ONE_OR_MORE          = "poll_select_one_or_more"
    public static let POLL_VIEW_VOTES                  = "poll_view_votes"
    public static let POLL_VOTES_TITLE                 = "poll_votes_title"
    public static let POLL_VOTER_YOU                   = "poll_voter_you"
    /// "%1$s votes" — the tally on one option in the votes list.
    public static let POLL_VOTES_FOR_OPTION            = "poll_votes_for_option"
    public static let GALLERY_CLOSE                    = "gallery_close"
    public static let GALLERY_ALL_PHOTOS               = "gallery_all_photos"
    public static let GALLERY_ALL_MEDIA                = "gallery_all_media"
    public static let GALLERY_VIDEO_BADGE              = "gallery_video_badge"
    public static let CONTACT_INFO_NAV_TITLE           = "contact_info_nav_title"
    public static let CONTACT_INFO_CLOSE               = "contact_info_close"
    public static let CONTACT_INFO_INVITE_TO_WAANGU    = "contact_info_invite_to_waangu"
    public static let CONTACT_INFO_CREATE_NEW          = "contact_info_create_new"
    public static let CONTACT_INFO_ADD_TO_EXISTING     = "contact_info_add_to_existing"
    public static let CONTACT_INFO_INVITE_MESSAGE      = "contact_info_invite_message"
    public static let CONTACT_INFO_ADDED_TO_CONTACT    = "contact_info_added_to_contact"
    public static let CONTACT_INFO_ADD_FAILED          = "contact_info_add_failed"
    public static let PRIVACY_EVERYONE                 = "privacy_everyone"
    public static let PRIVACY_MY_CONTACTS              = "privacy_my_contacts"
    public static let PRIVACY_NOBODY                   = "privacy_nobody"
    public static let PRIVACY_LAST_SEEN                = "privacy_last_seen"
    public static let PRIVACY_PROFILE_PHOTO            = "privacy_profile_photo"
    public static let PRIVACY_ABOUT                    = "privacy_about"
    public static let PRIVACY_PERSONAL_INFO_HEADER     = "privacy_personal_info_header"
    public static let PRIVACY_READ_RECEIPTS            = "privacy_read_receipts"
    public static let PRIVACY_READ_RECEIPTS_FOOTER     = "privacy_read_receipts_footer"
    public static let PRIVACY_GROUPS                   = "privacy_groups"
    public static let PRIVACY_GROUPS_HEADER            = "privacy_groups_header"
    public static let PRIVACY_BLOCKED_CONTACTS         = "privacy_blocked_contacts"
    public static let PRIVACY_TITLE                    = "privacy_title"
    public static let PRIVACY_NO_BLOCKED               = "privacy_no_blocked"
    public static let PRIVACY_BLOCKED_TITLE            = "privacy_blocked_title"
    public static let MEDIA_WIFI                       = "media_wifi"
    public static let MEDIA_MOBILE_DATA                = "media_mobile_data"
    public static let MEDIA_ROAMING                    = "media_roaming"
    public static let MEDIA_PHOTOS                     = "media_photos"
    public static let MEDIA_AUDIO                      = "media_audio"
    public static let MEDIA_VIDEO                      = "media_video"
    public static let MEDIA_DOCUMENTS                  = "media_documents"
    public static let MEDIA_RESET_DEFAULTS             = "media_reset_defaults"
    public static let MEDIA_AUTO_DOWNLOAD_TITLE        = "media_auto_download_title"
    public static let SETTINGS_TITLE                   = "settings_title"
    public static let SETTINGS_BACK_TO_WAANGU          = "settings_back_to_waangu"
    public static let SETTINGS_RETURN_TO_APP           = "settings_return_to_app"
    public static let SETTINGS_UPDATE_PROFILE          = "settings_update_profile"
    public static let SETTINGS_USERNAME                = "settings_username"
    public static let SETTINGS_BIO                     = "settings_bio"
    public static let SETTINGS_UPDATE                  = "settings_update"
    public static let SETTINGS_UPDATE_PROFILE_DESC     = "settings_update_profile_desc"
    public static let SETTINGS_SIGN_OUT_CONFIRM        = "settings_sign_out_confirm"
    public static let SETTINGS_SIGN_OUT                = "settings_sign_out"
    public static let SETTINGS_UPLOADING               = "settings_uploading"
    public static let SETTINGS_PROFILE_UPDATED         = "settings_profile_updated"

    // MARK: Profile
    public static let PROFILE_TITLE                    = "profile_title"
    public static let PROFILE_CHANGE_PHOTO             = "profile_change_photo"
    public static let PROFILE_NAME_FOOTER              = "profile_name_footer"
    public static let PROFILE_SAVE_FAILED              = "profile_save_failed"
    public static let PROFILE_PHOTO_LOAD_FAILED        = "profile_photo_load_failed"
    public static let PROFILE_SAVED_LOCALLY_ONLY       = "profile_saved_locally_only"
    public static let AUTH_INITIALIZING_CHAT           = "auth_initializing_chat"
    public static let AUTH_VERIFYING_SESSION           = "auth_verifying_session"
    public static let AUTH_START_FAILED_TITLE          = "auth_start_failed_title"
    public static let AUTH_START_FAILED_NETWORK        = "auth_start_failed_network"
    public static let AUTH_START_FAILED_SESSION        = "auth_start_failed_session"
    public static let AUTH_RETRY_COUNTDOWN             = "auth_retry_countdown"
    public static let CALLS_RECENT                     = "calls_recent"
    public static let CALLS_TITLE                      = "calls_title"
    public static let CALLS_NO_MISSED                  = "calls_no_missed"
    public static let CALLS_NO_RECENT                  = "calls_no_recent"
    public static let CALLS_EMPTY_SUBTITLE             = "calls_empty_subtitle"
    public static let CALLS_CREATE_LINK                = "calls_create_link"
    public static let CALLS_CREATE_LINK_DESC           = "calls_create_link_desc"
    public static let CALLS_NEW_TITLE                  = "calls_new_title"
    public static let CALLS_SEARCH_CONTACTS            = "calls_search_contacts"
    public static let CALLS_CONTACTS_ON_WAANGU         = "calls_contacts_on_waangu"
    public static let CALLS_INVITE_TO_WAANGU           = "calls_invite_to_waangu"
    public static let CALLS_NO_CONTACTS                = "calls_no_contacts"
    public static let CALLS_INVITE                     = "calls_invite"
    public static let CALLS_CALL_HISTORY               = "calls_call_history"
    public static let CALLS_VIDEO_CALL                 = "calls_video_call"
    public static let CALLS_AUDIO_CALL                 = "calls_audio_call"
    public static let CALLS_E2EE                       = "calls_e2ee"
    public static let CALLS_REMIND_ME                  = "calls_remind_me"
    public static let CALLS_MESSAGE                    = "calls_message"
    public static let CALLS_DECLINE                    = "calls_decline"
    public static let CALLS_ACCEPT                     = "calls_accept"
    public static let CALLS_SLIDE_TO_ANSWER            = "calls_slide_to_answer"
    /// Offer sent, far end not alerting yet.
    public static let CALLS_CALLING                    = "calls_calling"
    /// The callee's device is actually ringing.
    public static let CALLS_RINGING                    = "calls_ringing"
    public static let CALLS_SPEAKER                    = "calls_speaker"
    public static let CALLS_VIDEO                      = "calls_video"
    public static let CALLS_MUTE                       = "calls_mute"
    public static let CALLS_ADD                        = "calls_add"
    public static let CALLS_YOU                        = "calls_you"
    public static let CALLS_ENDED                      = "calls_ended"
    // How a call finished, when "ended" alone would leave the user guessing.
    public static let CALLS_FAILED                     = "calls_failed"
    public static let CALLS_NO_ANSWER                  = "calls_no_answer"
    public static let CALLS_DECLINED                   = "calls_declined"
    public static let CALLS_BUSY                       = "calls_busy"
    public static let CALLS_CONNECTED                  = "calls_connected"
    public static let CALLS_RECONNECTING               = "calls_reconnecting"
    // Actions offered when a call did not connect.
    public static let CALLS_CANCEL                     = "calls_cancel"
    public static let CALLS_CALL_AGAIN                 = "calls_call_again"
    public static let CALLS_RECORD_VOICE_MESSAGE       = "calls_record_voice_message"
    // Redialling a past call from its bubble.
    public static let CALLS_VOICE                      = "calls_voice"
    public static let CALLS_PARTICIPANT_COUNT          = "calls_participant_count"
    /// Header of a group call — the tiles carry the names, so the title does not.
    public static let CALLS_GROUP_CALL                 = "calls_group_call"
    /// A peer we can name from neither contacts, the wire, nor a phone number.
    public static let CALLS_UNKNOWN                    = "calls_unknown"
    // Group calls.
    public static let CALLS_AND_OTHERS                 = "calls_and_others"
    public static let CALLS_NEW_GROUP_CALL             = "calls_new_group_call"
    public static let CALLS_SELECTED_COUNT             = "calls_selected_count"
    // How a finished call reads in the conversation thread. `%1$s` is the call
    // kind ("Voice call" / "Video call").
    public static let CALLS_BUBBLE_FAILED              = "calls_bubble_failed"
    public static let CALLS_BUBBLE_DECLINED            = "calls_bubble_declined"
    public static let CALLS_BUBBLE_BUSY                = "calls_bubble_busy"
    public static let CALLS_BUBBLE_NO_ANSWER           = "calls_bubble_no_answer"
    public static let CALLS_BUBBLE_CANCELLED           = "calls_bubble_cancelled"
    public static let CALLS_BUBBLE_MISSED              = "calls_bubble_missed"
    public static let CALLS_SHARE                      = "calls_share"
    public static let CALLS_MORE                       = "calls_more"
    public static let CALLS_END                        = "calls_end"
    public static let CALLS_CONNECTING                 = "calls_connecting"
    public static let CALLS_FLIP_CAMERA                = "calls_flip_camera"
    public static let CALLS_EFFECTS                    = "calls_effects"
    public static let CALLS_MORE_TITLE                 = "calls_more_title"
    public static let CALLS_TAP_TO_RETURN              = "calls_tap_to_return"
    public static let CALLS_ADD_PARTICIPANT            = "calls_add_participant"
    public static let CALLS_ADD_PARTICIPANT_DESC       = "calls_add_participant_desc"
    public static let CALLS_ADD_PARTICIPANT_TITLE      = "calls_add_participant_title"
    public static let CALLS_PARTICIPANTS_SELECTED      = "calls_participants_selected"
    public static let CALLS_AUDIO_OUTPUT               = "calls_audio_output"
    public static let CALLS_AUDIO_OUTPUT_DESC          = "calls_audio_output_desc"
    public static let CALLS_SWITCH_TO_VIDEO            = "calls_switch_to_video"
    public static let CALLS_TURN_OFF_VIDEO             = "calls_turn_off_video"
    public static let CALLS_SHARE_SCREEN               = "calls_share_screen"
    public static let CALLS_SHARE_SCREEN_DESC          = "calls_share_screen_desc"
    public static let CALLS_STOP_SHARING               = "calls_stop_sharing"
    // Conference features (CALL-INTEGRATION V3 §16)
    public static let CALLS_REACTIONS                  = "calls_reactions"
    public static let CALLS_RAISE_HAND                 = "calls_raise_hand"
    public static let CALLS_LOWER_HAND                 = "calls_lower_hand"
    public static let CALLS_RAISED_HANDS               = "calls_raised_hands"
    public static let CALLS_ACKNOWLEDGE                = "calls_acknowledge"

    public static let CALLS_SHARE_SCREEN_TITLE         = "calls_share_screen_title"
    public static let CALLS_SHARE_SCREEN_MESSAGE       = "calls_share_screen_message"
    public static let CALLS_SHARE_SCREEN_ACTION        = "calls_share_screen_action"
    public static let CALLS_SWITCH_VIDEO_TITLE         = "calls_switch_video_title"
    public static let CALLS_SWITCH_VIDEO_MESSAGE       = "calls_switch_video_message"
    public static let CALLS_SWITCH_VIDEO_ACTION        = "calls_switch_video_action"
    public static let CALLS_SHARE_SCREEN_FAILED        = "calls_share_screen_failed"
    public static let CALLS_SHARE_SCREEN_BUSY          = "calls_share_screen_busy"
    public static let CALLS_SHARE_SCREEN_UNAVAILABLE   = "calls_share_screen_unavailable"
    public static let STORIES_UPDATES_TITLE            = "stories_updates_title"
    public static let STORIES_RECENT_UPDATES           = "stories_recent_updates"
    public static let STORIES_CHANNELS                 = "stories_channels"
    public static let STORIES_STATUS_HEADER            = "stories_status_header"
    public static let STORIES_STATUS_PRIVACY           = "stories_status_privacy"
    public static let STORIES_MY_STATUS                = "stories_my_status"
    public static let STORIES_ADD_TO_STATUS            = "stories_add_to_status"
    public static let STORIES_CHANNELS_DESC            = "stories_channels_desc"
    public static let STORIES_EXPLORE_MORE             = "stories_explore_more"
    public static let STORIES_CHANNEL_NAME             = "stories_channel_name"
    public static let STORIES_FOLLOW                   = "stories_follow"
    public static let STORIES_ONE_HOUR_AGO             = "stories_one_hour_ago"
    public static let STORIES_STATUS_PRIVACY_TITLE     = "stories_status_privacy_title"
    public static let STORIES_MY_CONTACTS              = "stories_my_contacts"
    public static let STORIES_MY_CONTACTS_EXCEPT       = "stories_my_contacts_except"
    public static let STORIES_ONLY_SHARE_WITH          = "stories_only_share_with"
    public static let STORIES_EXCLUDED_COUNT           = "stories_excluded_count"
    public static let STORIES_INCLUDED_COUNT           = "stories_included_count"
    public static let STORIES_ALLOW_SHARING            = "stories_allow_sharing"
    public static let STORIES_ALLOW_SHARING_DESC       = "stories_allow_sharing_desc"
    public static let STORIES_SEARCH_PLACEHOLDER       = "stories_search_placeholder"
    public static let STORIES_SELECTED_COUNT           = "stories_selected_count"
    public static let STORIES_SHARE_WITH               = "stories_share_with"
    public static let STORIES_EXCLUDE_FROM             = "stories_exclude_from"
    public static let STORIES_DONE                     = "stories_done"
    public static let STORIES_EDIT                     = "stories_edit"
    public static let STORIES_VIEWS                    = "stories_views"
    public static let STORIES_SENDING                  = "stories_sending"
    public static let STORIES_FAILED_SEND              = "stories_failed_send"
    public static let STORIES_SENT                     = "stories_sent"
    public static let STORIES_MESSAGE_SENT             = "stories_message_sent"
    public static let STORIES_TAP_RETRY                = "stories_tap_retry"
    public static let STORIES_PLEASE_WAIT              = "stories_please_wait"
    public static let STORIES_ADD_STATUS               = "stories_add_status"
    public static let STORIES_TEXT                     = "stories_text"
    public static let STORIES_CAMERA                   = "stories_camera"
    public static let STORIES_STATUS_TITLE             = "stories_status_title"
    public static let STORIES_EXPLORE                  = "stories_explore"
    public static let STORIES_NO_CHANNELS              = "stories_no_channels"
    public static let STORIES_NO_CHANNELS_DESC         = "stories_no_channels_desc"
    public static let STORIES_SEARCH                   = "stories_search"
    public static let STORIES_SYNCING                  = "stories_syncing"
    public static let STORIES_FAILED                   = "stories_failed"
    public static let STORIES_DELETING                 = "stories_deleting"
    public static let STORIES_DELETE_FAILED_TITLE      = "stories_delete_failed_title"
    public static let STORIES_DELETE_FAILED_MESSAGE    = "stories_delete_failed_message"
    public static let STORIES_REPLY_HERE               = "stories_reply_here"
    public static let STORIES_TYPE_HERE                = "stories_type_here"
    public static let STORIES_VIEWED_BY                = "stories_viewed_by"
    public static let STORIES_DOWNLOAD                 = "stories_download"
    public static let STORIES_CHARACTER_LIMIT          = "stories_character_limit"
    public static let STORIES_MENTION                  = "stories_mention"
    public static let STORIES_SEARCH_PEOPLE_GROUPS     = "stories_search_people_groups"
    public static let STORIES_GROUPS                   = "stories_groups"
    public static let STORIES_CONTACTS                 = "stories_contacts"
    public static let STORIES_MEMBERS                  = "stories_members"
    public static let STORIES_LOADING_THUMBNAILS       = "stories_loading_thumbnails"
    public static let STORIES_NO_PHOTO_CAPTURED        = "stories_no_photo_captured"
    public static let STORIES_VIDEO_RECORDED           = "stories_video_recorded"
    public static let STORIES_NO_VIDEO_RECORDED        = "stories_no_video_recorded"
    public static let STORIES_NO_MEDIA                 = "stories_no_media"
    public static let STORIES_SWIPE_UP_FILTER          = "stories_swipe_up_filter"
    public static let STORIES_PROCESSING_POST          = "stories_processing_post"
    public static let STORIES_NO_IMAGE                 = "stories_no_image"
    public static let STORIES_FILE_PDF_ERROR           = "stories_file_pdf_error"
    public static let STORIES_FILE_IMAGE_ERROR         = "stories_file_image_error"
    public static let STORIES_FILE_ADD_CAPTION         = "stories_file_add_caption"
    public static let STORIES_FILE_PAGES               = "stories_file_pages"
    public static let STORIES_FILE_UNKNOWN_SIZE        = "stories_file_unknown_size"
    public static let STORIES_AA                       = "stories_aa"
    public static let STORIES_RECORDING_STATE          = "stories_recording_state"
    public static let STORIES_SAMPLE_CONTACT           = "stories_sample_contact"
    public static let COMMON_LEARN_MORE                = "learn_more"
    public static let PAYMENT_SHOW_KEYPAD              = "payment_show_keypad"
    public static let PAYMENT_REQUEST                  = "payment_request"
    public static let SECURE_SCREEN_RECORDING_BLOCKED  = "secure_screen_recording_blocked"
    public static let ACCESSIBILITY_CLEAR_FIELD        = "accessibility_clear_field"
    public static let CHAT_LIST_NO_RESULTS             = "chat_list_no_results"
    /// Shown where a peer's name belongs when we have neither a name nor a number.
    public static let CHAT_UNKNOWN_USER                = "chat_unknown_user"
    public static let GALLERY_PHOTOS_COUNT             = "gallery_photos_count"
    public static let CHAT_MORE_MUTE                   = "chat_more_mute"
    public static let CHAT_MORE_CONTACT_INFO           = "chat_more_contact_info"
    public static let CHAT_MORE_LOCK_CHAT              = "chat_more_lock_chat"
    public static let CHAT_MORE_CLEAR_CHAT             = "chat_more_clear_chat"
    public static let CHAT_MORE_DELETE_CHAT            = "chat_more_delete_chat"
    public static let CHAT_MORE_BLOCK_USER             = "chat_more_block_user"
    public static let CHAT_MORE_FAVORITE                 = "chat_more_favorite"
    public static let CHAT_MORE_DELETE_CHAT_CONFIRM      = "chat_more_delete_chat_confirm"
    public static let CHAT_MORE_UNBLOCK_USER             = "chat_more_unblock_user"
    public static let CHAT_MORE_BLOCK_USER_NAMED         = "chat_more_block_user_named"
    public static let CHAT_MORE_ARCHIVE_INSTEAD          = "chat_more_archive_instead"
    public static let CHAT_LAST_SEEN_AT                  = "chat_last_seen_at"
    public static let CHAT_MESSAGE_PLACEHOLDER           = "chat_message_placeholder"
    public static let CHAT_A11Y_OPEN_CAMERA             = "chat_a11y_open_camera"
    public static let CHAT_A11Y_ATTACH                  = "chat_a11y_attach"
    public static let CHAT_A11Y_SEND_MESSAGE            = "chat_a11y_send_message"
    public static let CHAT_A11Y_PLAY_VOICE              = "chat_a11y_play_voice"
    public static let CHAT_A11Y_PAUSE_VOICE             = "chat_a11y_pause_voice"
    public static let CHAT_A11Y_PLAYBACK_SPEED          = "chat_a11y_playback_speed"
    public static let CHAT_A11Y_DOWNLOAD                = "chat_a11y_download"
    public static let CHAT_A11Y_UPLOAD                  = "chat_a11y_upload"
    public static let CHAT_A11Y_RETRY_TRANSFER          = "chat_a11y_retry_transfer"
    public static let CHAT_A11Y_CANCEL_TRANSFER         = "chat_a11y_cancel_transfer"
    public static let CHAT_A11Y_RECORD_VIDEO_NOTE       = "chat_a11y_record_video_note"
    public static let CHAT_VIDEO_NOTE_TITLE             = "chat_video_note_title"
    public static let CHAT_VIDEO_NOTE_INSTRUCTION       = "chat_video_note_instruction"
    public static let CHAT_VIDEO_NOTE_CAMERA_UNAVAILABLE = "chat_video_note_camera_unavailable"
    public static let CHAT_A11Y_VIEW_ONCE               = "chat_a11y_view_once"
    public static let CHAT_VIEW_ONCE_MESSAGE            = "chat_view_once_message"
    public static let CHAT_VIEW_ONCE_OPENED             = "chat_view_once_opened"
    public static let CHAT_VIEW_ONCE_CLOSE_HINT         = "chat_view_once_close_hint"
    public static let SETTINGS_CHANGE_PROFILE_PHOTO      = "settings_change_profile_photo"
    public static let SETTINGS_BROADCAST_LISTS           = "settings_broadcast_lists"
    public static let SETTINGS_STARRED_MESSAGES          = "settings_starred_messages"
    public static let SETTINGS_LINKED_DEVICES            = "settings_linked_devices"
    public static let SETTINGS_ACCOUNT                   = "settings_account"
    public static let SETTINGS_CHATS_MENU                = "settings_chats_menu"
    public static let SETTINGS_CHAT_APPEARANCE           = "settings_chat_appearance"
    public static let SETTINGS_CHAT_APPEARANCE_FOOTER    = "settings_chat_appearance_footer"
    public static let SETTINGS_TIME_FORMAT                 = "settings_time_format"
    public static let SETTINGS_TIME_FORMAT_FOOTER        = "settings_time_format_footer"
    public static let SETTINGS_TIME_FORMAT_24H            = "settings_time_format_24h"
    public static let SETTINGS_TIME_FORMAT_12H            = "settings_time_format_12h"
    public static let CHAT_APPEARANCE_DEFAULT            = "chat_appearance_default"
    public static let CHAT_APPEARANCE_LIGHT              = "chat_appearance_light"
    public static let CHAT_APPEARANCE_DARK               = "chat_appearance_dark"
    public static let CHAT_APPEARANCE_CONVERSATION_FOOTER = "chat_appearance_conversation_footer"
    public static let SETTINGS_NOTIFICATIONS             = "settings_notifications"
    public static let SETTINGS_STORAGE_DATA              = "settings_storage_data"
    public static let SETTINGS_HELP                      = "settings_help"
    public static let SETTINGS_TELL_FRIEND               = "settings_tell_friend"
    public static let SETTINGS_LOG_OUT                   = "settings_log_out"
    public static let SETTINGS_WALLPAPER_SOUND           = "settings_wallpaper_sound"
    public static let SETTINGS_CONTACT_DETAILS           = "settings_contact_details"
    public static let CALLS_FILTER_ALL                 = "calls_filter_all"
    public static let CALLS_FILTER_MISSED              = "calls_filter_missed"
    public static let STORIES_VIDEO_LABEL              = "stories_video_label"
    public static let STORIES_PHOTO_LABEL              = "stories_photo_label"
}
