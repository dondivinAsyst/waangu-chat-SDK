//
//  CopilotConversationViewModel.swift
//  FeatureChat
//
//  Waangu Copilot (§8) — l'opération se mène dans la conversation, jusqu'au bout.
//

import Foundation
import WaanguCoreKit
import WaanguSharedUI

/// La conversation avec Waangu Copilot, **le temps de l'écran** : rien n'est
/// conservé après fermeture — ni montants, ni noms.
///
/// L'opération se mène ici, sans ouvrir d'autre écran : Copilot pose les
/// questions (bénéficiaire, montant), le devis du serveur s'affiche en carte,
/// l'utilisateur confirme, et le statut suit dans le fil.
///
/// **Copilot n'exécute rien.** Les questions sont celles de l'app ; tout ce qui
/// compte — nom vérifié, frais, total, statut — vient du serveur. La
/// confirmation est un geste de l'utilisateur, suivi de Face ID ou du code, puis
/// le même chemin que l'écran d'envoi : `TransferSubmission` (clé enregistrée,
/// inscription avant execute, relecture). Aucun outil Copilot n'y participe, et
/// aucune portée `execute` n'est jamais accordée au registre.
///
/// Gardes : le texte libre passe le filtre d'injection de l'app ; un outil n'est
/// invoqué que s'il figure au registre (`CopilotToolRegistry`).
@MainActor
final class CopilotConversationViewModel: ObservableObject {

    // MARK: - Fil

    /// Un parcours que ce fil ne mène pas encore lui-même — à ouvrir.
    struct Proposal: Equatable, Codable {
        let kind: FinanceEntryKind
        let amount: Decimal?
        let currency: String?
    }

    /// Le bénéficiaire tel que le serveur l'a résolu.
    struct RecipientCard: Equatable, Codable {
        let name: String
        let verified: Bool
    }

    enum CardState: Equatable, Codable { case open, confirming, closed }

    enum ScannerState: Equatable, Codable {
        /// La caméra tourne et attend un code.
        case active
        /// Un code a été lu.
        case scanned
        /// Fermée sans code : une autre commande a commencé.
        case closed
    }

    /// Le devis du serveur, à confirmer.
    struct QuoteCard: Equatable, Codable {
        typealias State = CardState
        let quote: TransferQuote
        let recipientName: String
        var state: State
        /// L'opération — son titre sur la carte.
        var kind: FinanceEntryKind = .sendMoney
        /// À qui l'execute s'adresse : le jeton du bénéficiaire, le facturier…
        var payeeID: String = ""
        /// Libellé de `recipientName` — « À », ou le canal d'un dépôt ou d'un retrait.
        var recipientLabel: String = FinanceStrings.recipientTo
        /// Un titre à la place de celui de `kind` — le remboursement n'a pas de tuile du Hub.
        var titleOverride: String? = nil
    }

    /// Une facture lue au Biller Hub — le dû, avant tout devis.
    struct BillCard: Equatable, Codable {
        let billerName: String
        let customer: String
        let amountDue: Decimal
        let currency: String
        let dueDate: Date?
        /// Libellé de `customer` — le client d'un facturier, le numéro d'une facture marchande.
        var customerLabel: String = FinanceStrings.billCustomer
    }

    /// Une réponse proposée : catégorie, facturier, valeur admise, passer.
    struct Option: Identifiable, Equatable {
        let id: String
        let title: String
        var detail: String? = nil
    }

    /// Une demande d'argent, à envoyer. Aucun débit : le payeur confirmera de son côté.
    struct RequestCard: Equatable, Codable {
        let recipientName: String
        let amount: Decimal
        let currency: String
        var state: CardState
    }

    enum Message: Identifiable, Equatable {
        case user(id: UUID, text: String)
        /// Les mots de Copilot, rendus par le serveur tels quels. Non autoritatifs
        /// (`authoritative == false`), ils sont légendés « Waangu Copilot » : jamais
        /// un solde, un statut ni un montant — ceux-là viennent du devis ou de la carte.
        case copilot(id: UUID, text: String, authoritative: Bool)
        /// Ce que l'app dit ou demande pour mener l'opération — ses propres textes.
        case question(id: UUID, text: String)
        case proposal(id: UUID, Proposal)
        case recipient(id: UUID, RecipientCard)
        case quote(id: UUID, QuoteCard)
        case requestReview(id: UUID, RequestCard)
        case bill(id: UUID, BillCard)
        /// La caméra, dans le fil : elle attend un code, l'a lu, ou a été fermée.
        case scanner(id: UUID, state: ScannerState)
        /// L'opération soumise : sa carte se lit au serveur.
        case outcome(id: UUID, FinancialReference)
        /// Le code de retrait émis par Finance — montré ici une fois, jamais conservé.
        case cashOutCode(id: UUID, CashOutToken)
        /// Ce que l'app dit d'elle-même : refus, annulation, indisponibilité.
        case notice(id: UUID, text: String)
        /// La carte n'a pas pu être publiée dans le fil — à repartager. `resolved` :
        /// la nouvelle tentative a réussi.
        case announceFailed(id: UUID, resolved: Bool)
        /// Le lien de paiement d'une demande — montré, jamais conservé (il porte un jeton).
        case paymentLink(id: UUID, url: String, expiresAt: Date?)

        var id: UUID {
            switch self {
            case .user(let id, _), .copilot(let id, _, _), .question(let id, _), .proposal(let id, _),
                 .recipient(let id, _), .quote(let id, _), .requestReview(let id, _), .bill(let id, _), .scanner(let id, _),
                 .outcome(let id, _), .cashOutCode(let id, _), .notice(let id, _), .announceFailed(let id, _),
                 .paymentLink(let id, _, _):
                return id
            }
        }
    }

    /// Ce que la zone de saisie attend.
    enum Step: Equatable {
        /// Texte libre : une demande à lire.
        case free
        /// Un bénéficiaire : contact ou numéro.
        case recipient
        /// Un montant.
        case amount
        /// Une réponse parmi des options.
        case choice
        /// Une réponse libre à une question (champ de formulaire).
        case text
    }

    /// Un bénéficiaire proposé — l'interlocuteur, ou un contact.
    struct RecipientChoice: Identifiable, Equatable {
        let id: String
        let name: String
        let detail: String?
        let input: RecipientInput
        /// Utilisateur Chat derrière ce bénéficiaire, quand on le connaît.
        var chatUserID: String? = nil
        /// Le contact, quand c'en est un : son fil direct porte l'opération.
        var contact: UserContactProps? = nil
    }

    @Published private(set) var messages: [Message] = []
    @Published private(set) var tools: [FinanceCopilotTool] = []
    @Published private(set) var step: Step = .free
    @Published private(set) var isWorking = false
    @Published private(set) var recipientChoices: [RecipientChoice] = []
    /// Indice lu dans la demande (« à Jean ») : préfiltre les contacts.
    @Published private(set) var recipientHint: String?
    /// Réponses proposées à l'étape `.choice` — ou à côté d'une réponse libre.
    @Published private(set) var options: [Option] = []
    /// Invite de la zone de saisie à l'étape `.text`.
    @Published private(set) var textPrompt = ""
    @Published private(set) var textIsNumeric = false

    private let surface: ChatFinanceSurface
    private let host: CopilotConversationHost?
    private let registry = CopilotToolRegistry()

    /// L'opération en cours de conversation.
    private var operation: Operation?
    /// Le signalement en cours — un litige sur une opération déjà faite.
    private var dispute: DisputeFlow?
    /// Le partage d'addition en cours de composition.
    private var split: SplitFlow?

    private struct SplitFlow {
        enum Stage { case label, total, participants, strategy, values, privacy, confirm }
        var stage: Stage = .label
        var label = ""
        var total: Decimal?
        var candidates: [UserContactProps] = []
        var participants: [UserContactProps] = []
        var strategy = SplitStrategyInput()
        /// Le participant dont on attend la valeur (montant ou poids).
        var valueIndex = 0
        var privacy: SplitPrivacyScope = .ownShareOnly
    }

    /// L'annulation à confirmer : l'opération visée, `POST /intent/cancel-request`.
    private var cancellation: FinancialReference?

    /// Annuler n'est offert que si **le serveur** le liste (`allowedActions`), sur
    /// un objet pas encore final.
    static func allowsCancel(_ payload: FinancialCardPayload?) -> Bool {
        guard let payload, !payload.status.isTerminal, let actions = payload.allowedActions else { return false }
        return actions.contains("CANCEL") || actions.contains("CANCEL_INTENT")
    }

    /// La réponse à une demande d'argent reçue : la payer (devis, puis confirmation) ou la refuser.
    private struct AnswerFlow {
        enum Stage { case request, action, amount, confirmDecline }
        var stage: Stage = .request
        var requests: [MoneyRequestOverlay] = []
        var request: MoneyRequestOverlay?
        var amount: Decimal?
    }
    private var answer: AnswerFlow?

    /// Le remboursement en cours — d'une opération faite, jusqu'au devis à confirmer.
    private var refund: RefundFlow?
    /// La demande d'extourne en cours — Finance exécute, rien n'est annulé ici.
    private var reversal: ReversalFlow?

    /// Remboursement et extourne : le serveur ne les met pas dans `allowedActions`
    /// (réponses du backend, Q16/Q17) ; ils ne valent que pour une opération dont
    /// **le serveur** dit `COMPLETED`. Le prepare refuse de toute façon sans (`CF_047`).
    static func allowsRefundOrReversal(_ payload: FinancialCardPayload?) -> Bool {
        ReversalEligibility.allows(payload)
    }

    private struct RefundFlow {
        enum Stage { case operation, amount }
        var stage: Stage = .operation
        var references: [FinancialReference] = []
        var reference: FinancialReference?
        /// Montant et devise de l'opération, lus sur la carte du serveur.
        var original: Decimal = 0
        var currency = ""
        var amount: Decimal?
    }

    private struct ReversalFlow {
        enum Stage { case operation, reason, confirm }
        var stage: Stage = .operation
        var references: [FinancialReference] = []
        var reference: FinancialReference?
        var reason = ""
    }

    private struct DisputeFlow {
        enum Stage { case operation, category, description, consent }
        var stage: Stage = .operation
        var references: [FinancialReference] = []
        var reference: FinancialReference?
        /// La catégorie du serveur, telle que `GET /disputes/taxonomy` la rend.
        var category: String?
        var description = ""
    }

    private struct Operation {
        let kind: FinanceEntryKind
        var amount: Decimal?
        var recipient: ResolvedRecipient?
        var recipientName: String?
        var recipientChatUserID: String?
        /// Fil de l'envoi ou de la demande — `nil` : pas encore choisi.
        var destination: Destination?
        /// Fil du prepare d'une facture marchande, d'un dépôt, d'un retrait :
        /// le fil d'origine, ou le dossier personnel (§5.1.1).
        var operatingID: String?

        // Facture
        var stage: Stage = .none
        var categories: [BillerCategory] = []
        var biller: BillerForm?
        var fields: [DynamicBillerField] = []
        var fieldIndex = 0
        var values: [String: String] = [:]
        var bill: Bill?

        // Recharge
        var msisdn: String?
        var products: [TopUpProduct] = []
        var product: TopUpProduct?

        // QR — la charge lue, envoyée telle quelle au prepare.
        var qrPayload: String?

        // Facture marchande — lue au Merchant Backend.
        var invoice: Invoice?

        // Espèces
        var cashInChannels: [CashInChannel] = []
        var cashOutChannels: [CashOutChannel] = []
        var cashInChannel: CashInChannel?
        var cashOutChannel: CashOutChannel?
        /// L'opération soumise, quand le parcours continue chez l'agent.
        var submitted: FinancialReference?
    }

    /// Où l'opération s'annonce, et quel fil porte son prepare.
    private enum Destination {
        /// Le fil d'où Copilot est ouvert — avec son interlocuteur.
        case thread
        /// Le fil direct du contact choisi : existant, ou créé à l'annonce,
        /// comme le fait l'envoi depuis le portefeuille.
        case direct(WalletPaymentFlowViewModel.Recipient)
        /// Aucune identité de messagerie (numéro tapé) : l'opération se fait,
        /// sans annonce.
        case none
    }

    /// Qui l'utilisateur a désigné.
    private enum RecipientTarget {
        case peer, contact(UserContactProps), typed
    }

    private enum Stage {
        case none, billCategory, biller, billField, billAmount, topUpProduct
        case invoiceReference
        case cashChannel, cashInAgent, cashInHandover, cashOutAgent, cashOutCode
    }

    /// Lire, expliquer, simuler, préparer. **Jamais `execute`.**
    private static let grantedScopes: Set<CopilotScope> = [.read, .explain, .simulate, .prepare]

    /// Les actions que le Hub permet ici — celles des tuiles de l'accueil.
    private let hubKinds: [FinanceEntryKind]
    /// Les actions que le Hub ferme, avec le motif du serveur déjà rédigé.
    private let closedHubActions: [FinanceEntryKind: String]

    /// Le fil direct d'un contact et l'annonce qui s'y fait — ceux de l'envoi
    /// depuis le portefeuille. `nil` : rien n'est annoncé hors du fil d'origine.
    private let directMessaging: WalletPaymentFlowViewModel?

    /// Références dont l'annonce a échoué, par message : « Partager dans le fil ».
    private var pendingAnnouncements: [UUID: (reference: FinancialReference,
                                              publish: @MainActor (FinancialReference) async -> Bool)] = [:]

    /// La conversation Copilot conservée sur l'appareil — une seule, partout.
    /// Ouverte depuis un fil, elle y garde son lien (interlocuteur proposé
    /// d'abord, annonce dans ce fil) ; l'historique, lui, est le même. `nil` :
    /// rien ne se garde.
    private let conversationStore: (any CopilotConversationStoring)?
    /// L'identifiant de la conversation conservée — jamais envoyé à Chat Core.
    private(set) var storedConversationID: String?
    /// Messages relus de l'appareil : déjà lus, ils ne s'écrivent pas à nouveau.
    @Published private(set) var restoredCount = 0
    /// Les écritures, dans l'ordre des messages.
    private var persistence: Task<Void, Never>?

    init(surface: ChatFinanceSurface, host: CopilotConversationHost?, hubKinds: [FinanceEntryKind] = [],
         directMessaging: WalletPaymentFlowViewModel? = nil,
         conversationStore: (any CopilotConversationStoring)? = nil,
         closedHubActions: [FinanceEntryKind: String] = [:]) {
        self.surface = surface
        self.host = host
        self.hubKinds = hubKinds
        self.closedHubActions = closedHubActions
        self.directMessaging = directMessaging
        self.conversationStore = conversationStore
    }

    // MARK: - Suggestions

    /// Une suggestion : une action du Hub, ou un outil de lecture de Copilot.
    enum Suggestion: Identifiable, Equatable {
        case action(FinanceEntryKind, tool: FinanceCopilotTool?)
        case read(FinanceCopilotTool)
        /// Signaler un problème sur une opération déjà faite (litige).
        case reportProblem
        /// Rembourser une opération faite, ou en demander l'extourne.
        case refund, reversal
        /// Payer ou refuser une demande d'argent reçue dans ce fil.
        case answerRequest

        var id: String {
            switch self {
            case .action(let kind, _): return "action-" + kind.rawValue
            case .read(let tool):      return "read-" + tool.name
            case .reportProblem:       return "report-problem"
            case .refund:              return "refund"
            case .reversal:            return "reversal"
            case .answerRequest:       return "answer-request"
            }
        }
    }

    /// Les actions d'abord — celles que le Hub permet, et celles des outils
    /// PREPARE, **une fois chacune** — puis les lectures.
    ///
    /// Les outils seuls ne suffisent pas : le Hub publie des actions (facture,
    /// recharge, espèces…) qu'aucun outil Copilot ne couvre, et deux outils
    /// peuvent mener au même parcours (`qr.prepare`, `invoice.prepare`).
    var suggestions: [Suggestion] {
        var seen = Set<FinanceEntryKind>()
        var actions: [Suggestion] = []
        for tool in tools {
            guard let kind = Self.kind(of: tool), seen.insert(kind).inserted else { continue }
            actions.append(.action(kind, tool: tool))
        }
        for kind in hubKinds where Self.ledInConversation.contains(kind) && seen.insert(kind).inserted {
            actions.append(.action(kind, tool: nil))
        }
        let reads = tools.filter { Self.kind(of: $0) == nil && Self.label(of: $0) != nil }.map(Suggestion.read)
        let answering: [Suggestion] = (host?.receivedRequests().isEmpty == false && surface.requestResponder != nil)
            ? [.answerRequest] : []
        return actions + answering + [.reportProblem, .refund, .reversal] + reads
    }

    /// Les opérations que la conversation mène jusqu'au bout.
    static let ledInConversation: Set<FinanceEntryKind> = [.sendMoney, .requestMoney, .payBill, .topUp, .qrPay,
                                                            .invoice, .cashIn, .cashOut, .splitBill]

    /// Le parcours d'un outil. `invoice.prepare` mène à la facture marchande :
    /// le Hub n'a pas d'action `INVOICE` à lui donner pour handoff.
    static func kind(of tool: FinanceCopilotTool) -> FinanceEntryKind? {
        tool.name == "invoice.prepare" ? .invoice : tool.kind
    }

    func choose(_ suggestion: Suggestion) async {
        abandonOperation()
        switch suggestion {
        case .read(let tool):
            await invoke(tool)
        case .action(_, let tool?):
            await invoke(tool)
        case .action(let kind, nil):
            guard !isWorking else { return }
            append(.user(id: UUID(), text: Self.title(of: kind)))
            await begin(kind, amount: nil, hint: nil)
        case .reportProblem:
            guard !isWorking else { return }
            append(.user(id: UUID(), text: FinanceStrings.copilotReportProblem))
            await beginDispute()
        case .refund:
            guard !isWorking else { return }
            append(.user(id: UUID(), text: FinanceStrings.copilotRequestRefund))
            await beginRefund()
        case .reversal:
            guard !isWorking else { return }
            append(.user(id: UUID(), text: FinanceStrings.copilotRequestReversal))
            await beginReversal()
        case .answerRequest:
            guard !isWorking else { return }
            append(.user(id: UUID(), text: FinanceStrings.copilotAnswerRequest))
            await beginAnswer()
        }
    }

    // MARK: - Commandes « / »

    /// Une commande du menu « / » — une opération, ou une information.
    ///
    /// Ce que l'utilisateur voit : une icône et un titre traduit. Le nom serveur
    /// (`wallet.get_balance`) et la description du serveur, écrits pour des
    /// développeurs, ne s'affichent jamais.
    struct SlashCommand: Identifiable, Equatable {
        /// Nom serveur de l'outil, ou de l'action — pour la correspondance exacte seulement.
        let command: String
        let title: String
        let icon: String
        let suggestion: Suggestion
        /// Le motif **du serveur** quand le Hub ferme cette action — montré sous le titre.
        var unavailableReason: String? = nil
        var id: String { command }
    }

    /// Les opérations d'abord, dans l'ordre des tuiles ; puis les informations.
    /// Un outil sans titre traduit n'y figure pas — il reste au registre.
    var slashCommands: [SlashCommand] {
        var actions: [FinanceEntryKind: SlashCommand] = [:]
        var reads: [SlashCommand] = []
        for tool in tools {
            if let kind = Self.kind(of: tool) {
                guard actions[kind] == nil else { continue }
                actions[kind] = SlashCommand(command: tool.name, title: Self.title(of: kind),
                                             icon: FinanceGovernanceMapper.icon(for: kind),
                                             suggestion: .action(kind, tool: tool))
            } else if let title = Self.label(of: tool) {
                reads.append(SlashCommand(command: tool.name, title: title, icon: Self.icon(ofRead: tool),
                                          suggestion: .read(tool)))
            }
        }
        for kind in hubKinds where Self.ledInConversation.contains(kind) && actions[kind] == nil {
            actions[kind] = SlashCommand(command: kind.rawValue.lowercased(), title: Self.title(of: kind),
                                         icon: FinanceGovernanceMapper.icon(for: kind),
                                         suggestion: .action(kind, tool: nil))
        }
        // Une action que le Hub ferme reste visible, avec son motif — elle ne démarre pas.
        for (kind, reason) in closedHubActions where Self.ledInConversation.contains(kind) && actions[kind] == nil {
            actions[kind] = SlashCommand(command: kind.rawValue.lowercased(), title: Self.title(of: kind),
                                         icon: FinanceGovernanceMapper.icon(for: kind),
                                         suggestion: .action(kind, tool: nil), unavailableReason: reason)
        }
        let ordered = Self.slashOrder.compactMap { actions.removeValue(forKey: $0) }
        let others = actions.values.sorted { $0.title < $1.title }
        let report = SlashCommand(command: "report_problem", title: FinanceStrings.copilotReportProblem,
                                  icon: "exclamationmark.bubble", suggestion: .reportProblem)
        let refund = SlashCommand(command: "refund", title: FinanceStrings.copilotRequestRefund,
                                  icon: "arrow.uturn.backward.circle", suggestion: .refund)
        let reversal = SlashCommand(command: "reversal", title: FinanceStrings.copilotRequestReversal,
                                    icon: "arrow.counterclockwise.circle", suggestion: .reversal)
        var answering: [SlashCommand] = []
        if host?.receivedRequests().isEmpty == false, surface.requestResponder != nil {
            answering = [SlashCommand(command: "answer_request", title: FinanceStrings.copilotAnswerRequest,
                                      icon: "arrow.down.left.circle", suggestion: .answerRequest)]
        }
        return ordered + others + answering + [report, refund, reversal] + reads
    }

    /// L'ordre des opérations dans le menu — celui des tuiles de l'accueil.
    static let slashOrder: [FinanceEntryKind] = [.sendMoney, .requestMoney, .payBill, .topUp, .qrPay,
                                                 .invoice, .cashIn, .cashOut, .splitBill]

    private static func icon(ofRead tool: FinanceCopilotTool) -> String {
        switch tool.name {
        case "wallet.get_balance": return "wallet.pass"
        case "fco.get_status":     return "clock.arrow.circlepath"
        case "capability.list":    return "list.bullet.rectangle"
        default:                   return "info.circle"
        }
    }

    /// Ce qui suit « / » filtre par commande ou par titre — sans casse ni accents.
    static func slashMatches(_ commands: [SlashCommand], query: String) -> [SlashCommand] {
        let needle = query.trimmingCharacters(in: .whitespaces)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        guard !needle.isEmpty else { return commands }
        return commands.filter {
            $0.command.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle)
                || $0.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle)
        }
    }

    /// « /commande » envoyé : la commande exacte, ou la seule qui corresponde.
    /// **Jamais lu par le Hub** : un texte en « / » n'est pas une demande.
    private func runSlash(_ text: String) async {
        let query = String(text.dropFirst())
        let all = slashCommands
        let matches = Self.slashMatches(all, query: query)
        let exact = all.first { $0.command.caseInsensitiveCompare(query) == .orderedSame }
        guard let command = exact ?? (matches.count == 1 ? matches.first : nil) else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotSlashNoMatch))
            return
        }
        await choose(command.suggestion)
    }

    static func title(of suggestion: Suggestion) -> String {
        switch suggestion {
        case .action(let kind, _): return title(of: kind)
        case .read(let tool):      return title(of: tool)
        case .reportProblem:       return FinanceStrings.copilotReportProblem
        case .refund:              return FinanceStrings.copilotRequestRefund
        case .reversal:            return FinanceStrings.copilotRequestReversal
        case .answerRequest:       return FinanceStrings.copilotAnswerRequest
        }
    }

    var currency: String { serverCurrency ?? "BIF" }
    private var serverCurrency: String?

    // MARK: - Chargement

    func load() async {
        await restoreConversation()
        if let session = surface.financeSession, case .success(let status) = await session.status() {
            serverCurrency = status.currency
        }
        switch await surface.catalog.copilotTools() {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let published):
            let admitted = published.compactMap { tool in Self.descriptor(for: tool).map { (tool, $0) } }
            await registry.replace(with: admitted.map(\.1), version: "hub")
            tools = admitted.map(\.0)
        }
    }

    /// Un outil du Hub dans le registre. Une opération que ce client ne sait
    /// pas classer n'y entre pas — elle ne sera donc jamais invoquée.
    static func descriptor(for tool: FinanceCopilotTool) -> CopilotToolDescriptor? {
        let scope: CopilotScope
        switch tool.operation {
        case "PREPARE":  scope = .prepare
        case "EXPLAIN":  scope = .explain
        case "READ":     scope = .read
        case "SIMULATE": scope = .simulate
        default:         return nil
        }
        return CopilotToolDescriptor(toolID: tool.name, version: tool.version ?? "", domain: tool.domain ?? "",
                                     requiredScopes: [scope], requiresConfirmation: true,
                                     requiresStepUp: false, idempotencyRequired: false)
    }

    // MARK: - Outils

    func invoke(_ tool: FinanceCopilotTool) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        append(.user(id: UUID(), text: Self.title(of: tool)))

        do {
            _ = try await registry.authorize(toolID: tool.name,
                                             requestedVersion: tool.version.flatMap { $0.isEmpty ? nil : $0 },
                                             context: Self.context())
        } catch {
            append(.notice(id: UUID(), text: FinanceStrings.copilotToolRefused))
            return
        }

        switch await surface.catalog.invokeCopilotTool(tool.name) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let reply):
            if let text = reply.message, !text.isEmpty {
                append(.copilot(id: UUID(), text: text, authoritative: reply.isAuthoritative))
            }
            let kind: FinanceEntryKind? = Self.kind(of: tool) == .invoice ? .invoice : (reply.kind ?? tool.kind)
            switch Self.followUp(for: reply, kind: kind) {
            case .none:              break
            case .lead(let kind):    await begin(kind, amount: nil, hint: nil)
            case .propose(let kind): propose(kind, amount: nil)
            }
        }
    }

    /// Ce que la réponse d'un outil permet ensuite.
    enum FollowUp: Equatable {
        /// Le message seul : le serveur n'a pas offert de suite.
        case none
        /// L'opération, menée dans le fil jusqu'au devis à confirmer.
        case lead(FinanceEntryKind)
        /// La carte « ouvrir et vérifier » — un parcours que le fil ne mène pas.
        case propose(FinanceEntryKind)
    }

    /// `nextSafeActions` décide de la suite (§8).
    ///
    /// - Vide (serveur antérieur) : comme avant — l'opération s'ouvre.
    /// - `CONFIRM_HUMAN` ou `OPEN_HUB` : le parcours du Hub. Dans cette app, il se
    ///   mène dans le fil et s'achève sur la confirmation humaine (Confirmer +
    ///   Face ID ou code) ; `OPEN_HUB` seul est la forme que publie le contrat.
    /// - Ni l'un ni l'autre : le message seul. Un code inconnu ne compte pas —
    ///   il n'ouvre rien, et ne s'affiche jamais.
    static func followUp(for reply: FinanceCopilotReply, kind: FinanceEntryKind?) -> FollowUp {
        guard let kind else { return .none }
        let actions = Set(reply.nextSafeActions.map { $0.uppercased() })
        if !actions.isEmpty, actions.isDisjoint(with: ["CONFIRM_HUMAN", "OPEN_HUB"]) { return .none }
        return ledInConversation.contains(kind) ? .lead(kind) : .propose(kind)
    }

    // MARK: - Saisie

    /// Ce que l'utilisateur tape va à l'étape en cours : un bénéficiaire, un
    /// montant, ou une demande nouvelle.
    func submit(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isWorking else { return }
        if text.hasPrefix("/") {
            await runSlash(text)
            return
        }
        switch step {
        case .recipient: await typedRecipient(text)
        case .amount:    await typedAmount(text)
        case .text:      await typedFieldValue(text)
        case .choice:
            // Une réponse tapée qui nomme une option la choisit ; sinon, une demande nouvelle.
            if let match = options.first(where: { $0.title.localizedCaseInsensitiveCompare(text) == .orderedSame }) {
                await choose(match)
            } else {
                abandonOperation()
                await read(text)
            }
        case .free:      await read(text)
        }
    }

    /// Une demande en texte libre : filtrée, puis lue par le Hub — **brouillon**.
    private func read(_ text: String) async {
        // Une demande nouvelle, même sans opération reconnue : la caméra s'arrête.
        closeScanners()
        isWorking = true
        defer { isWorking = false }
        append(.user(id: UUID(), text: text))

        guard let screened = await screen(text) else {
            append(.notice(id: UUID(), text: FinanceStrings.copilotTextRefused))
            return
        }
        switch await surface.catalog.draft(from: screened) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let draft):
            // Un brouillon (`draftOnly`) : les mots de Copilot, jamais un fait.
            if let message = draft.message, !message.isEmpty {
                append(.copilot(id: UUID(), text: message, authoritative: false))
            }
            guard let kind = draft.kind else {
                if draft.message == nil { append(.notice(id: UUID(), text: FinanceStrings.draftNoAction)) }
                return
            }
            await begin(kind, amount: draft.amount, hint: draft.counterpartyHint)
        }
    }

    /// `nil` : refusé. Sans filtre branché, pas de texte libre — les outils restent.
    private func screen(_ text: String) async -> String? {
        guard let filter = surface.promptFilter else { return nil }
        do {
            switch try await filter.validate(text) {
            case .safe(let input):                 return input
            case .suspicious(let sanitized, _, _): return sanitized.isEmpty ? nil : sanitized
            }
        } catch {
            return nil
        }
    }

    // MARK: - Mener une opération

    /// Ouvre une opération dans le fil. Celles que le fil ne mène pas encore
    /// gardent la carte « ouvrir et vérifier ».
    private func begin(_ kind: FinanceEntryKind, amount: Decimal?, hint: String?) async {
        closeOpenQuotes()
        // Le Hub ferme cette action : le motif du serveur, et rien ne démarre.
        if let reason = closedHubActions[kind] {
            operation = nil
            step = .free
            append(.notice(id: UUID(), text: reason))
            return
        }
        switch kind {
        case .sendMoney, .requestMoney:
            operation = Operation(kind: kind, amount: amount)
            recipientHint = hint
            await loadRecipientChoices()
            append(.question(id: UUID(), text: kind == .requestMoney
                             ? FinanceStrings.copilotAskRecipientRequest : FinanceStrings.copilotAskRecipientSend))
            step = .recipient
        case .payBill:
            operation = Operation(kind: kind, amount: amount)
            await beginBill()
        case .topUp:
            operation = Operation(kind: kind, amount: amount)
            recipientHint = hint
            await loadRecipientChoices(includingSelf: true)
            append(.question(id: UUID(), text: FinanceStrings.copilotAskTopUpNumber))
            step = .recipient
        case .qrPay:
            operation = Operation(kind: kind, amount: amount)
            step = .free
            append(.question(id: UUID(), text: FinanceStrings.copilotAskScan))
            append(.scanner(id: UUID(), state: .active))
        case .splitBill:
            operation = nil
            split = SplitFlow()
            options = []
            append(.question(id: UUID(), text: FinanceStrings.copilotSplitAskLabel))
            textPrompt = FinanceStrings.splitLabel
            textIsNumeric = false
            step = .text
        // Sans devis serveur, ces parcours gardent l'écran : la conversation ne
        // confirme qu'un devis.
        case .invoice where surface.merchantInvoices.providesQuotes:
            operation = Operation(kind: kind, amount: nil)
            askInvoiceReference()
        case .cashIn where surface.cashIn.providesQuotes:
            operation = Operation(kind: kind, amount: amount)
            await beginCashIn()
        case .cashOut where surface.cashOut.providesQuotes:
            operation = Operation(kind: kind, amount: amount)
            await beginCashOut()
        default:
            propose(kind, amount: amount)
        }
    }

    private func propose(_ kind: FinanceEntryKind, amount: Decimal?) {
        operation = nil
        step = .free
        append(.proposal(id: UUID(), Proposal(kind: kind, amount: amount, currency: amount == nil ? nil : currency)))
    }

    // MARK: - Facture (§5.1)

    /// Catégories du Biller Hub — le serveur filtre, l'app ne choisit rien.
    private func beginBill() async {
        isWorking = true
        defer { isWorking = false }
        switch await surface.bills.categories() {
        case .failure(let error):
            operation = nil
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let categories):
            let usable = categories.filter { !$0.billerForms.isEmpty }
            guard !usable.isEmpty else {
                operation = nil
                append(.notice(id: UUID(), text: FinanceStrings.billNoBiller))
                return
            }
            operation?.categories = usable
            operation?.stage = .billCategory
            ask(FinanceStrings.copilotAskBillCategory,
                options: usable.map { Option(id: $0.id, title: $0.name) })
        }
    }

    /// Une option choisie, selon l'étape de l'opération.
    func choose(_ option: Option) async {
        if dispute != nil, !isWorking, step == .choice {
            await chooseForDispute(option)
            return
        }
        if split != nil, !isWorking, step == .choice {
            await chooseForSplit(option)
            return
        }
        if cancellation != nil, !isWorking, step == .choice {
            await chooseForCancel(option)
            return
        }
        if answer != nil, !isWorking, step == .choice || step == .amount {
            await chooseForAnswer(option)
            return
        }
        if refund != nil, !isWorking, step == .choice || step == .amount {
            await chooseForRefund(option)
            return
        }
        if reversal != nil, !isWorking, step == .choice {
            await chooseForReversal(option)
            return
        }
        guard let current = operation, !isWorking, step == .choice || step == .text else { return }
        switch current.stage {
        case .billCategory:
            guard let category = current.categories.first(where: { $0.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            operation?.stage = .biller
            ask(FinanceStrings.copilotAskBiller,
                options: category.billerForms.map { Option(id: $0.billerFormId, title: $0.name) })
        case .biller:
            guard let biller = current.categories.flatMap(\.billerForms)
                    .first(where: { $0.billerFormId == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            await loadBillForm(biller)
        case .billField:
            await answerField(option.id == Self.skipOptionID ? "" : option.title, shown: option.title)
        case .topUpProduct:
            guard let product = current.products.first(where: { $0.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            operation?.product = product
            await quoteTopUp()
        case .cashChannel:
            if current.kind == .cashIn {
                guard let channel = current.cashInChannels.first(where: { $0.rawValue == option.id }) else { return }
                operation?.cashInChannel = channel
            } else {
                guard let channel = current.cashOutChannels.first(where: { $0.rawValue == option.id }) else { return }
                operation?.cashOutChannel = channel
            }
            append(.user(id: UUID(), text: option.title))
            options = []
            if current.amount != nil {
                isWorking = true
                defer { isWorking = false }
                await amountKnown()
            } else {
                askAmount()
            }
        case .cashInHandover:
            append(.user(id: UUID(), text: option.title))
            await confirmPhysical()
        case .cashOutAgent where option.id == Self.skipOptionID:
            await issueToken(agentID: "", shown: option.title)
        case .cashOutCode:
            append(.user(id: UUID(), text: option.title))
            await settleCashOut(option.id)
        case .none, .billAmount, .invoiceReference, .cashInAgent, .cashOutAgent:
            break
        }
    }

    private static let skipOptionID = "__skip"

    private func loadBillForm(_ biller: BillerForm) async {
        isWorking = true
        defer { isWorking = false }
        switch await surface.bills.form(for: biller.billerFormId) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let form):
            operation?.biller = biller
            // Les champs de l'écran facture : visibles, dans l'ordre du facturier.
            operation?.fields = PayBillView.visibleFields(of: form)
            operation?.fieldIndex = 0
            operation?.values = [:]
            await askNextField()
        }
    }

    /// Un champ à la fois. Plus aucun : la facture se lit au Biller Hub.
    private func askNextField() async {
        guard let current = operation else { return }
        guard current.fieldIndex < current.fields.count else {
            await lookupBill()
            return
        }
        let field = current.fields[current.fieldIndex]
        operation?.stage = .billField
        let label = field.isRequired ? field.label : "\(field.label) (\(FinanceStrings.optional))"
        let skip = field.isRequired ? [] : [Option(id: Self.skipOptionID, title: FinanceStrings.copilotSkip)]
        if !field.allowedValues.isEmpty {
            ask(label, options: field.allowedValues.map { Option(id: $0, title: $0) } + skip)
        } else {
            append(.question(id: UUID(), text: label))
            options = skip
            textPrompt = field.placeholder.isEmpty ? field.label : field.placeholder
            textIsNumeric = ["number", "numeric", "amount", "phone", "tel"].contains(field.inputType.lowercased())
            step = .text
        }
    }

    /// Une réponse libre : un champ de facture, une référence, un identifiant d'agent.
    private func typedFieldValue(_ text: String) async {
        if dispute?.stage == .description {
            await typedDisputeDescription(text)
            return
        }
        if reversal?.stage == .reason {
            await typedReversalReason(text)
            return
        }
        if split?.stage == .label || split?.stage == .values {
            await typedSplitText(text)
            return
        }
        switch operation?.stage {
        case .invoiceReference?: await lookupInvoice(text)
        case .cashInAgent?:      await verifyAgent(text)
        case .cashOutAgent?:     await issueToken(agentID: text, shown: text)
        default:                 await answerField(text, shown: text)
        }
    }

    /// La valeur passe la règle partagée (requis, longueurs, motif) avant d'être gardée.
    private func answerField(_ value: String, shown: String) async {
        guard let current = operation, current.stage == .billField,
              current.fieldIndex < current.fields.count else { return }
        let field = current.fields[current.fieldIndex]
        if !shown.isEmpty { append(.user(id: UUID(), text: shown)) }
        var values = current.values
        values[field.fieldName] = value
        if let message = Self.fieldError(field, value: value, values: values,
                                         validator: surface.billFieldValidator) {
            append(.notice(id: UUID(), text: message))
            return
        }
        operation?.values = values
        operation?.fieldIndex += 1
        await askNextField()
    }

    /// La raison du refus d'un champ — celle du facturier s'il en a rédigé une.
    static func fieldError(_ field: DynamicBillerField, value: String, values: [String: String],
                           validator: BillFieldValidating?) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        if field.isRequired && trimmed.isEmpty { return FinanceStrings.copilotFieldRequired }
        guard !trimmed.isEmpty, let validator,
              let issue = validator(field.requiringValue(), values) else { return nil }
        return field.message.isEmpty ? FinanceStrings.billFieldError(issue, label: field.label) : field.message
    }

    /// `POST /pay-bill/inquiry` — le dû, lu au Biller Hub. Le client ne l'invente pas.
    private func lookupBill() async {
        guard let current = operation, let biller = current.biller else { return }
        step = .free
        options = []
        isWorking = true
        defer { isWorking = false }
        switch await surface.bills.lookup(billerID: biller.billerFormId, fields: current.values) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            // On reprend le formulaire : un champ était sans doute en cause.
            operation?.fieldIndex = 0
            operation?.values = [:]
            await askNextField()
        case .success(let bill):
            operation?.bill = bill
            append(.bill(id: UUID(), BillCard(billerName: biller.name, customer: bill.customerLabel,
                                              amountDue: bill.amountDue, currency: bill.currency,
                                              dueDate: bill.dueDate)))
            if bill.allowsPartialPayment {
                operation?.stage = .billAmount
                append(.question(id: UUID(), text: FinanceStrings.copilotAskAmountBill))
                step = .amount
            } else {
                operation?.amount = bill.amountDue
                await quoteBill()
            }
        }
    }

    /// `POST /pay-bill/prepare` — un devis, jamais un débit.
    private func quoteBill() async {
        guard let current = operation, let bill = current.bill, let biller = current.biller else { return }
        let amount = current.amount ?? bill.amountDue
        guard bill.accepts(amount: amount) else {
            append(.notice(id: UUID(), text: FinanceStrings.sendMissingAmount))
            append(.question(id: UUID(), text: FinanceStrings.copilotAskAmountBill))
            step = .amount
            return
        }
        // Une facture appartient toujours à un dossier : le fil, ou le dossier personnel (§5.1.1).
        guard let conversationID = await operatingConversationID(), !conversationID.isEmpty else {
            append(.notice(id: UUID(), text: FinanceStrings.billNeedsConversation))
            return
        }
        // La portée de l'écran facture : relancé, le même devis.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("bill.pay", bill.reference.id, String(describing: amount)),
            deviceID: surface.deviceID)
        step = .free
        switch await surface.bills.quote(bill, amount: amount, conversationID: conversationID,
                                         idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: biller.name, state: .open,
                                                kind: .payBill, payeeID: bill.billerID)))
        }
    }

    // MARK: - Recharge (§5.3)

    /// Les produits ouverts pour ce numéro — l'opérateur est celui du serveur.
    private func loadTopUpProducts(for msisdn: String) async {
        isWorking = true
        defer { isWorking = false }
        step = .free
        switch await surface.topUp.catalog(for: msisdn) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            append(.question(id: UUID(), text: FinanceStrings.copilotAskTopUpNumber))
            step = .recipient
        case .success(let products) where products.isEmpty:
            append(.notice(id: UUID(), text: FinanceStrings.topUpNoProduct))
            operation = nil
        case .success(let products):
            operation?.products = products
            operation?.stage = .topUpProduct
            ask(FinanceStrings.copilotAskTopUpProduct(products.first?.operatorName ?? ""),
                options: products.map { Option(id: $0.id, title: Self.label(of: $0)) })
        }
    }

    static func label(of product: TopUpProduct) -> String {
        FinanceLocalization.string(product.labelKey, fallback: product.labelKey)
            + " · " + AmountEntry.format(product.amount, product.currency)
    }

    /// `POST /top-up/prepare` — un devis, jamais une recharge.
    private func quoteTopUp() async {
        guard let current = operation, let msisdn = current.msisdn, let product = current.product else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        options = []
        let conversationID = await operatingConversationID()
        // Une ligne au nom stable : relancée, la même clé — jamais une seconde recharge.
        let request = TopUpOrderRequest(
            lines: [TopUpLine(id: msisdn + "|" + product.id, msisdn: msisdn, productID: product.id)],
            conversationID: conversationID)
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("topup.order", String(describing: request)), deviceID: surface.deviceID)
        switch await surface.topUp.quote(request, idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: msisdn, state: .open,
                                                kind: .topUp, payeeID: msisdn)))
        }
    }

    // MARK: - QR (§5.2)

    /// Un code lu par la caméra du fil. La charge part **telle quelle** au
    /// serveur, avec un nonce neuf : un rejeu devient un refus, jamais un second débit.
    func scanned(_ scannerID: UUID, payload: String) async {
        guard !isWorking, operation?.kind == .qrPay,
              messages.contains(where: { if case .scanner(scannerID, .active) = $0 { return true }; return false })
        else { return }
        setScanner(scannerID, .scanned)
        isWorking = true
        defer { isWorking = false }

        // Lien de paiement : il s'inspecte et se paie par la demande, pas par le service QR.
        if PaymentLinkURL.read(payload) != nil {
            append(.notice(id: UUID(), text: FinanceStrings.copilotScanPaymentLink))
            append(.scanner(id: UUID(), state: .active))
            return
        }
        operation?.qrPayload = payload
        await quoteQR()
    }

    private func setScanner(_ id: UUID, _ state: ScannerState) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index] = .scanner(id: id, state: state)
        // « Lu » ou « fermé » : ce que le fil relira.
        persist(messages[index])
    }

    /// Une autre commande commence : la caméra s'arrête. Ouverte, elle lirait
    /// un code destiné à rien.
    private func closeScanners() {
        for message in messages {
            if case .scanner(let id, .active) = message { setScanner(id, .closed) }
        }
    }

    /// `POST /qr/prepare` (§5.2) — la charge du code, telle quelle. Le serveur
    /// lit le code, nomme le marchand et fixe le montant : le devis le dit.
    private func quoteQR() async {
        guard let payload = operation?.qrPayload else { return }
        step = .free
        let conversationID = await operatingConversationID()
        // Une clé par code lu : relu, le même code rend le même devis.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("qr.pay", payload), deviceID: surface.deviceID)
        switch await surface.qrResolver.quotePayment(payload: payload, conversationID: conversationID,
                                                     idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            append(.scanner(id: UUID(), state: .active))
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: "", state: .open,
                                                kind: .qrPay, payeeID: quote.reference.id)))
        }
    }

    // MARK: - Facture marchande (§5.2)

    private func askInvoiceReference() {
        operation?.stage = .invoiceReference
        append(.question(id: UUID(), text: FinanceStrings.copilotAskInvoiceReference))
        options = []
        textPrompt = FinanceStrings.copilotInvoiceReferencePlaceholder
        textIsNumeric = false
        step = .text
    }

    /// `POST /invoice/inquire` — le reste dû, lu au Merchant Backend.
    private func lookupInvoice(_ reference: String) async {
        append(.user(id: UUID(), text: reference))
        isWorking = true
        defer { isWorking = false }
        step = .free
        switch await surface.merchantInvoices.invoice(id: reference) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            askInvoiceReference()
        case .success(let invoice):
            showInvoice(invoice)
            guard invoice.isPayable() else {
                append(.notice(id: UUID(), text: FinanceStrings.invoiceNotPayable))
                operation = nil
                return
            }
            operation?.invoice = invoice
            await quoteInvoice()
        }
    }

    private func showInvoice(_ invoice: Invoice) {
        append(.bill(id: UUID(), BillCard(billerName: invoice.merchantNameKey, customer: invoice.number,
                                          amountDue: invoice.amountDue.majorUnitsForDisplay,
                                          currency: invoice.amountDue.currency.code,
                                          dueDate: invoice.dueAt, customerLabel: FinanceStrings.invoiceTitle)))
    }

    /// Revalidée, puis `POST /invoice/prepare` — le montant est celui du serveur.
    private func quoteInvoice() async {
        guard var invoice = operation?.invoice else { return }
        step = .free
        switch await surface.merchantInvoices.revalidate(invoice.snapshot()) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            operation = nil
            return
        case .success(.unchanged):
            break
        case .success(.mutated(_, let fresh)):
            // Le marchand a modifié la facture : la version à jour, relue avant le devis.
            append(.question(id: UUID(), text: FinanceStrings.copilotInvoiceChanged))
            showInvoice(fresh)
            guard fresh.isPayable() else {
                append(.notice(id: UUID(), text: FinanceStrings.invoiceNotPayable))
                operation = nil
                return
            }
            invoice = fresh
            operation?.invoice = fresh
        case .success(.cancelled(let reason)):
            append(.notice(id: UUID(), text: reason))
            operation = nil
            return
        case .success(.expired):
            append(.notice(id: UUID(), text: FinanceStrings.invoiceExpired))
            operation = nil
            return
        }
        // La portée de l'écran facture : la facture, réglée en entier.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("invoice.pay", invoice.id, String(describing: PaymentAllocation.full)),
            deviceID: surface.deviceID)
        let conversationID = await operatingConversationID()
        operation?.operatingID = conversationID
        switch await surface.merchantInvoices.quote(invoice, conversationID: conversationID,
                                                    idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            operation = nil
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: invoice.merchantNameKey, state: .open,
                                                kind: .invoice,
                                                payeeID: invoice.merchantID.isEmpty ? invoice.id : invoice.merchantID)))
        }
    }

    // MARK: - Dépôt (§6)

    private func beginCashIn() async {
        isWorking = true
        defer { isWorking = false }
        switch await surface.cashIn.availableChannels() {
        case .failure(let error):
            operation = nil
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let channels) where channels.isEmpty:
            operation = nil
            append(.notice(id: UUID(), text: FinanceStrings.cashInNoChannel))
        case .success(let channels):
            operation?.cashInChannels = channels
            operation?.stage = .cashChannel
            ask(FinanceStrings.copilotAskCashInChannel,
                options: channels.map { Option(id: $0.rawValue, title: FinanceStrings.cashInChannel($0.rawValue)) })
        }
    }

    /// `POST /cash-in/prepare` — un devis, jamais un dépôt lancé.
    private func quoteCashIn() async {
        guard let current = operation, let channel = current.cashInChannel, let amount = current.amount else { return }
        step = .free
        let conversationID = await operatingConversationID()
        operation?.operatingID = conversationID
        let request = CashInRequest(channel: channel, amount: amount, currency: currency,
                                    conversationID: conversationID)
        // La portée de l'écran de dépôt : relancé, le même devis.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("cashin.instruction", String(describing: request)),
            deviceID: surface.deviceID)
        switch await surface.cashIn.quote(request, idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            operation?.amount = nil
            askAmount()
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: FinanceStrings.cashInChannel(channel.rawValue),
                                                state: .open, kind: .cashIn, payeeID: channel.rawValue,
                                                recipientLabel: FinanceStrings.copilotChannel)))
        }
    }

    private func askAgentID(_ stage: Stage, question: String, prompt: String, skippable: Bool) {
        operation?.stage = stage
        append(.question(id: UUID(), text: question))
        options = skippable ? [Option(id: Self.skipOptionID, title: FinanceStrings.copilotSkip)] : []
        textPrompt = prompt
        textIsNumeric = false
        step = .text
    }

    /// `POST /cash-in/verify-agent` — `CF_037` si le serveur ne le reconnaît pas.
    private func verifyAgent(_ agentID: String) async {
        guard let reference = operation?.submitted else { return }
        append(.user(id: UUID(), text: agentID))
        isWorking = true
        defer { isWorking = false }
        step = .free
        switch await surface.cashIn.verifyAgent(reference, conversationID: operation?.operatingID, agentID: agentID) {
        case .success(let overlay) where overlay.agentVerified:
            append(.question(id: UUID(), text: FinanceStrings.cashInAgentVerified))
            operation?.stage = .cashInHandover
            ask(FinanceStrings.copilotAskCashInHandover,
                options: [Option(id: "handover", title: FinanceStrings.cashInConfirmPhysical)])
        case .success:
            askAgentID(.cashInAgent, question: FinanceStrings.copilotAskCashInAgent,
                       prompt: FinanceStrings.cashInAgentID, skippable: false)
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            askAgentID(.cashInAgent, question: FinanceStrings.copilotAskCashInAgent,
                       prompt: FinanceStrings.cashInAgentID, skippable: false)
        }
    }

    /// `POST /cash-in/confirm-physical` — l'agent a les espèces. **Pas un crédit**
    /// (`CF_038`) : tant que le serveur ne l'a pas crédité, le fil le dit.
    private func confirmPhysical() async {
        guard let reference = operation?.submitted else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        options = []
        switch await surface.cashIn.confirmPhysical(reference, conversationID: operation?.operatingID) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            ask(FinanceStrings.copilotAskCashInHandover,
                options: [Option(id: "handover", title: FinanceStrings.cashInConfirmPhysical)])
        case .success(let overlay):
            append(.question(id: UUID(), text: overlay.isCredited ? FinanceStrings.cashInCredited
                                                                 : FinanceStrings.cashInAwaitingCredit))
            operation = nil
        }
    }

    // MARK: - Retrait (§6)

    private func beginCashOut() async {
        isWorking = true
        defer { isWorking = false }
        switch await surface.cashOut.availableChannels() {
        case .failure(let error):
            operation = nil
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let channels) where channels.isEmpty:
            operation = nil
            append(.notice(id: UUID(), text: FinanceStrings.cashOutNoChannel))
        case .success(let channels):
            operation?.cashOutChannels = channels
            operation?.stage = .cashChannel
            ask(FinanceStrings.copilotAskCashOutChannel,
                options: channels.map { Option(id: $0.rawValue, title: FinanceStrings.cashOutChannel($0.rawValue)) })
        }
    }

    private static func cashOutScope(_ request: CashOutRequest) -> String {
        FinanceOperationKeys.scope("cashout.issue", request.channel.rawValue,
                                   request.amount, request.currency, request.conversationID ?? "")
    }

    private func cashOutRequest() -> CashOutRequest? {
        guard let channel = operation?.cashOutChannel, let amount = operation?.amount else { return nil }
        return CashOutRequest(channel: channel, amount: amount, currency: currency,
                              conversationID: operation?.operatingID)
    }

    /// `POST /cash-out/prepare` — un devis, jamais un retrait.
    private func quoteCashOut() async {
        operation?.operatingID = await operatingConversationID()
        guard let request = cashOutRequest() else { return }
        step = .free
        // La portée de l'écran de retrait : relancé, le même devis.
        let idempotency = await surface.operationKeys.key(for: Self.cashOutScope(request), deviceID: surface.deviceID)
        switch await surface.cashOut.quote(request, idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            operation?.amount = nil
            askAmount()
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote,
                                                recipientName: FinanceStrings.cashOutChannel(request.channel.rawValue),
                                                state: .open, kind: .cashOut, payeeID: request.channel.rawValue,
                                                recipientLabel: FinanceStrings.copilotChannel)))
        }
    }

    /// `POST /cash-out/token` — **émis par Finance**, rendu une seule fois.
    private func issueToken(agentID: String, shown: String) async {
        guard let reference = operation?.submitted else { return }
        append(.user(id: UUID(), text: shown))
        isWorking = true
        defer { isWorking = false }
        step = .free
        options = []
        switch await surface.cashOut.issueToken(reference, conversationID: operation?.operatingID, agentID: agentID) {
        case .failure(let error):
            // `CF_051` : Finance non câblé — aucun code, et surtout pas un local.
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            askAgentID(.cashOutAgent, question: FinanceStrings.copilotAskCashOutAgent,
                       prompt: FinanceStrings.cashOutAgentID, skippable: true)
        case .success(let token):
            append(.question(id: UUID(), text: FinanceStrings.copilotCashOutCodeReady))
            append(.cashOutCode(id: UUID(), token))
            operation?.stage = .cashOutCode
            askCashOutSettlement()
        }
    }

    private func askCashOutSettlement() {
        options = [Option(id: "remit", title: FinanceStrings.cashOutConfirmRemittance),
                   Option(id: "revoke", title: FinanceStrings.cashOutRevoke),
                   Option(id: "incident", title: FinanceStrings.cashOutReportIncident)]
        step = .choice
    }

    /// Remise constatée, code révoqué ou incident : aucun n'est une finalité
    /// financière — le ledger appartient à Finance, et se lit sur la carte.
    private func settleCashOut(_ action: String) async {
        guard let reference = operation?.submitted else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        let conversationID = operation?.operatingID
        let result: Result<CashOutTokenOverlay, FinanceError>
        switch action {
        case "remit":    result = await surface.cashOut.confirmRemittance(reference, conversationID: conversationID)
        case "revoke":   result = await surface.cashOut.revokeToken(reference, conversationID: conversationID)
        case "incident": result = await surface.cashOut.reportIncident(reference, conversationID: conversationID)
        default:         return
        }
        switch result {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            askCashOutSettlement()
        case .success(let overlay):
            append(.question(id: UUID(), text: Self.caption(of: overlay)))
            operation = nil
            options = []
        }
    }

    static func caption(of overlay: CashOutTokenOverlay) -> String {
        if overlay.incidentOpened { return FinanceStrings.cashOutIncidentOpened }
        if overlay.revoked { return FinanceStrings.cashOutRevoked }
        if overlay.remittedAt != nil { return FinanceStrings.cashOutRemitted }
        return FinanceStrings.cashOutAwaitingSettlement
    }

    /// Soumis : chez un agent, le parcours continue dans le fil.
    private func continueAfterSubmission(_ reference: FinancialReference) async {
        switch operation?.kind {
        case .cashIn? where operation?.cashInChannel == .agent:
            operation?.submitted = reference
            askAgentID(.cashInAgent, question: FinanceStrings.copilotAskCashInAgent,
                       prompt: FinanceStrings.cashInAgentID, skippable: false)
        case .cashOut?:
            // L'émission confirmée libère la clé : un second retrait identique,
            // plus tard, est une opération nouvelle.
            if let request = cashOutRequest() { await surface.operationKeys.release(Self.cashOutScope(request)) }
            operation?.submitted = reference
            askAgentID(.cashOutAgent, question: FinanceStrings.copilotAskCashOutAgent,
                       prompt: FinanceStrings.cashOutAgentID, skippable: true)
        default:
            operation = nil
        }
    }

    // MARK: - Signaler un problème (litige)

    private static let disputeDeclineID = "__decline"

    /// Les opérations de cette conversation — celles dont une carte est à l'écran —,
    /// la plus récente d'abord. Rien d'autre à contester ici.
    private func beginDispute() async {
        closeOpenQuotes()
        operation = nil
        var seen = Set<String>()
        let candidates = messages.reversed().compactMap { message -> FinancialReference? in
            guard case .outcome(_, let reference) = message, reference.type != .dispute,
                  seen.insert(reference.id).inserted else { return nil }
            return reference
        }
        // Seul le serveur dit ce qui se conteste : `OPEN_DISPUTE` dans les actions de la carte.
        var references: [FinancialReference] = []
        for reference in candidates.prefix(8) where await allowsDispute(reference) {
            references.append(reference)
        }
        guard !references.isEmpty else {
            append(.notice(id: UUID(), text: FinanceStrings.copilotDisputeNoOperation))
            return
        }
        dispute = DisputeFlow(references: Array(references.prefix(5)))
        if references.count == 1 {
            dispute?.reference = references[0]
            await askDisputeCategory()
        } else {
            dispute?.stage = .operation
            ask(FinanceStrings.copilotDisputePickOperation,
                options: dispute?.references.map { Option(id: $0.id, title: Self.title(ofOperation: $0)) } ?? [])
        }
    }

    /// Depuis le lien sous la carte d'une opération : le motif est demandé aussitôt,
    /// l'opération étant déjà choisie.
    func reportProblem(on reference: FinancialReference) async {
        guard !isWorking else { return }
        abandonOperation()
        append(.user(id: UUID(), text: FinanceStrings.copilotReportProblem))
        dispute = DisputeFlow(references: [reference])
        dispute?.reference = reference
        await askDisputeCategory()
    }

    private static func title(ofOperation reference: FinancialReference) -> String {
        "\(reference.type.rawValue) · \(reference.id.suffix(8))"
    }

    /// `OPEN_DISPUTE` dans les `allowedActions` que le serveur a posées sur la carte.
    private func allowsDispute(_ reference: FinancialReference) async -> Bool {
        var payload = await surface.objectReader?.current(for: reference)
        if payload == nil, case .success(let fresh)? = await surface.objectReader?.refresh(reference) {
            payload = fresh
        }
        return payload != nil && DisputeEligibility.allows(payload?.allowedActions)
    }

    /// Les catégories **du serveur** — jamais une liste de l'app. Illisibles : rien ne se devine.
    private func askDisputeCategory() async {
        isWorking = true
        defer { isWorking = false }
        switch await surface.disputes.categories() {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            dispute = nil
        case .success(let categories) where categories.isEmpty:
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(.capabilityUnavailable)))
            dispute = nil
        case .success(let categories):
            dispute?.stage = .category
            ask(FinanceStrings.copilotDisputePickReason,
                options: categories.map { Option(id: $0, title: FinanceStrings.disputeCategoryLabel($0)) })
        }
    }

    private func chooseForDispute(_ option: Option) async {
        guard let current = dispute else { return }
        switch current.stage {
        case .operation:
            guard let reference = current.references.first(where: { $0.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            dispute?.reference = reference
            await askDisputeCategory()
        case .category:
            append(.user(id: UUID(), text: option.title))
            dispute?.category = option.id
            dispute?.stage = .description
            options = []
            append(.question(id: UUID(), text: FinanceStrings.copilotDisputeAskDescription))
            textPrompt = FinanceStrings.disputeDescription
            textIsNumeric = false
            step = .text
        case .consent:
            append(.user(id: UUID(), text: option.title))
            if option.id == Self.disputeDeclineID {
                dispute = nil
                options = []
                step = .free
                append(.notice(id: UUID(), text: FinanceStrings.copilotCancelled))
            } else {
                await fileDispute()
            }
        case .description:
            break
        }
    }

    private func typedDisputeDescription(_ text: String) async {
        append(.user(id: UUID(), text: text))
        dispute?.description = text
        dispute?.stage = .consent
        // Le dossier part chez un tiers : un consentement explicite, jamais présumé.
        ask(FinanceStrings.disputeConsent,
            options: [Option(id: "agree", title: FinanceStrings.copilotDisputeAgree),
                      Option(id: Self.disputeDeclineID, title: FinanceStrings.copilotDisputeDecline)])
    }

    /// `POST /disputes` — la même ouverture que l'écran du litige.
    private func fileDispute() async {
        guard let current = dispute, let reference = current.reference, let category = current.category else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        options = []
        // Le statut observé : celui de la carte, relu au serveur si besoin.
        var observed = await surface.objectReader?.current(for: reference)?.status
        if observed == nil, case .success(let fresh)? = await surface.objectReader?.refresh(reference) {
            observed = fresh.status
        }
        guard let observed else {
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(.networkUnavailable)))
            dispute = nil
            return
        }
        let draft = DisputeDraft(reference: reference, description: current.description,
                                 correlationID: reference.correlationID, observedStatus: observed,
                                 conversationID: await operatingConversationID(), sharingConsent: true,
                                 category: category)
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("dispute.file", String(describing: draft)), deviceID: surface.deviceID)
        switch await surface.disputes.file(draft, idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let filed):
            append(.question(id: UUID(), text: FinanceStrings.copilotDisputeFiled))
            append(.outcome(id: UUID(), filed))
        }
        dispute = nil
    }

    // MARK: - Partage d'addition (§4)

    private func typedSplitText(_ text: String) async {
        guard let current = split else { return }
        append(.user(id: UUID(), text: text))
        switch current.stage {
        case .label:
            split?.label = text.trimmingCharacters(in: .whitespacesAndNewlines)
            split?.stage = .total
            append(.question(id: UUID(), text: FinanceStrings.copilotSplitAskTotal))
            step = .amount
        case .values:
            guard let value = SplitStrategyInput.decimal(text), value > 0,
                  current.valueIndex < current.participants.count else {
                append(.notice(id: UUID(), text: FinanceStrings.copilotAmountInvalid))
                return
            }
            split?.strategy.values[current.participants[current.valueIndex].userId] = text
            split?.valueIndex += 1
            askNextSplitValue()
        default:
            break
        }
    }

    private func typedSplitTotal(_ text: String) async {
        guard let amount = Self.amount(in: text), amount > 0 else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotAmountInvalid))
            return
        }
        append(.user(id: UUID(), text: AmountEntry.format(amount, currency)))
        split?.total = amount
        isWorking = true
        defer { isWorking = false }
        // Les contacts que l'on peut inviter : la règle de la diffusion.
        split?.candidates = await surface.splitSharing.participantCandidates().filter { !$0.userId.isEmpty }
        guard split?.candidates.isEmpty == false else {
            append(.notice(id: UUID(), text: FinanceStrings.splitParticipantsFirst))
            split = nil
            step = .free
            return
        }
        split?.stage = .participants
        askSplitParticipants()
    }

    private static let splitDone = "__done"

    private func askSplitParticipants() {
        guard let current = split else { return }
        let chosen = Set(current.participants.map(\.userId))
        var choices = current.candidates.filter { !chosen.contains($0.userId) }
            .map { Option(id: $0.userId, title: $0.name, detail: $0.phone) }
        if !current.participants.isEmpty {
            choices.insert(Option(id: Self.splitDone, title: FinanceStrings.splitParticipantsDone), at: 0)
        }
        let names = current.participants.map(\.name).joined(separator: ", ")
        ask(names.isEmpty ? FinanceStrings.copilotSplitPickParticipants
                          : FinanceStrings.copilotSplitAddMore(names), options: choices)
    }

    private func chooseForSplit(_ option: Option) async {
        guard let current = split else { return }
        switch current.stage {
        case .participants:
            if option.id == Self.splitDone {
                append(.user(id: UUID(), text: option.title))
                split?.stage = .strategy
                ask(FinanceStrings.copilotSplitAskStrategy,
                    options: SplitStrategyInput.Kind.allCases.map {
                        Option(id: $0.rawValue, title: Self.strategyTitle($0))
                    })
            } else if let contact = current.candidates.first(where: { $0.userId == option.id }) {
                append(.user(id: UUID(), text: option.title))
                split?.participants.append(contact)
                askSplitParticipants()
            }
        case .strategy:
            guard let kind = SplitStrategyInput.Kind(rawValue: option.id) else { return }
            append(.user(id: UUID(), text: option.title))
            split?.strategy.kind = kind
            if kind == .equal {
                askSplitPrivacy()
            } else {
                split?.stage = .values
                split?.valueIndex = 0
                askNextSplitValue()
            }
        case .privacy:
            let scope: SplitPrivacyScope
            switch option.id {
            case "aggregate": scope = .aggregateOnly
            case "open":      scope = .openToAll
            default:          scope = .ownShareOnly
            }
            append(.user(id: UUID(), text: option.title))
            split?.privacy = scope
            split?.stage = .confirm
            askSplitConfirm()
        case .confirm:
            append(.user(id: UUID(), text: option.title))
            options = []
            step = .free
            guard option.id == "create" else {
                split = nil
                append(.notice(id: UUID(), text: FinanceStrings.copilotCancelled))
                return
            }
            await createSplit()
        case .label, .total, .values:
            break
        }
    }

    private static func strategyTitle(_ kind: SplitStrategyInput.Kind) -> String {
        switch kind {
        case .equal:        return FinanceStrings.splitStrategyEqual
        case .custom:       return FinanceStrings.splitStrategyCustom
        case .proportional: return FinanceStrings.splitStrategyProportional
        }
    }

    private func askNextSplitValue() {
        guard let current = split else { return }
        guard current.valueIndex < current.participants.count else {
            askSplitPrivacy()
            return
        }
        let person = current.participants[current.valueIndex]
        let custom = current.strategy.kind == .custom
        options = []
        append(.question(id: UUID(), text: custom ? FinanceStrings.copilotSplitAskAmountFor(person.name)
                                                  : FinanceStrings.copilotSplitAskWeightFor(person.name)))
        textPrompt = person.name
        textIsNumeric = true
        step = .text
    }

    private func askSplitPrivacy() {
        split?.stage = .privacy
        ask(FinanceStrings.splitPrivacy,
            options: [Option(id: "own", title: FinanceStrings.splitPrivacyOwn),
                      Option(id: "aggregate", title: FinanceStrings.splitPrivacyAggregate),
                      Option(id: "open", title: FinanceStrings.splitPrivacyOpen)])
    }

    /// Le récapitulatif — ce que l'utilisateur confirme avant que rien ne parte.
    private func askSplitConfirm() {
        guard let current = split, let total = current.total else { return }
        ask(FinanceStrings.copilotSplitSummary(current.label, AmountEntry.format(total, currency),
                                               current.participants.map(\.name).joined(separator: ", ")),
            options: [Option(id: "create", title: FinanceStrings.copilotSplitCreate),
                      Option(id: "cancel", title: FinanceStrings.copilotDisputeDecline)])
    }

    /// `POST /split-bill` — le serveur répartit, arrondis compris ; puis chaque participant le reçoit.
    private func createSplit() async {
        guard let current = split, let total = current.total,
              let declared = current.strategy.strategy(for: current.participants.map(\.userId)) else {
            append(.notice(id: UUID(), text: FinanceStrings.sendMissingAmount))
            split = nil
            return
        }
        isWorking = true
        defer { isWorking = false }
        let draft = SplitBillDraft(
            labelKey: current.label,
            total: Money(minorUnits: NSDecimalNumber(decimal: total).int64Value,
                         currency: CurrencyCode(code: currency, exponent: 0)),
            participantIDs: current.participants.map(\.userId),
            strategy: declared, privacyScope: current.privacy,
            conversationID: await operatingConversationID())
        // Relancé : le même brouillon rend le même partage, jamais un second.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("split.create", String(describing: draft)), deviceID: surface.deviceID)
        switch await surface.splitBills.create(draft, idempotency: idempotency) {
        case .failure(let error):
            // `CF_041` : la somme des parts ne fait pas le total.
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let created):
            append(.question(id: UUID(), text: FinanceStrings.copilotSplitCreated))
            let report = await surface.splitSharing.share(created, correlationID: idempotency.correlationID,
                                                          with: current.participants)
            if !report.isComplete {
                let missed = current.participants.filter { report.failed.contains($0.userId) }.map(\.name)
                append(.notice(id: UUID(), text: FinanceStrings.splitShareIncomplete + " " + missed.joined(separator: ", ")))
            }
        }
        split = nil
    }

    // MARK: - Rembourser ou demander l'extourne (Phase 10)

    /// La carte lue au serveur — l'état connu, sinon une lecture.
    private func cardPayload(for reference: FinancialReference) async -> FinancialCardPayload? {
        var payload = await surface.objectReader?.current(for: reference)
        if payload == nil, case .success(let fresh)? = await surface.objectReader?.refresh(reference) {
            payload = fresh
        }
        return payload
    }

    /// Les opérations de cette conversation que **le serveur** autorise pour `action`
    /// (`allowedActions`), la plus récente d'abord. Aucune règle locale sur le type.
    private func eligibleReferences(allowing action: String) async -> [FinancialReference] {
        await eligibleReferences { $0?.allowedActions?.contains(action) == true }
    }

    private func eligibleReferences(where allows: (FinancialCardPayload?) -> Bool) async -> [FinancialReference] {
        var seen = Set<String>()
        let candidates = messages.reversed().compactMap { message -> FinancialReference? in
            guard case .outcome(_, let reference) = message, reference.type != .dispute,
                  seen.insert(reference.id).inserted else { return nil }
            return reference
        }
        var eligible: [FinancialReference] = []
        for reference in candidates.prefix(8) {
            if allows(await cardPayload(for: reference)) { eligible.append(reference) }
        }
        return eligible
    }

    private func beginRefund() async {
        closeOpenQuotes()
        operation = nil
        let references = await eligibleReferences(where: Self.allowsRefundOrReversal)
        guard !references.isEmpty else {
            append(.notice(id: UUID(), text: FinanceStrings.copilotNothingToRefund))
            return
        }
        refund = RefundFlow(references: Array(references.prefix(5)))
        if references.count == 1 {
            await chooseRefundOperation(references[0])
        } else {
            ask(FinanceStrings.copilotRefundPickOperation,
                options: references.prefix(5).map { Option(id: $0.id, title: Self.title(ofOperation: $0)) })
        }
    }

    /// Depuis le lien sous la carte : l'opération est choisie.
    func requestRefund(on reference: FinancialReference) async {
        guard !isWorking else { return }
        abandonOperation()
        append(.user(id: UUID(), text: FinanceStrings.copilotRequestRefund))
        refund = RefundFlow(references: [reference])
        await chooseRefundOperation(reference)
    }

    private func chooseRefundOperation(_ reference: FinancialReference) async {
        guard let payload = await cardPayload(for: reference) else {
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(.networkUnavailable)))
            refund = nil
            return
        }
        refund?.reference = reference
        refund?.original = payload.amount
        refund?.currency = payload.currency
        refund?.stage = .amount
        // Le montant de l'opération vient de la carte du serveur ; le total en une touche.
        let full = AmountEntry.format(payload.amount, payload.currency)
        options = [Option(id: "full", title: FinanceStrings.copilotRefundFull(full))]
        append(.question(id: UUID(), text: FinanceStrings.copilotRefundAskAmount(full)))
        step = .amount
    }

    private func chooseForRefund(_ option: Option) async {
        guard let current = refund else { return }
        switch current.stage {
        case .operation:
            guard let reference = current.references.first(where: { $0.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            await chooseRefundOperation(reference)
        case .amount:
            guard option.id == "full" else { return }
            append(.user(id: UUID(), text: option.title))
            refund?.amount = current.original
            options = []
            await quoteRefund()
        }
    }

    private func typedRefundAmount(_ text: String) async {
        guard let amount = Self.amount(in: text), amount > 0 else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotAmountInvalid))
            return
        }
        append(.user(id: UUID(), text: AmountEntry.format(amount, refund?.currency ?? currency)))
        refund?.amount = amount
        options = []
        await quoteRefund()
    }

    /// `POST /refund` — un devis, jamais un crédit ; le montant est celui que l'utilisateur a choisi.
    private func quoteRefund() async {
        guard let current = refund, let reference = current.reference, let amount = current.amount else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("refund.prepare", reference.id, String(describing: amount)),
            deviceID: surface.deviceID)
        switch await surface.reversals.quoteRefund(of: reference, amount: amount, currency: current.currency,
                                                   conversationID: await operatingConversationID(),
                                                   idempotency: idempotency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            refund = nil
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: "", state: .open, kind: .sendMoney,
                                                payeeID: reference.id,
                                                titleOverride: FinanceStrings.copilotRefundTitle)))
        }
    }

    // MARK: - Répondre à une demande reçue

    private func beginAnswer() async {
        closeOpenQuotes()
        operation = nil
        guard let responder = surface.requestResponder, let host else { return }
        isWorking = true
        var open: [MoneyRequestOverlay] = []
        for reference in host.receivedRequests().prefix(10) {
            // Le serveur dit ce qui reste faisable ; une demande déjà réglée n'est pas proposée.
            if case .success(let overlay) = await responder.overlay(for: reference),
               overlay.canPay || overlay.canDecline { open.append(overlay) }
        }
        isWorking = false
        guard !open.isEmpty else {
            append(.notice(id: UUID(), text: FinanceStrings.copilotAnswerNone))
            return
        }
        answer = AnswerFlow(requests: Array(open.prefix(5)))
        if open.count == 1 {
            askAnswerAction(open[0])
        } else {
            ask(FinanceStrings.copilotAnswerPick,
                options: open.prefix(5).map { Option(id: $0.reference.id, title: Self.title(ofRequest: $0)) })
        }
    }

    private static func title(ofRequest overlay: MoneyRequestOverlay) -> String {
        guard let amount = overlay.myRemaining ?? overlay.requestedTotal else { return FinanceStrings.requestPayTitle }
        return AmountEntry.format(amount, overlay.currency)
    }

    private func askAnswerAction(_ overlay: MoneyRequestOverlay) {
        answer?.request = overlay
        answer?.stage = .action
        var choices: [Option] = []
        if overlay.canPay { choices.append(Option(id: "pay", title: FinanceStrings.requestActionPay)) }
        if overlay.canDecline { choices.append(Option(id: "decline", title: FinanceStrings.requestActionDecline)) }
        ask(FinanceStrings.copilotAnswerAsk(Self.title(ofRequest: overlay)), options: choices)
    }

    private func chooseForAnswer(_ option: Option) async {
        guard let current = answer else { return }
        switch current.stage {
        case .request:
            guard let overlay = current.requests.first(where: { $0.reference.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            askAnswerAction(overlay)
        case .action:
            guard let overlay = current.request else { return }
            append(.user(id: UUID(), text: option.title))
            if option.id == "decline" {
                answer?.stage = .confirmDecline
                ask(FinanceStrings.requestDeclineTitle + " " + FinanceStrings.requestDeclineDetail,
                    options: [Option(id: "decline", title: FinanceStrings.requestActionDecline),
                              Option(id: "keep", title: FinanceStrings.copilotAnswerKeep)])
            } else if overlay.amountMode == .free {
                // Montant libre : le payeur le choisit.
                answer?.stage = .amount
                options = []
                append(.question(id: UUID(), text: FinanceStrings.requestPayAmountHint))
                step = .amount
            } else {
                options = []
                await quoteAnswer()
            }
        case .amount:
            return
        case .confirmDecline:
            guard let overlay = current.request else { return }
            append(.user(id: UUID(), text: option.title))
            options = []
            step = .free
            answer = nil
            guard option.id == "decline" else { return }
            isWorking = true
            defer { isWorking = false }
            switch await surface.requestResponder?.decline(overlay.reference, conversationID: await operatingConversationID())
                ?? .failure(.capabilityUnavailable) {
            case .success:
                await surface.requestResponder?.forget(overlay.reference)
                _ = await surface.objectReader?.refresh(overlay.reference)
                NotificationCenter.default.post(name: .financeRequestDidChange, object: overlay.reference.id)
                append(.question(id: UUID(), text: FinanceStrings.copilotAnswerDeclined))
            case .failure(let error):
                append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            }
        }
    }

    private func typedAnswerAmount(_ text: String) async {
        guard let amount = Self.amount(in: text), amount > 0 else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotAmountInvalid))
            return
        }
        append(.user(id: UUID(), text: AmountEntry.format(amount, answer?.request?.currency ?? currency)))
        answer?.amount = amount
        await quoteAnswer()
    }

    /// `POST /request-money/pay` — un devis, comme un envoi ; rien ne part sans confirmation.
    private func quoteAnswer() async {
        guard let current = answer, let overlay = current.request, let responder = surface.requestResponder else { return }
        isWorking = true
        defer { isWorking = false }
        step = .free
        switch await responder.pay(overlay.reference, conversationID: overlay.conversationID ?? host?.conversationID,
                                   amount: current.amount, currency: overlay.currency) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            answer = nil
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: "", state: .open, kind: .sendMoney,
                                                payeeID: overlay.reference.id,
                                                titleOverride: FinanceStrings.requestPayTitle)))
        }
    }

    /// Depuis le lien sous la carte : la confirmation d'abord, rien ne part avant.
    func requestCancel(on reference: FinancialReference) async {
        guard !isWorking else { return }
        abandonOperation()
        append(.user(id: UUID(), text: FinanceStrings.actionsCancel))
        cancellation = reference
        ask(FinanceStrings.actionsCancelConfirm,
            options: [Option(id: "cancel", title: FinanceStrings.actionsCancel),
                      Option(id: "keep", title: FinanceStrings.copilotCancelKeep)])
    }

    private func chooseForCancel(_ option: Option) async {
        guard let reference = cancellation else { return }
        append(.user(id: UUID(), text: option.title))
        options = []
        step = .free
        cancellation = nil
        guard option.id == "cancel" else { return }
        isWorking = true
        defer { isWorking = false }
        // `POST /intent/cancel-request`, puis la carte relue. Déjà soumis : la demande
        // est **enregistrée, pas faite** (`CF_046`) — le fil le dit.
        switch await surface.objectReader?.cancel(reference, conversationID: await operatingConversationID())
            ?? .failure(.capabilityUnavailable) {
        case .success(.cancelled): append(.question(id: UUID(), text: FinanceStrings.cancelDone))
        case .success(.requested): append(.question(id: UUID(), text: FinanceStrings.cancelRequested))
        case .failure(let error):  append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        }
    }

    /// `POST /request-money/payment-link` — un lien pour une demande d'argent déjà
    /// envoyée. Il ne donne que le contexte : le payeur consent et confirme de son côté.
    func issuePaymentLink(for reference: FinancialReference) async {
        guard !isWorking, let responder = surface.requestResponder else { return }
        isWorking = true
        defer { isWorking = false }
        switch await responder.issueLink(for: reference, conversationID: await operatingConversationID()) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let link):
            guard let url = PaymentLinkURL.make(token: link.token, nonce: link.nonce) else {
                append(.notice(id: UUID(), text: FinanceStrings.errorMessage(.providerUnavailable)))
                return
            }
            append(.paymentLink(id: UUID(), url: url.absoluteString, expiresAt: link.expiresAt))
        }
    }

    /// Le lien ne s'offre que pour une demande d'argent, quand un répondeur est branché.
    var canIssuePaymentLinks: Bool { surface.requestResponder != nil }

    /// La carte du reçu ne se publie que dans une vraie conversation.
    var canShareReceipts: Bool { host != nil }

    /// `POST /receipt/share` — depuis le lien sous la carte, quand le serveur liste `SHARE_RECEIPT`.
    func shareReceipt(of reference: FinancialReference) async {
        guard !isWorking, let conversationID = host?.conversationID, !conversationID.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        switch await surface.receipts.postInConversation(reference, conversationID: conversationID) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success:
            append(.question(id: UUID(), text: FinanceStrings.copilotReceiptShared))
        }
    }

    private func beginReversal() async {
        closeOpenQuotes()
        operation = nil
        let references = await eligibleReferences(where: Self.allowsRefundOrReversal)
        guard !references.isEmpty else {
            append(.notice(id: UUID(), text: FinanceStrings.copilotNothingToReverse))
            return
        }
        reversal = ReversalFlow(references: Array(references.prefix(5)))
        if references.count == 1 {
            reversal?.reference = references[0]
            askReversalReason()
        } else {
            ask(FinanceStrings.copilotReversalPickOperation,
                options: references.prefix(5).map { Option(id: $0.id, title: Self.title(ofOperation: $0)) })
        }
    }

    func requestReversal(on reference: FinancialReference) async {
        guard !isWorking else { return }
        abandonOperation()
        append(.user(id: UUID(), text: FinanceStrings.copilotRequestReversal))
        reversal = ReversalFlow(references: [reference])
        reversal?.reference = reference
        askReversalReason()
    }

    private func askReversalReason() {
        reversal?.stage = .reason
        options = []
        append(.question(id: UUID(), text: FinanceStrings.copilotReversalAskReason))
        textPrompt = FinanceStrings.disputeDescription
        textIsNumeric = false
        step = .text
    }

    private func typedReversalReason(_ text: String) async {
        append(.user(id: UUID(), text: text))
        reversal?.reason = text
        reversal?.stage = .confirm
        // Finance exécute : l'utilisateur confirme qu'il veut bien la demande.
        ask(FinanceStrings.copilotReversalConfirm,
            options: [Option(id: "send", title: FinanceStrings.copilotReversalSend),
                      Option(id: "cancel", title: FinanceStrings.copilotDisputeDecline)])
    }

    private func chooseForReversal(_ option: Option) async {
        guard let current = reversal else { return }
        switch current.stage {
        case .operation:
            guard let reference = current.references.first(where: { $0.id == option.id }) else { return }
            append(.user(id: UUID(), text: option.title))
            reversal?.reference = reference
            askReversalReason()
        case .confirm:
            append(.user(id: UUID(), text: option.title))
            options = []
            step = .free
            guard option.id == "send", let reference = current.reference else {
                reversal = nil
                append(.notice(id: UUID(), text: FinanceStrings.copilotCancelled))
                return
            }
            await sendReversal(of: reference, reason: current.reason)
        case .reason:
            break
        }
    }

    /// `POST /reversal/request` — une demande : Finance exécute, rien n'est annulé ici.
    private func sendReversal(of reference: FinancialReference, reason: String) async {
        isWorking = true
        defer { isWorking = false }
        // Chat Core refuse un `conversationId` vide (« Validation failed ») : le fil,
        // ou le dossier personnel hors conversation (§5.1.1).
        switch await surface.reversals.requestReversal(of: reference, conversationID: await operatingConversationID(),
                                                       reason: reason) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let requested):
            // Les mots du serveur d'abord ; les nôtres seulement s'il n'en a pas.
            if let message = requested.message, !message.isEmpty {
                append(.copilot(id: UUID(), text: message, authoritative: false))
            } else {
                append(.question(id: UUID(), text: FinanceStrings.copilotReversalRequested))
            }
        }
        reversal = nil
    }

    // MARK: - Fil de l'opération et annonce

    /// L'interlocuteur : ce fil. Un contact : son fil direct — même dans un
    /// groupe. Un numéro tapé : aucun.
    private func destination(for target: RecipientTarget) async -> Destination {
        switch target {
        case .peer:
            return host == nil ? .none : .thread
        case .contact(let contact):
            // Sans annonce directe branchée, le fil d'origine — comme avant.
            guard let directMessaging else { return host == nil ? .none : .thread }
            return .direct(await directMessaging.recipient(for: contact))
        case .typed:
            return .none
        }
    }

    /// L'utilisateur Chat derrière le bénéficiaire résolu. Sans lui, l'acteur
    /// porte le jeton (`LiveSendMoney`) : pas d'identité de messagerie.
    private static func chatUserID(of resolved: ResolvedRecipient) -> String? {
        let id = resolved.actor.actorID
        return id.isEmpty || id == resolved.recipientID ? nil : id
    }

    /// Une opération sans bénéficiaire (facture, recharge…) s'annonce dans le fil d'origine.
    private func announceDestination(_ operation: Operation?) -> Destination {
        operation?.destination ?? (host == nil ? .none : .thread)
    }

    /// Le fil que porte le prepare d'un envoi ou d'une demande — **jamais
    /// aucun** : `send-money/prepare` l'exige. Un fil direct encore inexistant
    /// porte l'identifiant fabriqué au choix ; sans identité de messagerie, le
    /// dossier personnel (§5.1.1), et rien n'est annoncé.
    private func conversationID(of operation: Operation) async -> String? {
        switch announceDestination(operation) {
        case .thread:                return host?.conversationID
        case .direct(let recipient): return recipient.conversationId
        case .none:                  return await surface.catalog.personalFolder()?.conversationID
        }
    }

    /// Publie la carte de l'opération, comme l'écran d'envoi. Un échec laisse
    /// « Partager dans le fil » : le message manque, l'opération, elle, est faite.
    private func announce(_ reference: FinancialReference, to destination: Destination) async {
        let publish: (@MainActor (FinancialReference) async -> Bool)?
        switch destination {
        case .thread:
            publish = host.map { host in { await host.publish($0, nil) } }
        case .direct(let recipient):
            publish = directMessaging.map { messaging in { await messaging.publish($0, to: recipient) } }
        case .none:
            publish = nil
        }
        guard let publish, await !publish(reference) else { return }
        let id = UUID()
        pendingAnnouncements[id] = (reference, publish)
        append(.announceFailed(id: id, resolved: false))
    }

    func retryAnnouncement(_ messageID: UUID) async {
        guard !isWorking, let pending = pendingAnnouncements[messageID] else { return }
        isWorking = true
        defer { isWorking = false }
        guard await pending.publish(pending.reference),
              let index = messages.firstIndex(where: { $0.id == messageID }) else { return }
        pendingAnnouncements[messageID] = nil
        messages[index] = .announceFailed(id: messageID, resolved: true)
    }

    /// Le fil, ou le dossier personnel du serveur hors conversation (§5.1.1).
    private func operatingConversationID() async -> String? {
        if let id = host?.conversationID, !id.isEmpty { return id }
        return await surface.catalog.personalFolder()?.conversationID
    }

    private func ask(_ question: String, options: [Option]) {
        append(.question(id: UUID(), text: question))
        self.options = options
        step = .choice
    }

    /// L'interlocuteur d'abord, puis les contacts — et, pour une recharge, son propre numéro.
    private func loadRecipientChoices(includingSelf: Bool = false) async {
        var choices: [RecipientChoice] = []
        let own = CurrentSessionInfo.shared.userPhoneNumber
        if includingSelf, !own.isEmpty {
            choices.append(RecipientChoice(id: "self", name: FinanceStrings.copilotMyNumber, detail: own,
                                           input: .phoneNumber(own)))
        }
        if let peer = host?.peer {
            choices.append(RecipientChoice(id: "peer", name: host?.peerName ?? Self.label(of: peer),
                                           detail: nil, input: peer, chatUserID: host?.peerChatUserID))
        }
        let contacts = await surface.splitSharing.participantCandidates()
        choices += contacts
            .filter { !$0.phone.isEmpty }
            .map { RecipientChoice(id: "contact-" + $0.userId + $0.phone, name: $0.name,
                                   detail: $0.phone, input: .phoneNumber($0.phone), chatUserID: $0.userId,
                                   contact: $0) }
        recipientChoices = choices
    }

    /// Choisi dans les propositions.
    func pick(_ choice: RecipientChoice) async {
        guard step == .recipient, !isWorking else { return }
        await choose(choice.input, name: choice.name, chatUserID: choice.chatUserID, target: Self.target(of: choice))
    }

    private static func target(of choice: RecipientChoice) -> RecipientTarget {
        if choice.id == "peer" { return .peer }
        return choice.contact.map(RecipientTarget.contact) ?? .typed
    }

    private static func digits(_ phone: String) -> String { phone.filter(\.isWholeNumber) }

    /// Tapé : un numéro se résout ; un nom choisit le contact qu'il désigne.
    private func typedRecipient(_ text: String) async {
        if let phone = Self.phoneNumber(in: text) {
            // Le numéro d'un contact, ou de l'interlocuteur : son fil porte l'opération.
            let typed = Self.digits(phone)
            if case .phoneNumber(let peer)? = host?.peer, Self.digits(peer) == typed {
                await choose(.phoneNumber(phone), name: host?.peerName, chatUserID: host?.peerChatUserID, target: .peer)
            } else if let contact = recipientChoices.compactMap(\.contact).first(where: { Self.digits($0.phone) == typed }) {
                await choose(.phoneNumber(phone), name: contact.name, chatUserID: contact.userId, target: .contact(contact))
            } else {
                await choose(.phoneNumber(phone), name: nil, target: .typed)
            }
        } else if let match = Self.matches(recipientChoices, query: text).first {
            await choose(match.input, name: match.name, chatUserID: match.chatUserID, target: Self.target(of: match))
        } else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotRecipientPickHint))
        }
    }

    /// Le serveur résout — jamais un nom seul (§0.3.4, `CF_028`).
    private func choose(_ input: RecipientInput, name: String?, chatUserID: String? = nil,
                        target: RecipientTarget = .typed) async {
        guard var current = operation else { return }
        // Une recharge vise un numéro : le serveur le normalise et nomme
        // l'opérateur au catalogue (§5.3) — pas de bénéficiaire à résoudre.
        if current.kind == .topUp {
            guard case .phoneNumber(let msisdn) = input else {
                append(.notice(id: UUID(), text: FinanceStrings.copilotRecipientPickHint))
                return
            }
            append(.user(id: UUID(), text: name.map { "\($0) · \(msisdn)" } ?? msisdn))
            current.msisdn = msisdn
            operation = current
            recipientHint = nil
            await loadTopUpProducts(for: msisdn)
            return
        }
        isWorking = true
        defer { isWorking = false }
        append(.user(id: UUID(), text: name ?? Self.label(of: input)))

        switch await surface.recipientResolver.resolve(input, knownAs: name) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let resolved):
            guard resolved.allowsPayment() else {
                append(.notice(id: UUID(), text: FinanceStrings.sendRecipientUnavailable))
                return
            }
            // Une demande obéit à la politique anti-abus du serveur — avant le montant.
            if current.kind == .requestMoney, let refusal = await requestRefusal(towards: resolved) {
                append(.notice(id: UUID(), text: refusal))
                return
            }
            current.recipient = resolved
            current.recipientName = resolved.actor.displayName.isEmpty ? name : resolved.actor.displayName
            // Un numéro tapé : l'utilisateur que le serveur rend derrière lui en
            // fait un contact — son fil se retrouve, ou se crée, comme pour un choix.
            var target = target
            if case .typed = target, let userID = Self.chatUserID(of: resolved) {
                let phone: String
                if case .phoneNumber(let msisdn) = input { phone = msisdn } else { phone = "" }
                target = .contact(UserContactProps(idContact: nil, userId: userID,
                                                   name: current.recipientName ?? phone, avatar: nil,
                                                   phone: phone, description: "", isBlocked: false))
            }
            current.recipientChatUserID = chatUserID ?? Self.chatUserID(of: resolved)
            // Le fil du bénéficiaire, comme l'écran d'envoi : son prepare le porte,
            // et la carte s'y publie.
            current.destination = await destination(for: target)
            operation = current
            recipientHint = nil
            append(.recipient(id: UUID(), RecipientCard(name: current.recipientName ?? Self.label(of: input),
                                                        verified: resolved.actor.verification == .verified)))
            if current.amount != nil {
                await amountKnown()
            } else {
                askAmount()
            }
        }
    }

    private func typedAmount(_ text: String) async {
        if split?.stage == .total {
            await typedSplitTotal(text)
            return
        }
        if refund?.stage == .amount {
            await typedRefundAmount(text)
            return
        }
        if answer?.stage == .amount {
            await typedAnswerAmount(text)
            return
        }
        guard let amount = Self.amount(in: text), amount > 0 else {
            append(.user(id: UUID(), text: text))
            append(.notice(id: UUID(), text: FinanceStrings.copilotAmountInvalid))
            return
        }
        append(.user(id: UUID(), text: AmountEntry.format(amount, currency)))
        operation?.amount = amount
        isWorking = true
        defer { isWorking = false }
        await amountKnown()
    }

    private func askAmount() {
        let question: String
        switch operation?.kind {
        case .requestMoney?:  question = FinanceStrings.copilotAskAmountRequest
        case .qrPay?, .payBill?: question = FinanceStrings.copilotAskAmountBill
        case .cashIn?:        question = FinanceStrings.copilotAskAmountCashIn
        case .cashOut?:       question = FinanceStrings.copilotAskAmountCashOut
        default:              question = FinanceStrings.copilotAskAmountSend
        }
        append(.question(id: UUID(), text: question))
        step = .amount
    }

    /// Bénéficiaire et montant connus : un devis pour un envoi, une demande à relire sinon.
    private func amountKnown() async {
        guard let current = operation else { return }
        if current.kind == .payBill {
            await quoteBill()
        } else if current.kind == .cashIn {
            await quoteCashIn()
        } else if current.kind == .cashOut {
            await quoteCashOut()
        } else if current.kind == .requestMoney, let amount = current.amount {
            step = .free
            append(.question(id: UUID(), text: FinanceStrings.copilotRequestReady))
            append(.requestReview(id: UUID(), RequestCard(recipientName: current.recipientName ?? "",
                                                          amount: amount, currency: currency, state: .open)))
        } else {
            await requestQuote()
        }
    }

    /// `nil` : la politique du serveur autorise une nouvelle demande.
    private func requestRefusal(towards recipient: ResolvedRecipient) async -> String? {
        guard case .success(let policy) = await surface.moneyRequests.policy(towards: recipient.recipientID) else {
            return Self.localized("finance.request.refused.policy_unavailable")
        }
        // Comme l'écran de demande : en attendant que le serveur les fournisse,
        // les valeurs les plus restrictives.
        switch policy.verdictForNewRequest(openRequests: 0, isContact: true) {
        case .allowed:                return nil
        case .refused(let reasonKey): return Self.localized(reasonKey)
        }
    }

    private static func localized(_ key: String) -> String {
        FinanceLocalization.string(key, fallback: key.replacingOccurrences(of: "_", with: " "))
    }

    /// `POST /request-money` — après le geste de l'utilisateur. Aucun débit, donc
    /// pas d'authentification : le payeur confirmera de son côté.
    func sendRequest(_ messageID: UUID) async {
        guard !isWorking, let card = requestCard(messageID), card.state == .open,
              let current = operation, let recipient = current.recipient else { return }
        isWorking = true
        defer { isWorking = false }
        setRequest(messageID) { $0.state = .confirming }

        let draft = MoneyRequestDraft(recipientID: recipient.recipientID, amount: card.amount,
                                      currency: card.currency, conversationID: await conversationID(of: current),
                                      recipientChatUserID: current.recipientChatUserID)
        // La même portée que l'écran de demande : relancée, la même demande.
        let idempotency = await surface.operationKeys.key(
            for: FinanceOperationKeys.scope("request.create", String(describing: draft)), deviceID: surface.deviceID)
        switch await surface.moneyRequests.createRequest(draft, idempotency: idempotency) {
        case .failure(let error):
            setRequest(messageID) { $0.state = .open }
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        case .success(let reference):
            setRequest(messageID) { $0.state = .closed }
            append(.question(id: UUID(), text: FinanceStrings.copilotRequestSent))
            append(.outcome(id: UUID(), reference))
            operation = nil
            await announce(reference, to: announceDestination(current))
        }
    }

    /// Le devis du serveur (`/send-money/prepare`) — montants, frais, total.
    private func requestQuote() async {
        guard let current = operation, let recipient = current.recipient, let amount = current.amount else { return }
        step = .free
        let draft = TransferDraft(recipientID: recipient.recipientID, amount: amount, currency: currency,
                                  conversationID: await conversationID(of: current))
        switch await surface.transferQuoting.quote(for: draft) {
        case .failure(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            // Le montant était peut-être en cause : on le redemande.
            operation?.amount = nil
            askAmount()
        case .success(let quote):
            append(.question(id: UUID(), text: FinanceStrings.copilotQuoteReady))
            append(.quote(id: UUID(), QuoteCard(quote: quote, recipientName: current.recipientName ?? "",
                                                state: .open, kind: current.kind, payeeID: recipient.recipientID)))
        }
    }

    // MARK: - Confirmer

    /// **Geste de l'utilisateur**, suivi de Face ID ou du code, puis le chemin de
    /// l'écran d'envoi. Rien ne part sans les deux.
    func confirm(_ messageID: UUID) async {
        guard !isWorking, let card = quoteCard(messageID), card.state == .open, !card.payeeID.isEmpty else { return }
        isWorking = true
        defer { isWorking = false }
        setQuote(messageID) { $0.state = .confirming }

        // Face ID seul : jamais l'écran de code de l'appareil. Indisponible,
        // verrouillé ou refusé, le PIN du portefeuille prend le relais.
        let attestation: StepUpAttestation
        do {
            attestation = try await surface.stepUp.satisfyStepUp(
                level: .biometric, reason: FinanceStrings.stepUpReasonPayment,
                correlationID: card.quote.reference.correlationID, deviceID: surface.deviceID)
        } catch StepUpError.userCancelled {
            setQuote(messageID) { $0.state = .open }
            append(.notice(id: UUID(), text: FinanceStrings.copilotStepUpCancelled))
            return
        } catch {
            pinRequest = messageID
            return
        }
        await submit(messageID, card, attestation: attestation)
    }

    // MARK: - PIN du portefeuille (repli de Face ID)

    /// Le devis qui attend le PIN — la feuille du portefeuille est ouverte.
    @Published private(set) var pinRequest: UUID?

    /// Le PIN est vérifié **par le serveur**, jamais ici. Refusé, rien ne part
    /// et le devis reste confirmable.
    func submitPIN(_ pin: String) async {
        guard !isWorking, let messageID = pinRequest, let card = quoteCard(messageID) else { return }
        isWorking = true
        defer { isWorking = false }
        pinRequest = nil
        switch await surface.pinVerifier.verify(pin: pin, correlationID: card.quote.reference.correlationID,
                                                deviceID: surface.deviceID) {
        case .success(let attestation):
            await submit(messageID, card, attestation: attestation)
        case .failure(.capabilityUnavailable):
            setQuote(messageID) { $0.state = .open }
            append(.notice(id: UUID(), text: FinanceStrings.copilotPINUnavailable))
        case .failure(let error):
            setQuote(messageID) { $0.state = .open }
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
        }
    }

    /// La feuille fermée sans PIN : rien ne part, le devis reste confirmable.
    func cancelPIN() {
        guard let messageID = pinRequest else { return }
        pinRequest = nil
        setQuote(messageID) { $0.state = .open }
        append(.notice(id: UUID(), text: FinanceStrings.copilotStepUpCancelled))
    }

    /// Le chemin de l'écran d'envoi, une fois l'utilisateur authentifié.
    private func submit(_ messageID: UUID, _ card: QuoteCard, attestation: StepUpAttestation) async {
        let outcome = await TransferSubmission.confirm(
            card.quote, recipientID: card.payeeID, counterpartyName: card.recipientName,
            attestation: attestation, sendMoney: surface.sendMoney, operationKeys: surface.operationKeys,
            objects: surface.objectReader, deviceID: surface.deviceID)
        setQuote(messageID) { $0.state = .closed }

        switch FinancialOutcomeRoute.route(outcome, submittedReference: card.quote.reference) {
        case .submitted(let reference):
            append(.question(id: UUID(), text: FinanceStrings.copilotSubmitted))
            append(.outcome(id: UUID(), reference))
            refund = nil
            if let paid = answer?.request {
                // Le paiement n'est pas un nouveau message : c'est la demande qui change.
                answer = nil
                await surface.requestResponder?.forget(paid.reference)
                _ = await surface.objectReader?.refresh(paid.reference)
                NotificationCenter.default.post(name: .financeRequestDidChange, object: paid.reference.id)
                return
            }
            await announce(reference, to: announceDestination(operation))
            await continueAfterSubmission(reference)
        case .verifying(let reference):
            // L'argent est peut-être parti : jamais un échec, jamais un nouvel envoi.
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(.timeoutUnknown)))
            append(.outcome(id: UUID(), reference))
            operation = nil
        case .needsNewAgreement:
            if case .needsNewAgreement(_, let fresh) = outcome {
                append(.question(id: UUID(), text: FinanceStrings.copilotConditionsChanged))
                append(.quote(id: UUID(), QuoteCard(quote: fresh, recipientName: card.recipientName, state: .open,
                                                    kind: card.kind, payeeID: card.payeeID,
                                                    titleOverride: card.titleOverride)))
            }
        case .failed(.expired):
            // Rien n'est parti : un devis actualisé, à reconfirmer.
            if case .success(let fresh) = await surface.transferQuoting.refreshQuote(card.quote), !fresh.isExpired() {
                append(.question(id: UUID(), text: FinanceStrings.copilotQuoteRefreshed))
                append(.quote(id: UUID(), QuoteCard(quote: fresh, recipientName: card.recipientName, state: .open,
                                                    kind: card.kind, payeeID: card.payeeID,
                                                    titleOverride: card.titleOverride)))
            } else {
                await requote()
            }
        case .failed(let error):
            append(.notice(id: UUID(), text: FinanceStrings.errorMessage(error)))
            operation = nil
        }
    }

    /// Le devis expiré sur la carte : un devis actualisé à sa place.
    func refreshQuote(_ messageID: UUID) async {
        guard !isWorking, let card = quoteCard(messageID), card.state == .open else { return }
        isWorking = true
        defer { isWorking = false }
        setQuote(messageID) { $0.state = .closed }
        if case .success(let fresh) = await surface.transferQuoting.refreshQuote(card.quote), !fresh.isExpired() {
            append(.quote(id: UUID(), QuoteCard(quote: fresh, recipientName: card.recipientName, state: .open,
                                                kind: card.kind, payeeID: card.payeeID,
                                                    titleOverride: card.titleOverride)))
        } else {
            await requote()
        }
    }

    /// Un nouveau devis pour l'opération en cours — celui de son propre prepare.
    private func requote() async {
        if refund != nil { await quoteRefund(); return }
        if answer != nil { await quoteAnswer(); return }
        switch operation?.kind {
        case .payBill?: await quoteBill()
        case .topUp?:   await quoteTopUp()
        case .qrPay?:   await quoteQR()
        case .invoice?: await quoteInvoice()
        case .cashIn?:  await quoteCashIn()
        case .cashOut?: await quoteCashOut()
        default:        await requestQuote()
        }
    }

    func cancel(_ messageID: UUID) {
        guard !isWorking else { return }
        let wasRequest = requestCard(messageID) != nil
        setQuote(messageID) { $0.state = .closed }
        setRequest(messageID) { $0.state = .closed }
        closeScanners()
        operation = nil
        options = []
        step = .free
        append(.notice(id: UUID(), text: wasRequest ? FinanceStrings.copilotRequestCancelled
                                                    : FinanceStrings.copilotCancelled))
    }

    /// Abandonne l'opération en cours — une autre demande commence.
    func abandonOperation() {
        guard !isWorking else { return }
        closeOpenQuotes()
        operation = nil
        dispute = nil
        refund = nil
        reversal = nil
        answer = nil
        cancellation = nil
        split = nil
        recipientHint = nil
        options = []
        step = .free
    }

    // MARK: - Aide

    private func append(_ message: Message) {
        messages.append(message)
        persist(message)
    }

    // MARK: - Conservation

    /// Ce qui se garde d'un message — rien de ce qui ne doit pas survivre à l'écran.
    ///
    /// Un devis, une demande, une caméra se gardent **fermés** : rouverte, la
    /// conversation ne confirme jamais un devis d'hier. Le code de retrait ne se
    /// garde pas — il s'affiche une fois. L'échec d'une annonce non plus : il
    /// ne vaut que pour l'écran ouvert. Une opération soumise garde sa
    /// référence, et son statut se relit au serveur.
    enum StoredMessage: Codable, Equatable {
        case user(id: UUID, text: String)
        case copilot(id: UUID, text: String, authoritative: Bool)
        case question(id: UUID, text: String)
        case notice(id: UUID, text: String)
        case proposal(id: UUID, Proposal)
        case recipient(id: UUID, RecipientCard)
        case quote(id: UUID, QuoteCard)
        case requestReview(id: UUID, RequestCard)
        case bill(id: UUID, BillCard)
        case scanner(id: UUID, scanned: Bool)
        case outcome(id: UUID, FinancialReference)

        init?(_ message: Message) {
            switch message {
            case .user(let id, let text):              self = .user(id: id, text: text)
            case .copilot(let id, let text, let a):    self = .copilot(id: id, text: text, authoritative: a)
            case .question(let id, let text):          self = .question(id: id, text: text)
            case .notice(let id, let text):            self = .notice(id: id, text: text)
            case .proposal(let id, let proposal):      self = .proposal(id: id, proposal)
            case .recipient(let id, let card):         self = .recipient(id: id, card)
            case .quote(let id, var card):
                card.state = .closed
                self = .quote(id: id, card)
            case .requestReview(let id, var card):
                card.state = .closed
                self = .requestReview(id: id, card)
            case .bill(let id, let card):              self = .bill(id: id, card)
            case .scanner(let id, let state):          self = .scanner(id: id, scanned: state == .scanned)
            case .outcome(let id, let reference):      self = .outcome(id: id, reference)
            case .cashOutCode(let id, _):              self = .notice(id: id, text: FinanceStrings.copilotCashOutCodeNotKept)
            case .paymentLink(let id, _, _):           self = .notice(id: id, text: FinanceStrings.copilotPaymentLinkNotKept)
            case .announceFailed:                      return nil
            }
        }

        var message: Message {
            switch self {
            case .user(let id, let text):              return .user(id: id, text: text)
            case .copilot(let id, let text, let a):    return .copilot(id: id, text: text, authoritative: a)
            case .question(let id, let text):          return .question(id: id, text: text)
            case .notice(let id, let text):            return .notice(id: id, text: text)
            case .proposal(let id, let proposal):      return .proposal(id: id, proposal)
            case .recipient(let id, let card):         return .recipient(id: id, card)
            case .quote(let id, let card):             return .quote(id: id, card)
            case .requestReview(let id, let card):     return .requestReview(id: id, card)
            case .bill(let id, let card):              return .bill(id: id, card)
            case .scanner(let id, let scanned):        return .scanner(id: id, state: scanned ? .scanned : .closed)
            case .outcome(let id, let reference):      return .outcome(id: id, reference)
            }
        }

        var id: UUID { message.id }
    }

    /// La ligne de la liste des discussions — les mots, et le titre d'un devis.
    static func preview(of stored: StoredMessage) -> String? {
        switch stored {
        case .user(_, let text), .copilot(_, let text, _), .question(_, let text), .notice(_, let text):
            return text
        case .quote(_, let card):
            return title(of: card.kind)
        default:
            return nil
        }
    }

    /// Relit la conversation conservée, avant tout nouveau message.
    private func restoreConversation() async {
        guard let conversationStore, storedConversationID == nil else { return }
        do {
            let id = try await conversationStore.conversationID()
            storedConversationID = id
            let decoder = JSONDecoder()
            let restored = try await conversationStore.messages(in: id)
                .compactMap { try? decoder.decode(StoredMessage.self, from: $0).message }
            messages = restored + messages
            restoredCount = restored.count
        } catch {
            // La conversation reste utilisable ; elle ne se garde simplement pas.
            #if DEBUG
            print("[Copilot] conversation not restored: \(error)")
            #endif
        }
    }

    /// Écrit le message, dans l'ordre — les échecs ne gênent pas la conversation.
    private func persist(_ message: Message) {
        guard let conversationStore, let conversationID = storedConversationID,
              let stored = StoredMessage(message), let payload = try? JSONEncoder().encode(stored) else { return }
        let preview = Self.preview(of: stored)
        let previous = persistence
        persistence = Task {
            await previous?.value
            try? await conversationStore.save(payload, messageID: stored.id.uuidString,
                                              preview: preview, to: conversationID)
        }
    }

    /// Attend les écritures en cours — pour les tests.
    func flushPersistence() async { await persistence?.value }

    private func quoteCard(_ id: UUID) -> QuoteCard? {
        for message in messages { if case .quote(id, let card) = message { return card } }
        return nil
    }

    private func setQuote(_ id: UUID, _ change: (inout QuoteCard) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              case .quote(_, var card) = messages[index] else { return }
        change(&card)
        messages[index] = .quote(id: id, card)
    }

    private func requestCard(_ id: UUID) -> RequestCard? {
        for message in messages { if case .requestReview(id, let card) = message { return card } }
        return nil
    }

    private func setRequest(_ id: UUID, _ change: (inout RequestCard) -> Void) {
        guard let index = messages.firstIndex(where: { $0.id == id }),
              case .requestReview(_, var card) = messages[index] else { return }
        change(&card)
        messages[index] = .requestReview(id: id, card)
    }

    /// Une seule carte confirmable à la fois — et plus de caméra ouverte.
    private func closeOpenQuotes() {
        closeScanners()
        for message in messages {
            if case .quote(let id, let card) = message, card.state == .open { setQuote(id) { $0.state = .closed } }
            if case .requestReview(let id, let card) = message, card.state == .open {
                setRequest(id) { $0.state = .closed }
            }
        }
    }

    /// L'identité vient de la session, jamais du texte (§54.3).
    private static func context() -> CopilotContext {
        CopilotContext(companyID: "", actorID: CurrentSessionInfo.shared.currentUid, countryCode: "",
                       conversationID: "", channelType: "MOBILE", allowedScopes: grantedScopes,
                       correlationID: UUID().lowercasedString, traceParent: "")
    }

    /// Propositions filtrées par ce qui est tapé — nom ou numéro.
    static func matches(_ choices: [RecipientChoice], query: String) -> [RecipientChoice] {
        let needle = query.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive],
                                                                         locale: nil)
        guard !needle.isEmpty else { return choices }
        return choices.filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(needle)
                || ($0.detail ?? "").contains(needle)
        }
    }

    /// Un numéro de téléphone tapé : chiffres, `+` en tête, espaces tolérés.
    static func phoneNumber(in text: String) -> String? {
        let compact = text.filter { !$0.isWhitespace && $0 != "-" }
        let digits = compact.hasPrefix("+") ? String(compact.dropFirst()) : compact
        guard digits.count >= 6, digits.allSatisfy(\.isNumber) else { return nil }
        return compact
    }

    /// « 5 000 », « 5000,50 » — la virgule du clavier français admise.
    static func amount(in text: String) -> Decimal? {
        let normalized = text.filter { !$0.isWhitespace && $0 != "\u{202F}" && $0 != "\u{00A0}" }
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func label(of input: RecipientInput) -> String {
        switch input {
        case .phoneNumber(let msisdn), .mobileMoney(_, let msisdn): return msisdn
        case .walletHandle(let handle):                             return handle
        default:                                                    return FinanceStrings.recipientTo
        }
    }

    /// Libellé d'un outil : son parcours s'il en ouvre un, sinon son nom connu.
    static func label(of tool: FinanceCopilotTool) -> String? {
        if let kind = kind(of: tool) { return title(of: kind) }
        switch tool.name {
        case "wallet.get_balance": return FinanceStrings.copilotToolBalance
        case "fco.get_status":     return FinanceStrings.copilotToolStatus
        case "capability.list":    return FinanceStrings.copilotToolCapabilities
        default:                   return nil
        }
    }

    static func title(of tool: FinanceCopilotTool) -> String {
        label(of: tool) ?? tool.name
    }

    static func title(of kind: FinanceEntryKind) -> String {
        FinanceLocalization.string(FinanceTranslationKeys.entryKey(for: kind),
                                   fallback: kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)
    }
}
