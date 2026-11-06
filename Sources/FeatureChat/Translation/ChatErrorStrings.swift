//
//  ChatErrorStrings.swift
//  FeatureChat
//
//  Messages d'erreur montrés à l'utilisateur.
//

import Foundation

/// Les messages d'erreur que l'utilisateur lit.
///
/// Ils étaient écrits en anglais dans les vues et les repositories d'une
/// application dont l'interface est française : un échec d'envoi affichait
/// « Failed to send image » à quelqu'un qui n'avait jamais vu un mot d'anglais
/// dans le reste de l'application.
///
/// Ne contient **que** ce qu'un utilisateur peut voir. Les traces, les domaines
/// `NSError` et les `debugDescription` restent en anglais : ils sont lus par des
/// développeurs, et les traduire rendrait les recherches dans les journaux
/// dépendantes de la langue du poste.
public enum ChatErrorStrings {

    private static func t(_ key: String, _ fallback: String) -> String {
        let value = NSLocalizedString(key, bundle: .module, comment: "")
        return value == key ? fallback : value
    }

    // MARK: Envoi de message

    public static var sendImageInvalidPath: String {
        t("chat.error.send_image_invalid_path", "Envoi impossible : image introuvable.")
    }
    public static var sendAudioInvalidPath: String {
        t("chat.error.send_audio_invalid_path", "Envoi impossible : enregistrement introuvable.")
    }
    /// Format à une chaîne : l'URL en cause.
    public static var sendAudioBadURL: String {
        t("chat.error.send_audio_bad_url", "Envoi impossible : enregistrement illisible (%@).")
    }
    public static var sendAudioSaveFailed: String {
        t("chat.error.send_audio_save_failed", "L'enregistrement n'a pas pu être sauvegardé.")
    }

    // MARK: Fichiers

    public static var imageConversionFailed: String {
        t("chat.error.image_conversion_failed", "Cette image n'a pas pu être préparée pour l'envoi.")
    }
    /// Format à une chaîne : la cause système.
    public static var fileReadFailed: String {
        t("chat.error.file_read_failed", "Fichier illisible : %@")
    }
    public static var imageDecodeFailed: String {
        t("chat.error.image_decode_failed", "L'image reçue n'a pas pu être affichée.")
    }
    public static var documentSaveFailed: String {
        t("chat.error.document_save_failed", "Le document reçu n'a pas pu être enregistré.")
    }
    public static var uploadPartFailed: String {
        t("chat.error.upload_part_failed", "L'envoi a été interrompu. Réessayez.")
    }

    public static var audioSaveFailed: String {
        t("chat.error.audio_save_failed", "L'audio reçu n'a pas pu être enregistré.")
    }
    public static var downloadURLMissing: String {
        t("chat.error.download_url_missing", "Téléchargement impossible : lien indisponible.")
    }
    /// Format à une chaîne : l'adresse en cause.
    public static var imageLoadFailed: String {
        t("chat.error.image_load_failed", "Cette image n'a pas pu être chargée (%@).")
    }
    /// Format à une chaîne : la cause système.
    public static var uploadURLFailed: String {
        t("chat.error.upload_url_failed", "L'envoi n'a pas pu être préparé : %@")
    }
    public static var uploadIncomplete: String {
        t("chat.error.upload_incomplete", "L'envoi n'a pas été confirmé par le serveur. Réessayez.")
    }

    // MARK: Envoi — échecs génériques

    public static var sendMessageFailed: String {
        t("chat.error.send_message_failed", "Le message n'a pas pu être envoyé.")
    }
    public static var sendDocumentFailed: String {
        t("chat.error.send_document_failed", "Le document n'a pas pu être envoyé.")
    }
    public static var sendVoiceFailed: String {
        t("chat.error.send_voice_failed", "Le message vocal n'a pas pu être envoyé.")
    }
    public static var sendImageFailed: String {
        t("chat.error.send_image_failed", "L'image n'a pas pu être envoyée.")
    }
    public static var sendVideoFailed: String {
        t("chat.error.send_video_failed", "La vidéo n'a pas pu être envoyée.")
    }
    public static var prepareVideoFailed: String {
        t("chat.error.prepare_video_failed", "La vidéo n'a pas pu être préparée pour l'envoi.")
    }
    public static var sendLocationFailed: String {
        t("chat.error.send_location_failed", "La position n'a pas pu être envoyée.")
    }
    public static var startLiveLocationFailed: String {
        t("chat.error.start_live_location_failed", "Le partage de position n'a pas pu démarrer.")
    }
    public static var deleteMessageFailed: String {
        t("chat.error.delete_message_failed", "Le message n'a pas pu être supprimé.")
    }
    public static var saveContactFailed: String {
        t("chat.error.save_contact_failed", "Le contact n'a pas pu être enregistré.")
    }
    /// Format à une chaîne : la cause système.
    public static var blockStatusFailedDetailed: String {
        t("chat.error.block_status_failed_detailed",
          "Le statut de blocage n'a pas pu être mis à jour : %@")
    }
    /// Format à une chaîne : la cause système.
    public static var addMembersFailed: String {
        t("chat.error.add_members_failed", "Les membres n'ont pas pu être ajoutés : %@")
    }
    /// Format à une chaîne : la cause système.
    public static var resetInviteLinkFailed: String {
        t("chat.error.reset_invite_link_failed",
          "Le lien d'invitation n'a pas pu être réinitialisé : %@")
    }

    // MARK: Médias — transfert

    public static var invalidURL: String {
        t("chat.error.invalid_url", "Adresse invalide.")
    }
    public static var invalidServerResponse: String {
        t("chat.error.invalid_server_response", "Réponse inattendue du serveur.")
    }
    public static var localFileNotFound: String {
        t("chat.error.local_file_not_found", "Fichier introuvable sur l'appareil.")
    }
    public static var fileDetailsMissing: String {
        t("chat.error.file_details_missing", "Détails du fichier indisponibles.")
    }

    // MARK: Appels — état

    public static var callConnectFailed: String {
        t("chat.error.call_connect_failed", "L'appel n'a pas pu être établi")
    }

    // MARK: Groupes — administration

    /// Format à une chaîne : la cause système.
    public static var clearMessagesFailed: String {
        t("chat.error.clear_messages_failed", "Les messages n'ont pas pu être effacés : %@")
    }
    /// Format à une chaîne : la cause système.
    public static var permissionUpdateFailed: String {
        t("chat.error.permission_update_failed", "L'autorisation n'a pas pu être modifiée : %@")
    }

    // MARK: Contacts

    /// Format à un entier : le nombre de contacts.
    public static var contactSyncFailed: String {
        t("chat.error.contact_sync_failed", "%d contact(s) n'ont pas pu être synchronisés.")
    }
    public static var blockStatusFailed: String {
        t("chat.error.block_status_failed", "Le statut de blocage n'a pas pu être mis à jour.")
    }
    public static var blockMissingContact: String {
        t("chat.error.block_missing_contact",
          "Blocage impossible : les informations du contact sont indisponibles.")
    }

    // MARK: Groupes

    public static var cannotDeleteGroupTitle: String {
        t("chat.error.cannot_delete_group_title", "Suppression impossible")
    }
    public static var cannotDeleteShort: String {
        t("chat.error.cannot_delete_short", "Suppression impossible")
    }
    /// Format à une chaîne : la cause système.
    public static var deletionEligibilityFailed: String {
        t("chat.error.deletion_eligibility_failed",
          "Impossible de vérifier si la suppression est possible : %@")
    }

    // MARK: Appels

    public static var cameraOpenFailed: String {
        t("chat.error.camera_open_failed", "La caméra n'a pas pu être ouverte.")
    }

    // MARK: Ouverture du Chat

    public static var chatOpenFailedTitle: String {
        t("chat.error.chat_open_failed_title", "La messagerie n'a pas pu s'ouvrir")
    }
    public static var chatOpenFailedMessage: String {
        t("chat.error.chat_open_failed_message",
          "Le reste de l'application fonctionne normalement. Vous pouvez réessayer.")
    }
    public static var chatOpenRetry: String {
        t("chat.error.chat_open_retry", "Réessayer")
    }
    public static var chatOpenCancel: String {
        t("chat.error.chat_open_cancel", "Annuler")
    }

    // MARK: Canaux — invitations

    public static var channelLoadFailedTitle: String {
        t("chat.error.channel_load_failed_title", "Impossible de charger le canal")
    }
    public static var channelInviteLinkLoadFailed: String {
        t("chat.error.channel_invite_link_load_failed", "Le lien d'invitation n'a pas pu être chargé.")
    }
    public static var channelInviteLinkGenerateFailed: String {
        t("chat.error.channel_invite_link_generate_failed", "Le lien d'invitation n'a pas pu être créé.")
    }
    public static var channelInviteLinkRevokeFailed: String {
        t("chat.error.channel_invite_link_revoke_failed", "Le lien d'invitation n'a pas pu être révoqué.")
    }
    public static var channelInviteInvalid: String {
        t("chat.error.channel_invite_invalid", "Ce lien d'invitation est invalide ou a expiré.")
    }
    public static var channelJoinBanned: String {
        t("chat.error.channel_join_banned", "Vous n'êtes pas autorisé à rejoindre ce canal.")
    }
    public static var channelJoinForbidden: String {
        t("chat.error.channel_join_forbidden", "Vous n'avez pas la permission de rejoindre ce canal.")
    }
    public static var channelUnavailableInRegion: String {
        t("chat.error.channel_unavailable_in_region", "Ce canal n'est pas disponible dans votre région.")
    }
    public static var channelUnavailable: String {
        t("chat.error.channel_unavailable", "Ce canal n'est pas disponible.")
    }
    public static var channelJoinFailed: String {
        t("chat.error.channel_join_failed", "Impossible de rejoindre le canal.")
    }
    public static var channelJoinFailedRetry: String {
        t("chat.error.channel_join_failed_retry", "Impossible de rejoindre le canal. Réessayez.")
    }
    /// Format à une chaîne : la cause système.
    public static var channelJoinFailedWithCause: String {
        t("chat.error.channel_join_failed_with_cause", "Impossible de rejoindre le canal : %@")
    }
}
