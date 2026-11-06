//
//  FinanceHomeView.swift
//  FeatureChat
//
//  L'accueil financier — un seul, pour toutes les surfaces.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// L'accueil financier de Waangu.
///
/// **Un seul écran, trois hôtes** : l'onglet Waangu d'une conversation, l'écran
/// plein de la conversation, et les Réglages. Chacun en avait auparavant sa
/// propre composition, et les trois divergeaient — l'un montrait un solde, les
/// autres non ; l'un listait neuf services, l'autre quatre. Un utilisateur qui
/// voit deux fois le même nom sur deux dessins différents conclut qu'il s'agit
/// de deux fonctions.
///
/// L'hôte ne fournit que ce qu'il sait : le contexte de conversation, et ce
/// qu'il faut faire d'une entrée choisie. Tout le reste — solde, catalogue,
/// niveau d'authentification — est lu ici, une fois.
///
/// L'ordre est celui de la maquette de référence, et il répond aux questions
/// dans l'ordre où elles se posent : de combien je dispose, que puis-je faire,
/// où est mon argent, qu'ai-je fait.
struct FinanceHomeView: View {

    let surface: ChatFinanceSurface
    let context: ChatFinanceContext

    /// Ce que l'hôte fait d'une entrée choisie.
    ///
    /// La vue ne présente aucun parcours elle-même : dans une conversation,
    /// l'entrée s'ouvre sur le fil ; depuis les Réglages, elle passe d'abord par
    /// un choix de bénéficiaire. Trancher ici obligerait la vue à connaître ses
    /// hôtes.
    let onSelect: (FinanceCatalogEntry) -> Void

    var translationService: (any TranslationServiceProtocol)?

    /// La conversation d'où l'accueil est ouvert : Copilot y prend
    /// l'interlocuteur et y annonce l'opération. `nil` hors conversation.
    var copilotHost: CopilotConversationHost?
    /// Le fil direct du contact que Copilot choisit, et l'annonce qui s'y fait.
    var copilotMessaging: WalletPaymentFlowViewModel?
    /// Copilot fermé : l'hôte ouvre le fil où une opération vient d'être annoncée.
    var onCopilotClosed: (() -> Void)?
    /// La conversation Copilot conservée — **une seule**, la même partout : la
    /// liste des discussions, le portefeuille, l'accueil des paiements d'un fil.
    var copilotStore: (any CopilotConversationStoring)?

    init(surface: ChatFinanceSurface,
         context: ChatFinanceContext,
         onSelect: @escaping (FinanceCatalogEntry) -> Void,
         translationService: (any TranslationServiceProtocol)? = nil,
         copilotHost: CopilotConversationHost? = nil,
         copilotMessaging: WalletPaymentFlowViewModel? = nil,
         onCopilotClosed: (() -> Void)? = nil,
         copilotStore: (any CopilotConversationStoring)? = nil) {
        self.surface = surface
        self.context = context
        self.onSelect = onSelect
        self.translationService = translationService
        self.copilotHost = copilotHost
        self.copilotMessaging = copilotMessaging
        self.onCopilotClosed = onCopilotClosed
        self.copilotStore = copilotStore
        // Une seule lecture de session pour l'écran : le bandeau la partage au
        // lieu d'en déclencher une seconde.
        _session = StateObject(wrappedValue: FinanceSessionViewModel(provider: surface.financeSession))
    }

    @StateObject private var session: FinanceSessionViewModel
    @State private var entries: [FinanceCatalogEntry] = []
    @State private var phase: Phase = .loading
    /// Nouvelle tentative en cours depuis l'écran d'indisponibilité.
    @State private var isRetrying = false
    @State private var balanceState: BalanceState = .loading
    @State private var stepUpLevel: StepUpLevel?
    @State private var recent: [TransactionHistoryEntry] = []
    /// Ce que la lecture du relevé a donné. Voir `HistoryState`.
    @State private var historyState: HistoryState = .loading
    @State private var showsAllServices = false
    @State private var showsHistory = false
    /// Refus du catalogue, dans les mots du serveur. Voir `loadCatalog()`.
    @State private var catalogRefusal: String?
    /// Texte libre lu par le Hub (§2.2) — un brouillon, jamais une commande.
    @State private var draftText = ""
    @State private var isReadingDraft = false
    @State private var draftNotice: String?
    /// Waangu Copilot (§8) : proposé seulement si le Hub publie au moins un outil.
    @State private var copilotAvailable = false
    @State private var showsCopilot = false

    private enum Phase: Equatable {
        case loading
        /// Le catalogue a répondu, et il n'y a rien à proposer sur ce marché.
        case empty
        /// Le catalogue n'a **pas** répondu. Distinct de `empty` : l'un est une
        /// réponse de marché, l'autre une panne, et les annoncer pareil ferait
        /// expliquer une coupure réseau par le pays de l'utilisateur.
        case failed
        case loaded
    }

    /// Trois issues que la page confondait en une seule : rien.
    ///
    /// « Aucune opération » est une réponse du serveur ; « relevé indisponible »
    /// est son silence. Les afficher pareil — en escamotant la section — laissait
    /// croire à un compte sans historique alors qu'aucun relevé n'est encore
    /// servi. Le relevé reste **du serveur** (voir `TransactionHistoryEntry`) :
    /// rien n'est agrégé ici pour combler son absence.
    private enum HistoryState: Equatable {
        case loading
        case entries([TransactionHistoryEntry])
        /// Le serveur a répondu, et le compte n'a pas d'opération.
        case empty
        /// Pas de relevé : droit de consultation refusé, service non branché,
        /// ou lecture en échec. Le texte est celui du serveur quand il en a un.
        case unavailable(String?)
    }

    private enum BalanceState: Equatable {
        case loading
        case ready(GetBalance)
        /// Lecture impossible. **Jamais remplacé par zéro** : « 0 » affirme que
        /// le compte est vide, et l'affirmer sans le savoir est le seul faux que
        /// cet écran puisse produire.
        case unavailable
    }

    /// Les trois gestes de tête, dans l'ordre du parcours réel : on envoie plus
    /// souvent qu'on ne demande, et on scanne avant tout le reste.
    ///
    /// Trois et non quatre : la quatrième pastille est « Plus de services », qui
    /// n'est pas un geste financier mais une porte. La faire dériver du
    /// catalogue l'aurait fait disparaître le jour où le catalogue se réduit —
    /// c'est-à-dire le jour où elle est la plus utile.
    private static let quickKinds: [FinanceEntryKind] = [.sendMoney, .requestMoney, .qrPay]

    /// Ce que la page d'accueil montre en propre, et qui ne repart donc pas
    /// dans la grille.
    private static let promoted: Set<FinanceEntryKind> = [
        .sendMoney, .requestMoney, .qrPay, .cards, .pfm
    ]

    // MARK: - Corps

    /// Rien n'est joignable : ni la session, ni le Hub.
    ///
    /// Tout le reste de la page devient alors du décor — un solde qu'on ne peut
    /// pas relire, des pastilles qui n'ouvrent rien, un relevé vide. L'écran
    /// entier cède la place au message d'indisponibilité : un seul état, une
    /// seule action.
    @MainActor
    private var isUnreachable: Bool {
        session.state == .unavailable || phase == .failed
    }

    /// Première résolution en cours : ni catalogue, ni session.
    ///
    /// Seulement la **première** — une relecture, elle, garde la page affichée
    /// et remplace son contenu quand il arrive. Reposer le chargeur à chaque
    /// rafraîchissement ferait clignoter un écran déjà lisible.
    @MainActor
    private var isPreparing: Bool {
        phase == .loading && entries.isEmpty && !isUnreachable
    }

    var body: some View {
        Group {
            // L'attente passe en premier : pendant une nouvelle tentative, la
            // session est encore marquée injoignable, et l'écran d'échec
            // resterait affiché sous un bouton déjà pressé.
            if isRetrying || isPreparing {
                FinanceLoaderView()
                    .transition(.opacity)
            } else if isUnreachable {
                FinanceUnreachableView(detail: catalogRefusal) { await retry() }
                    .transition(.opacity)
            } else if session.restriction == .countryClosed {
                // Pays non ouvert ou non localisé : le contrat demande cet écran
                // **à la place** du Hub (§1.2), pas un bandeau au-dessus.
                FinanceCountryClosedView { await retry() }
                    .transition(.opacity)
            } else {
                page
                    // Waangu Copilot flotte au-dessus de la page, déplaçable :
                    // il ne prend la place d'aucune action de la rangée.
                    .overlay {
                        if copilotAvailable {
                            CopilotFloatingButton { showsCopilot = true }
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.22), value: isPreparing)
        .animation(.easeOut(duration: 0.22), value: isRetrying)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.walletCanvas)
        .task(id: context) { await loadCatalog() }
        // Dans cet ordre, et pas en parallèle : le solde et le relevé ne sont
        // demandés qu'une fois l'amorçage terminé, et seulement s'il les autorise.
        .task {
            await session.load()
            await loadAccount()
        }
        .chatAppearanceSheet(isPresented: $showsAllServices) {
            FinanceServicesGridView(
                entries: listedEntries,
                onSelect: { entry in
                    showsAllServices = false
                    Task { await admit(entry) }
                },
                onDismiss: { showsAllServices = false }
            )
        }
        // Backend réel seulement : les outils de Waangu Copilot sont ceux du Hub.
        .task {
            guard surface.financeSession != nil,
                  case .success(let tools) = await surface.catalog.copilotTools() else { return }
            copilotAvailable = !tools.isEmpty
        }
        .chatAppearanceSheet(isPresented: $showsCopilot, onDismiss: onCopilotClosed) {
            CopilotConversationView(
                surface: surface,
                host: copilotHost,
                // Les tuiles de l'accueil : ce que le Hub permet ici.
                hubKinds: entries.filter { $0.isActionable() }.map(\.kind),
                closedHubActions: Dictionary(entries.filter { !$0.isActionable() && $0.unavailableReasonKey != nil }
                    .map { ($0.kind, FinanceLocalization.entryReason($0.unavailableReasonKey ?? "")) },
                    uniquingKeysWith: { first, _ in first }),
                directMessaging: copilotMessaging,
                conversationStore: copilotStore,
                onOpen: { draft in
                    showsCopilot = false
                    Task { await openDraft(draft) }
                },
                onDismiss: { showsCopilot = false }
            )
            // Une feuille n'est pas dans la pile de l'accueil : sans cela, la
            // portée s'y croirait déjà — ni titre, ni bouton de fermeture.
            .environment(\.financeHasNavigationStack, false)
        }
        .chatAppearanceSheet(isPresented: $showsHistory) {
            TransactionHistoryView(history: surface.transactionHistory) {
                showsHistory = false
            }
        }
    }

    /// Nouvelle tentative : on jette ce que le client croyait savoir avant de
    /// relire, sans quoi un instantané périmé répondrait à la place du serveur.
    private func retry() async {
        await MainActor.run { isRetrying = true }
        await surface.catalog.invalidate()
        await session.refresh()
        await loadCatalog()
        // La page décide dès que session et catalogue ont répondu. Le solde a
        // son propre état de chargement : l'attendre ici tiendrait tout l'écran
        // derrière la lecture la plus lente.
        await MainActor.run { isRetrying = false }
        await loadAccount()
    }

    private var page: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Backend réel seulement : dit pourquoi l'écriture est refusée.
                // Les motifs qui restent ici laissent la page lisible — pays
                // fermé, mode sûr, session à revalider : on peut encore
                // consulter. L'injoignable, lui, a pris tout l'écran plus haut.
                if surface.financeSession != nil {
                    FinanceSessionBanner(viewModel: session)
                        .padding(.top, 8)
                }

                WalletBalanceBlock(title: totalBalanceTitle, state: balanceBlockState)

                FinanceQuickActions(actions: quickActions)
                    .padding(.bottom, 4)

                // Backend réel seulement : seul le Hub sait lire un texte.
                if surface.financeSession != nil, phase != .empty { draftField }

                if needsPINSetup { promoCard }

                accountRow
                addPaymentMethodRow

                if phase == .empty { emptyNotice }

                historySection
            }
            .padding(.bottom, 28)
        }
    }

    // MARK: - Actions rapides

    private var quickActions: [FinanceQuickActions.Action] {
        var actions = Self.quickKinds.compactMap { kind -> FinanceQuickActions.Action? in
            let entry = entries.first { $0.kind == kind }
            return FinanceQuickActions.Action(
                id: kind.rawValue,
                symbol: entry?.iconName ?? Self.fallbackSymbol(for: kind),
                label: label(for: kind, entry: entry),
                // Une pastille dont le catalogue ne propose pas l'entrée reste
                // **visible et grisée** : la masquer ferait bouger la rangée
                // d'un marché à l'autre, et un geste absent se cherche.
                isEnabled: entry?.isActionable() ?? false,
                handler: {
                    guard let entry, entry.isActionable() else { return }
                    Task { await admit(entry) }
                }
            )
        }

        actions.append(FinanceQuickActions.Action(
            id: "MORE_SERVICES",
            symbol: "square.grid.2x2.fill",
            label: FinanceLocalization.string("wallet_more_services", fallback: "Plus de services"),
            isEnabled: !listedEntries.isEmpty,
            handler: { showsAllServices = true }
        ))
        return actions
    }

    /// Glyphe de repli quand le catalogue ne rend pas l'entrée : la pastille
    /// grisée doit tout de même montrer de quoi elle parle.
    private static func fallbackSymbol(for kind: FinanceEntryKind) -> String {
        switch kind {
        case .sendMoney:    return "arrow.up"
        case .requestMoney: return "arrow.down"
        case .qrPay:        return "qrcode.viewfinder"
        case .splitBill:    return "person.2.fill"
        default:            return "creditcard"
        }
    }

    private func label(for kind: FinanceEntryKind, entry: FinanceCatalogEntry?) -> String {
        if let entry { return FinanceLocalization.entryShortTitle(entry) }
        // Le catalogue ne rend pas l'entrée : le libellé vient alors de la
        // nature, qui est un type fermé et donc toujours traduisible.
        return FinanceLocalization.string(
            "entry_short_" + kind.rawValue.lowercased(),
            fallback: FinanceLocalization.string(
                FinanceTranslationKeys.entryKey(for: kind), fallback: kind.rawValue)
        )
    }

    /// Tout ce que l'accueil ne montre pas déjà en propre — jamais deux fois la
    /// même entrée.
    private var listedEntries: [FinanceCatalogEntry] {
        var listed = entries.filter { !Self.promoted.contains($0.kind) }
        // Le partage d'addition ouvre la grille quand le Hub le propose — dans
        // une conversation de groupe, seul contexte où le contrat l'autorise.
        // Le reste garde l'ordre du serveur : c'est lui qui décide de la suite.
        if let index = listed.firstIndex(where: { $0.kind == .splitBill }) {
            listed.insert(listed.remove(at: index), at: 0)
        }
        return listed
    }

    // MARK: - Cartes

    private var promoCard: some View {
        WalletPromoCard(
            title: FinanceLocalization.string(
                "wallet_protect_title", fallback: "Protégez vos transactions avec un code"),
            actionTitle: FinanceLocalization.string(
                "wallet_protect_action", fallback: "Configurer le code"),
            symbol: "lock.fill",
            action: { Task { await configurePIN() } }
        )
        .padding(.horizontal, 16)
    }

    /// Le compte et son solde.
    ///
    /// Le montant n'apparaît **que** s'il a été lu. En cas d'échec la ligne
    /// existe toujours — le compte, lui, existe — mais sa droite reste vide
    /// plutôt que d'afficher un zéro.
    private var accountRow: some View {
        WalletCardRow(
            symbol: "dollarsign",
            iconColor: AppColors.walletCurrency,
            iconShape: .circle,
            title: accountName,
            subtitle: accountSubtitle,
            trailing: accountTrailing,
            action: { open(kind: .pfm) }
        )
        .padding(.horizontal, 16)
    }

    private var accountTrailing: WalletCardRow.Trailing {
        guard case .ready(let account) = balanceState else { return .none }
        return .value(primary: formatted(Decimal(account.balance), account.currency),
                      secondary: nil)
    }

    private var accountSubtitle: String? {
        guard case .ready(let account) = balanceState else { return nil }
        // Le code ISO sous le nom du compte : « BIF » dit ce que « FBu » ne dit
        // pas à qui gère plusieurs devises.
        return account.currency
    }

    private var addPaymentMethodRow: some View {
        WalletCardRow(
            symbol: "creditcard.fill",
            iconColor: AppColors.primary,
            iconShape: .circle,
            title: FinanceLocalization.string(
                "wallet_add_payment_method", fallback: "Ajouter un moyen de paiement"),
            trailing: .chevron,
            action: { open(kind: .cards) }
        )
        .padding(.horizontal, 16)
    }

    /// Catalogue vide, dit **sur** la page plutôt qu'à sa place.
    ///
    /// Le solde et le relevé restent vrais quand aucun service n'est proposé :
    /// remplacer toute la page par un état vide retirerait à l'utilisateur ce
    /// qu'il peut encore consulter.
    private var emptyNotice: some View {
        Text(FinanceStrings.hubEmptyDetail)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 32)
            .padding(.top, 4)
    }

    // MARK: - Relevé

    /// Les dernières opérations, sur la page même.
    ///
    /// Trois lignes et un lien : assez pour répondre à « est-ce passé ? » sans
    /// ouvrir le relevé, trop peu pour tenir lieu de relevé.
    ///
    /// La section ne s'escamote plus quand elle n'a rien à montrer. Elle le
    /// faisait pour les trois issues à la fois — des lignes, un compte sans
    /// opération, un relevé qu'on n'a pas pu lire — et les deux dernières se
    /// lisaient donc comme la même chose : un compte vierge. Aucun relevé n'est
    /// pourtant servi aujourd'hui, et la page l'affirmait par son silence.
    ///
    /// Rien n'est comblé localement : le relevé vient du serveur, jamais d'une
    /// agrégation d'ici — voir `TransactionHistoryEntry`.
    @ViewBuilder
    private var historySection: some View {
        switch historyState {
        case .loading:
            EmptyView()
        case .entries(let rows):
            historyFrame(showsSeeAll: true) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, entry in
                        TransactionHistoryRow(entry: entry, showsSeparator: index < rows.count - 1)
                    }
                }
            }
        case .empty:
            historyFrame(showsSeeAll: false) {
                historyNotice(icon: "tray", text: FinanceStrings.historyEmpty)
            }
        case .unavailable(let reason):
            historyFrame(showsSeeAll: false) {
                historyNotice(icon: "exclamationmark.triangle",
                              text: reason ?? FinanceStrings.historyUnavailable)
            }
        }
    }

    private func historyFrame<Content: View>(showsSeeAll: Bool,
                                             @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            WalletSectionHeader(
                title: FinanceLocalization.string(
                    "wallet_transaction_history", fallback: "Historique des transactions"),
                actionTitle: showsSeeAll
                    ? FinanceLocalization.string("wallet_see_all", fallback: "Voir tout") : nil,
                action: showsSeeAll ? { showsHistory = true } : nil
            )

            content()
                .background(AppColors.cardBackground,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.horizontal, 16)
        }
    }

    private func historyNotice(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.subtitleGray)
            Text(text)
                .font(.footnote)
                .foregroundStyle(AppColors.subtitleGray)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Brouillon (§2.2)

    /// « Que voulez-vous faire ? » — le Hub lit le texte, l'app ouvre le
    /// parcours qu'il désigne avec le montant proposé. Rien n'est préparé ni
    /// envoyé d'ici : le bénéficiaire se choisit, et l'envoi se confirme, dans
    /// le parcours lui-même.
    private var draftField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.primary)
                    .accessibilityHidden(true)
                TextField(FinanceStrings.draftPlaceholder, text: $draftText)
                    .font(.system(size: 15))
                    .submitLabel(.go)
                    .disabled(isReadingDraft)
                    .onSubmit { Task { await readDraft() } }
                if isReadingDraft {
                    ProgressView()
                } else if !draftText.isEmpty {
                    Button { Task { await readDraft() } } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(AppColors.primary)
                    }
                    .accessibilityLabel(FinanceStrings.draftSubmit)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .background(AppColors.cardBackground,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let draftNotice {
                Text(draftNotice)
                    .font(.footnote)
                    .foregroundStyle(AppColors.subtitleGray)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal, 16)
    }

    /// Lit le texte, puis ouvre l'entrée du catalogue qu'il désigne — par le
    /// même chemin qu'un appui sur la tuile, élévation comprise.
    @MainActor
    private func readDraft() async {
        let text = draftText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !isReadingDraft else { return }
        isReadingDraft = true
        draftNotice = nil
        let outcome = await surface.catalog.draft(from: text)
        isReadingDraft = false
        switch outcome {
        case .failure(let error):
            draftNotice = FinanceStrings.errorMessage(error)
        case .success(let draft):
            guard draft.kind != nil else {
                draftNotice = draft.message ?? FinanceStrings.draftNoAction
                return
            }
            if await openDraft(draft) { draftText = "" }
        }
    }

    /// Ouvre le parcours qu'un brouillon désigne — depuis le champ ou depuis
    /// Waangu Copilot — par le même chemin qu'un appui sur la tuile.
    ///
    /// Le Hub peut reconnaître une action que ce fil ne propose pas : le
    /// catalogue reste la vérité d'écran.
    @MainActor
    @discardableResult
    private func openDraft(_ draft: FinanceTextDraft) async -> Bool {
        guard let kind = draft.kind,
              let entry = entries.first(where: { $0.kind == kind }), entry.isActionable() else {
            draftNotice = FinanceStrings.draftActionUnavailable
            return false
        }
        await surface.textDrafts.put(draft)
        await admit(entry)
        return true
    }

    // MARK: - Sélection

    private func open(kind: FinanceEntryKind) {
        guard let entry = entries.first(where: { $0.kind == kind }), entry.isActionable() else { return }
        Task { await admit(entry) }
    }

    /// Ouvre une entrée, après l'élévation que le Hub exige (`requiresStepUp`,
    /// capacités `PILOT` / `LIMITED` — §2.1).
    ///
    /// C'est le **niveau relu** qui décide, pas le `true` rendu par `elevate` :
    /// ce booléen dit seulement que l'appareil est content (§33). Élévation
    /// refusée ou annulée ⇒ le parcours ne s'ouvre pas.
    private func admit(_ entry: FinanceCatalogEntry) async {
        if entry.requiresStepUp == true {
            if await surface.stepUp.currentLevel < Self.hubStepUpLevel {
                _ = try? await surface.stepUp.elevate(to: Self.hubStepUpLevel)
            }
            let level = await surface.stepUp.currentLevel
            await MainActor.run { stepUpLevel = level }
            guard level >= Self.hubStepUpLevel else { return }
        }
        await MainActor.run { onSelect(entry) }
    }

    /// Le contrat ne fixe pas le niveau : le plus faible qui constitue une
    /// élévation. Le parcours garde ses propres exigences au moment de payer.
    private static let hubStepUpLevel: StepUpLevel = .pin

    /// Ce que le serveur a répondu quand il a refusé le catalogue, prêt à
    /// afficher. `nil` : il n'a rien dit d'affichable — l'écran garde alors sa
    /// propre phrase plutôt que d'en inventer une.
    private static func serverReason(of outcome: Result<[FinanceCatalogEntry], FinanceError>) -> String? {
        guard case .failure(let error) = outcome else { return nil }
        return serverText(for: error)
    }

    /// Les mots du serveur pour cet échec, ou `nil` s'il n'en a pas eu.
    /// Rien n'est inventé à la place : l'écran garde sa propre phrase.
    private static func serverText(for error: FinanceError) -> String? {
        guard case .server(let text)? = FinanceErrorExplanations.shared.explanation(for: error)
        else { return nil }
        return text
    }

    // MARK: - Chargement

    private func loadCatalog() async {
        await MainActor.run { phase = .loading }

        let outcome = await surface.catalog.load(for: context)
        guard case .success(let resolved) = outcome else {
            // Catalogue injoignable : on ne garde pas les entrées précédentes.
            // Les proposer sous un catalogue qu'on n'a pas pu relire ouvrirait
            // des parcours sous des conditions qui ne sont peut-être plus.
            //
            // Le refus du serveur est affiché **tel qu'il est écrit**. Le hub
            // refusait `conversationType=SELF` (« should be of type
            // ConversationType ») et l'écran répondait « service indisponible » :
            // une phrase qui laisse chercher du côté du réseau, du pays ou du
            // compte, alors que le serveur avait nommé la cause exacte.
            let reason = Self.serverReason(of: outcome)
            await MainActor.run {
                entries = []
                catalogRefusal = reason
                phase = .failed
            }
            return
        }
        await MainActor.run { catalogRefusal = nil }

        // Une entrée périmée est écartée à la lecture, pas seulement grisée à
        // l'affichage : le catalogue qui l'a autorisée n'est plus d'actualité,
        // et la garder proposerait un parcours sous des conditions expirées.
        let live = resolved.filter { $0.isValid() }

        await MainActor.run {
            entries = live
            phase = live.isEmpty ? .empty : .loaded
        }
    }

    /// Solde, niveau d'authentification et dernières opérations.
    ///
    /// Les trois en parallèle : ils ne dépendent pas les uns des autres, et les
    /// enchaîner ferait attendre le solde derrière un relevé.
    private func loadAccount() async {
        // Aucune lecture du compte sans droit de consultation : pays fermé,
        // couche suspendue ou `FINANCE_READ` refusé ne partent pas sur le
        // réseau. Le solde reste « indisponible » — jamais zéro.
        guard await session.canReadAccount else {
            let level = await surface.stepUp.currentLevel
            await MainActor.run {
                balanceState = .unavailable
                recent = []
                // Consultation refusée : c'est un relevé qu'on n'a pas le
                // droit de lire, pas un compte sans opération.
                historyState = .unavailable(session.restriction.map(FinanceStrings.sessionRestrictionDetail))
                stepUpLevel = level
            }
            return
        }
        async let level = surface.stepUp.currentLevel
        async let history = surface.transactionHistory.history(cursor: nil, limit: 3)
        await loadBalance()

        let resolvedLevel = await level
        let resolvedHistory = await history

        await MainActor.run {
            stepUpLevel = resolvedLevel
            // Un relevé indisponible ne fait pas d'erreur sur cette page — le
            // solde reste lisible — mais il se **dit**. La section s'escamotait,
            // et une absence de service se lisait comme un compte vierge.
            switch resolvedHistory {
            case .success(let page):
                recent = page.entries
                historyState = page.entries.isEmpty ? .empty : .entries(page.entries)
            case .failure(let error):
                recent = []
                historyState = .unavailable(Self.serverText(for: error))
            }
        }
    }

    private func loadBalance() async {
        await MainActor.run { balanceState = .loading }
        let result = await surface.balance.execute(forceRefresh: false)
        await MainActor.run {
            switch result {
            case .success(let value): balanceState = .ready(value)
            case .failure:            balanceState = .unavailable
            }
        }
    }

    /// Élève la session au niveau code.
    ///
    /// Le résultat n'est pas affiché comme un succès : c'est le niveau relu qui
    /// fait disparaître la carte. Un `true` rendu par `elevate` dit seulement
    /// que l'appareil est content — §33.
    private func configurePIN() async {
        _ = try? await surface.stepUp.elevate(to: .pin)
        let level = await surface.stepUp.currentLevel
        await MainActor.run { stepUpLevel = level }
    }

    /// La carte n'apparaît que si l'on **sait** qu'aucun code n'est posé.
    ///
    /// Tant que le niveau n'est pas lu, elle reste absente : proposer de
    /// configurer un code à quelqu'un qui en a déjà un apprend à ignorer la
    /// carte, et c'est celle-ci qu'on veut qu'il lise.
    private var needsPINSetup: Bool {
        guard let stepUpLevel else { return false }
        return stepUpLevel < .pin
    }

    // MARK: - Libellés

    private var totalBalanceTitle: String {
        FinanceLocalization.string("wallet_total_balance", fallback: "Solde total")
    }

    private var accountName: String {
        guard case .ready(let account) = balanceState, !account.name.isEmpty else {
            return FinanceLocalization.string("wallet_account", fallback: "Mon compte")
        }
        return account.name
    }

    private func formatted(_ amount: Decimal, _ code: String) -> String {
        let parts = WalletAmountText.split(amount, code)
        return parts.prefix + parts.digits + (parts.suffix.isEmpty ? "" : " " + parts.suffix)
    }

    private var balanceBlockState: WalletBalanceBlock.State {
        switch balanceState {
        case .loading:
            return .loading
        case .ready(let account):
            return .amount(Decimal(account.balance), currencyCode: account.currency)
        case .unavailable:
            return .unavailable(
                message: FinanceLocalization.string(
                    "wallet_balance_unavailable",
                    fallback: "Solde indisponible. Toucher pour réessayer."),
                retry: { Task { await loadBalance() } }
            )
        }
    }
}
