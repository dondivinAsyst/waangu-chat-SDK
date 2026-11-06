// FeatureChat/Data/Models/MessageContentModel.swift
import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: MessageContentModel
// ─────────────────────────────────────────────────────────────
// Contenu unifié d'un message — texte, média, localisation,
// contact, sondage, paiement, trajet, commande, appel.
// Embarqué dans MessageModel.content (json_payload).
// Pas une table séparée — zéro jointure au scroll.

public struct MessageContentModel: Codable, Sendable {

    // ── Texte ─────────────────────────────────────────────────
    public var text: String?

    // ── Fichier ───────────────────────────────────────────────
    public var url:          String?
    public var thumbnailURL: String?
    public var localPath:    String?
    public var mimeType:     String?
    public var fileSize:     Int?
    public var fileName:     String?

    // ── Dimensions (image, video, sticker, gif) ───────────────
    public var width:  Int?
    public var height: Int?

    /// Automatic transfer attempts already spent on this message's media —
    /// uploads for a message we sent, downloads for one we received.
    ///
    /// Device-local bookkeeping: it is deliberately absent from `MessageContentDTO`
    /// so it never goes on the wire. Optional so that rows written before it
    /// existed still decode — the engine stores the model as a JSON payload, and a
    /// missing key for an optional decodes as nil rather than throwing, which is
    /// what keeps this migration-free.
    public var autoTransferAttempts: Int?

    // ── Durée (voice, audio, video) ───────────────────────────
    public var durationSeconds: Double?

    // ── Audio / Voice ─────────────────────────────────────────
    public var waveform: [Float]?

    // ── Localisation ──────────────────────────────────────────
    public var latitude:            Double?
    public var longitude:           Double?
    public var locationName:        String?
    public var locationAddress:     String?
    public var liveDurationSeconds: Int?

    /// True when this `LOCATION` message anchors a live share.
    ///
    /// The ticks themselves are never stored — they have a Redis TTL behind
    /// them and live in `LiveLocationStore` — so this and `liveExpiresAt` are
    /// all a relaunch has to decide whether the share is still running.
    public var isLiveLocation:      Bool?
    /// Share id, matching the ticks. The message's own `codeMessage` unless
    /// the sender named a different one.
    public var liveShareId:         String?
    /// Epoch seconds. A number rather than a `Date` so the stored payload
    /// holds what the wire carried, whatever encoder writes it.
    public var liveExpiresAt:       Double?

    // ── Contact partagé ───────────────────────────────────────
    public var contacts: [MessageContactModel]?
    public var contactName:  String?
    public var contactPhone: String?
    public var contactVCard: String?
    public var isRegistered: Bool?
    public var isSavedContact: Bool?

    // ── Sondage ───────────────────────────────────────────────
    public var pollQuestion:         String?
    public var pollOptions:          [PollOptionModel]?
    public var pollIsMultipleChoice: Bool?
    public var pollIsClosed:         Bool?

    // ── Paiement (Waangu) ─────────────────────────────────────
    public var paymentAmount:   Double?
    public var paymentCurrency: String?
    public var paymentStatus:   String?
    public var paymentRef:      String?

    // ── Objet financier (Bloc 1) ──────────────────────────────
    // Les quatre colonnes ci-dessus préexistaient au Bloc 1 et sont conservées.
    // Les trois suivantes complètent ce qui manquait pour que la carte soit
    // reconstructible : la nature de l'objet, sa révision, et de quoi présenter
    // la contrepartie sans la résoudre localement.

    /// `FinancialObjectType.rawValue`. Avec `paymentRef`, forme l'identité de l'objet.
    public var financialObjectType: String?

    /// Révision de l'objet.
    ///
    /// Sans elle, une resynchronisation ne peut pas décider si la ligne en base
    /// est plus ancienne que l'événement reçu — et écrase donc parfois le récent
    /// par l'ancien.
    public var financialObjectVersion: Int?

    /// Corrélation de l'opération, pour recouper les logs client et serveur.
    public var financialCorrelationId: String?

    /// Nom de contrepartie **tel que rendu par le backend**.
    ///
    /// Jamais résolu depuis l'annuaire local : un nom de contact local peut
    /// désigner quelqu'un d'autre que le bénéficiaire réel.
    public var financialCounterpartyName: String?

    /// Frais, séparés du montant.
    public var financialFeeAmount: Double?

    // ── Montants décimaux (tâche 4.3b) ────────────────────────
    //
    // `paymentAmount` et `financialFeeAmount` sont des `Double` : un binaire
    // flottant ne représente pas exactement une somme d'argent, et le dernier
    // centime peut se décaler.
    //
    // La colonne n'est pas *changée* de type : `MessageContentModel` est
    // sérialisé en JSON dans `MessageModel.content`, et des lignes existantes
    // portent déjà un `Double`. Les réécrire d'un coup casserait leur décodage.
    // Les champs décimaux s'ajoutent donc **à côté** :
    //
    //   - en écriture, les deux sont renseignés ;
    //   - en lecture, le décimal fait autorité, le `Double` sert de repli.
    //
    // Une version antérieure de l'application continue donc de lire les lignes
    // écrites par celle-ci, ce qui garde un retour arrière possible.

    /// Montant en représentation décimale exacte, sous forme de chaîne.
    public var paymentAmountDecimal: String?

    /// Frais en représentation décimale exacte.
    public var financialFeeAmountDecimal: String?

    /// `FinancialCardVerification.rawValue` — ce que ce client a pu établir.
    public var financialVerification: String?

    /// Dernière lecture serveur, en `timeIntervalSince1970`.
    public var financialRefreshedAt: Double?

    // ── Trajet (Waangu) ───────────────────────────────────────
    public var rideStatus:      String?
    public var rideETA:         Int?
    public var rideOrigin:      String?
    public var rideDestination: String?

    // ── Commande (Waangu) ─────────────────────────────────────
    public var orderStatus: String?
    public var orderRef:    String?

    // ── Appel ─────────────────────────────────────────────────
    public var callType:     CallTypeModel?
    public var callDuration: Int?

    /// How the call ended, as `CallOutcome.rawValue`.
    ///
    /// `MessageTypeModel` is coarser than the call kinds it has to store, so
    /// these three fields carry what it cannot. Without the outcome the type
    /// only says connected or not, and every unconnected outgoing call reads
    /// back as "Cancelled" — including ones the far end declined, ones where the
    /// line was busy, and ones the server refused outright.
    public var callOutcome: String?

    /// Whether the call carried video.
    ///
    /// Both missed kinds collapse to `missedCall`, which would otherwise make
    /// every missed video call read back as audio.
    public var callIsVideo: Bool?

    /// Whether the call was answered.
    ///
    /// Connected calls collapse to `system`, which maps back to plain text — so
    /// without this a finished call stops being a call bubble on reload.
    public var callConnected: Bool?

    // ── Événement de groupe ───────────────────────────────────

    /// Which group event this is, as `MessageTypeProps.rawValue`.
    ///
    /// `MessageTypeModel` collapses all of them to `system`, which maps back to
    /// plain text — so without this a group event stops being a checkpoint bubble
    /// on reload. Same reason `callConnected` exists.
    public var groupEventType: String?

    /// Who the event was about, and their name at the time it happened.
    ///
    /// The name is denormalized on purpose: a member who was removed is no longer
    /// in the roster, so there is nothing left to resolve the id against when the
    /// bubble is rendered months later.
    public var groupTargetUserId: String?
    public var groupTargetName:   String?
    public var groupTitle:        String?

    // ── Media batch (multi-select send grouping) ───────────────
    /// Shared UUID for all images/videos sent in the same gallery batch.
    /// Nil for single-item sends. Persisted so grouping survives app restart.
    public var mediaBatchId: String?

    // ── Upload state ────────────────────────────────────────────
    /// True while the media file has not yet been successfully uploaded to the server.
    /// Set to true on send, cleared to false on upload success.
    /// Survives app restart — the bubble uses this to show the retry/upload button.
    public var pendingUpload: Bool?

    /// True once a transfer for this media has ended in failure — an upload for a
    /// message we sent, a download for one we received.
    ///
    /// The domain flag it backs, `MessageContent.shouldRetry`, was read in six
    /// places and written true in none: failure lived only in
    /// `FileUploadViewModel.uploads`, which is memory. A photo that failed to
    /// upload therefore read back as merely pending, and was indistinguishable
    /// from one still queued.
    ///
    /// Optional for the same reason as `autoTransferAttempts`: the model is stored
    /// as a JSON payload, so a row written before this key existed decodes with it
    /// nil rather than throwing. No migration.
    public var mediaTransferFailed: Bool?

    /// When this device used up a view-once message. Each side opens its own
    /// copy once, so this is device-local like `autoTransferAttempts` and never
    /// goes on the wire. Optional for the same migration-free reason.
    public var viewOnceOpenedAt: Date?

    // ── Init ──────────────────────────────────────────────────

    public init(
        text:                 String?            = nil,
        url:                  String?            = nil,
        thumbnailURL:         String?            = nil,
        localPath:            String?            = nil,
        mimeType:             String?            = nil,
        fileSize:             Int?               = nil,
        fileName:             String?            = nil,
        width:                Int?               = nil,
        height:               Int?               = nil,
        autoTransferAttempts: Int?               = nil,
        durationSeconds:      Double?            = nil,
        waveform:             [Float]?           = nil,
        latitude:             Double?            = nil,
        longitude:            Double?            = nil,
        locationName:         String?            = nil,
        locationAddress:      String?            = nil,
        liveDurationSeconds:  Int?               = nil,
        isLiveLocation:       Bool?              = nil,
        liveShareId:          String?            = nil,
        liveExpiresAt:        Double?            = nil,
        contacts:             [MessageContactModel]? = nil,
        contactName:          String?            = nil,
        contactPhone:         String?            = nil,
        contactVCard:         String?            = nil,
        isRegistered:         Bool?              = nil,
        isSavedContact:       Bool?              = nil,
        pollQuestion:         String?            = nil,
        pollOptions:          [PollOptionModel]? = nil,
        pollIsMultipleChoice: Bool?              = nil,
        pollIsClosed:         Bool?              = nil,
        paymentAmount:        Double?            = nil,
        paymentCurrency:      String?            = nil,
        paymentStatus:        String?            = nil,
        paymentRef:           String?            = nil,
        financialObjectType:      String?        = nil,
        financialObjectVersion:   Int?           = nil,
        financialCorrelationId:   String?        = nil,
        financialCounterpartyName: String?       = nil,
        financialFeeAmount:       Double?        = nil,
        paymentAmountDecimal:     String?        = nil,
        financialFeeAmountDecimal: String?       = nil,
        financialVerification:    String?        = nil,
        financialRefreshedAt:     Double?        = nil,
        rideStatus:           String?            = nil,
        rideETA:              Int?               = nil,
        rideOrigin:           String?            = nil,
        rideDestination:      String?            = nil,
        orderStatus:          String?            = nil,
        orderRef:             String?            = nil,
        callType:             CallTypeModel?     = nil,
        callDuration:         Int?               = nil,
        callOutcome:          String?            = nil,
        callIsVideo:          Bool?              = nil,
        callConnected:        Bool?              = nil,
        groupEventType:       String?            = nil,
        groupTargetUserId:    String?            = nil,
        groupTargetName:      String?            = nil,
        groupTitle:           String?            = nil,
        mediaBatchId:         String?            = nil,
        pendingUpload:        Bool?              = nil,
        mediaTransferFailed:  Bool?              = nil,
        viewOnceOpenedAt:     Date?              = nil
    ) {
        self.text                 = text
        self.url                  = url
        self.thumbnailURL         = thumbnailURL
        self.localPath            = localPath
        self.mimeType             = mimeType
        self.fileSize             = fileSize
        self.fileName             = fileName
        self.width                = width
        self.height               = height
        self.autoTransferAttempts = autoTransferAttempts
        self.durationSeconds      = durationSeconds
        self.waveform             = waveform
        self.latitude             = latitude
        self.longitude            = longitude
        self.locationName         = locationName
        self.locationAddress      = locationAddress
        self.liveDurationSeconds  = liveDurationSeconds
        self.isLiveLocation       = isLiveLocation
        self.liveShareId          = liveShareId
        self.liveExpiresAt        = liveExpiresAt
        self.contacts             = contacts
        self.contactName          = contactName
        self.contactPhone         = contactPhone
        self.contactVCard         = contactVCard
        self.isRegistered         = isRegistered
        self.isSavedContact       = isSavedContact
        self.pollQuestion         = pollQuestion
        self.pollOptions          = pollOptions
        self.pollIsMultipleChoice = pollIsMultipleChoice
        self.pollIsClosed         = pollIsClosed
        self.paymentAmount        = paymentAmount
        self.paymentCurrency      = paymentCurrency
        self.paymentStatus        = paymentStatus
        self.paymentRef           = paymentRef
        self.financialObjectType       = financialObjectType
        self.financialObjectVersion    = financialObjectVersion
        self.financialCorrelationId    = financialCorrelationId
        self.financialCounterpartyName = financialCounterpartyName
        self.financialFeeAmount        = financialFeeAmount
        self.paymentAmountDecimal      = paymentAmountDecimal
        self.financialFeeAmountDecimal = financialFeeAmountDecimal
        self.financialVerification     = financialVerification
        self.financialRefreshedAt      = financialRefreshedAt
        self.rideStatus           = rideStatus
        self.rideETA              = rideETA
        self.rideOrigin           = rideOrigin
        self.rideDestination      = rideDestination
        self.orderStatus          = orderStatus
        self.orderRef             = orderRef
        self.callType             = callType
        self.callDuration         = callDuration
        self.callOutcome          = callOutcome
        self.callIsVideo          = callIsVideo
        self.callConnected        = callConnected
        self.groupEventType       = groupEventType
        self.groupTargetUserId    = groupTargetUserId
        self.groupTargetName      = groupTargetName
        self.groupTitle           = groupTitle
        self.mediaBatchId         = mediaBatchId
        self.pendingUpload         = pendingUpload
        self.mediaTransferFailed  = mediaTransferFailed
        self.viewOnceOpenedAt     = viewOnceOpenedAt
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Factories
// ─────────────────────────────────────────────────────────────

public extension MessageContentModel {

    static func text(_ text: String) -> Self {
        MessageContentModel(text: text)
    }

    static func image(url: String, thumbnailURL: String?, width: Int, height: Int, caption: String? = nil) -> Self {
        MessageContentModel(text: caption, url: url, thumbnailURL: thumbnailURL, width: width, height: height)
    }

    static func video(url: String, thumbnailURL: String?, width: Int, height: Int, duration: Double, caption: String? = nil) -> Self {
        MessageContentModel(text: caption, url: url, thumbnailURL: thumbnailURL, width: width, height: height, durationSeconds: duration)
    }

    static func voice(url: String, duration: Double, waveform: [Float]?) -> Self {
        MessageContentModel(url: url, mimeType: "audio/ogg", durationSeconds: duration, waveform: waveform)
    }

    static func document(url: String, fileName: String, mimeType: String, fileSize: Int) -> Self {
        MessageContentModel(url: url, mimeType: mimeType, fileSize: fileSize, fileName: fileName)
    }

    static func location(latitude: Double, longitude: Double, name: String?, address: String?) -> Self {
        MessageContentModel(latitude: latitude, longitude: longitude, locationName: name, locationAddress: address)
    }

    static func liveLocation(latitude: Double, longitude: Double, duration: Int) -> Self {
        MessageContentModel(latitude: latitude, longitude: longitude, liveDurationSeconds: duration)
    }

    static func contacts(_ contacts: [MessageContactModel]) -> Self {
        MessageContentModel(
            contacts: contacts,
            contactName: contacts.first?.name,
            contactPhone: contacts.first?.phone
        )
    }

    static func payment(amount: Double, currency: String, status: String, ref: String?) -> Self {
        MessageContentModel(paymentAmount: amount, paymentCurrency: currency, paymentStatus: status, paymentRef: ref)
    }

    static func missedCall(type: CallTypeModel, duration: Int = 0) -> Self {
        MessageContentModel(callType: type, callDuration: duration)
    }

    static func system(_ text: String) -> Self {
        MessageContentModel(text: text)
    }
}

public struct MessageContactModel: Codable, Sendable {
    public var id: String
    public var idContact: String?
    public var userId: String
    public var phone: String
    public var name: String?
    public var avatar: String?
    public var isRegistered: Bool?

    public init(
        id: String,
        idContact: String? = nil,
        userId: String,
        phone: String,
        name: String? = nil,
        avatar: String? = nil,
        isRegistered: Bool? = nil
    ) {
        self.id = id
        self.idContact = idContact
        self.userId = userId
        self.phone = phone
        self.name = name
        self.avatar = avatar
        self.isRegistered = isRegistered
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: PollOptionModel
// ─────────────────────────────────────────────────────────────

public struct PollOptionModel: Codable, Sendable, Identifiable {
    public var id:        String
    public var text:      String
    public var voterIds:  [String]
    public var voteCount: Int

    public init(id: String = UUID().uuidString.lowercased(), text: String, voterIds: [String] = [], voteCount: Int = 0) {
        self.id        = id
        self.text      = text
        self.voterIds  = voterIds
        self.voteCount = voteCount
    }
}
