//
//  SheetActionView.swift
//  chatpreview
//
//  Created by Asyst on 7/5/25.
//

import SwiftUI
import SDWebImageSwiftUI
import UniformTypeIdentifiers
import PDFKit
import QuickLook
import WaanguSharedUI
import WaanguCoreKit

// MARK: - FileView

struct FileView: View {
    @State private var showFilePicker = false
    @State private var selectedFileURLs: [URL] = []
    @State private var previewFileURL: URL? = nil
    @State private var showPreview = false
    @State private var recentDocuments: [MessageDataItem] = []
    let conversationId: String
    let loadRecentDocuments: () async -> [MessageDataItem]
    var allowMultipleSelection: Bool = true
    var onSendFiles: (([URL]) -> Void)?
    var onDismiss: (() -> Void)?
    let translationService: (any TranslationServiceProtocol)?
    
    init(
        conversationId: String,
        loadRecentDocuments: @escaping () async -> [MessageDataItem],
        allowMultipleSelection: Bool = true,
        translationService: (any TranslationServiceProtocol)? = nil,
        onSendFiles: (([URL]) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.conversationId = conversationId
        self.loadRecentDocuments = loadRecentDocuments
        self.allowMultipleSelection = allowMultipleSelection
        self.translationService = translationService
        self.onSendFiles = onSendFiles
        self.onDismiss = onDismiss
    }

    var body: some View {
        NavigationView {
            VStack {
                Spacer().frame(height: 10)
                VStack {
                    HStack {
                        Spacer().frame(width: 24)
                        Image(systemName: "cloud").resizable().scaledToFit().frame(height: 28).foregroundStyle(AppColors.primary)
                        Spacer().frame(width: 16)
                        Text(t(ChatTranslationKeys.FILE_SELECT_FROM_FILES)).font(.headline).foregroundStyle(AppColors.primary)
                        Spacer()
                    }
                    .padding(.vertical, 20)
                    .onTapGesture { showFilePicker = true }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .padding(.horizontal, 20)

                Spacer().frame(height: 30)

                VStack {
                    if !selectedFileURLs.isEmpty {
                        List {
                            Section(t(ChatTranslationKeys.FILE_SELECTED_FILES)) {
                                ForEach(selectedFileURLs, id: \.self) { url in
                                    HStack {
                                        Spacer().frame(width: 10)
                                        FileThumbnailView(fileURL: url, size: CGSize(width: 70, height: 70)).cornerRadius(12).clipped()
                                        Spacer().frame(width: 16)
                                        VStack(alignment: .leading, spacing: 8) {
                                            Text(url.lastPathComponent.removingPercentEncoding ?? "")
                                                .font(.title3).bold().foregroundStyle(Color.primary).lineLimit(1).truncationMode(.middle)
                                            Text(getFileSizeString(for: url)).font(.headline).foregroundStyle(Color(.systemGray))
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 10)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        previewFileURL = url
                                        showPreview = true
                                    }
                                }
                            }
                        }
                    } else if !recentDocuments.isEmpty {
                        List {
                            Section(t(ChatTranslationKeys.FILE_RECENTLY_SENT)) {
                                ForEach(recentDocuments, id: \.codeMessage) { msg in
                                    recentDocRow(msg)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            if let url = resolveFileURL(for: msg) {
                                                previewFileURL = url
                                                showPreview = true
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .background(Color(.systemBackground))
                .cornerRadius(12)

                if selectedFileURLs.isEmpty && recentDocuments.isEmpty {
                    VStack {
                        Spacer().frame(height: 80)
                        Image(systemName: "doc.text.fill").resizable().scaledToFit().frame(width: 70, height: 70).foregroundStyle(Color(.systemGray))
                        Spacer().frame(height: 16)
                        Text(t(ChatTranslationKeys.FILE_EMPTY)).font(.title2).foregroundStyle(Color(.systemGray)).bold()
                        Spacer()
                    }
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task(id: conversationId) {
                await reloadRecentDocuments()
            }
            .onDisappear {
                selectedFileURLs.removeAll()
                previewFileURL = nil
                showPreview = false
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(t(ChatTranslationKeys.GALLERY_CLOSE)) {
                        selectedFileURLs.removeAll()
                        onDismiss?()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        sendSelectedFiles()
                    }) {
                        Text(common("send")).font(.headline).bold().foregroundColor(AppColors.primary)
                    }
                    .opacity(selectedFileURLs.isEmpty ? 0 : 1)
                    .disabled(selectedFileURLs.isEmpty)
                    .animation(.easeInOut, value: selectedFileURLs.isEmpty)
                }
            }
        }
        .chatAppearanceSheet(isPresented: $showFilePicker) {
            DocumentPickerView(
                allowMultiple: allowMultipleSelection,
                onFilesSelected: { urls in
                    selectedFileURLs = urls
                    if urls.count == 1, let url = urls.first {
                        previewFileURL = url
                        showPreview = true
                    }
                    showFilePicker = false
                }
            )
            .presentationDragIndicator(.visible)
        }
        .chatAppearanceSheet(isPresented: $showPreview) {
            if let url = previewFileURL {
                DocumentFilePreview(
                    fileURL: url,
                    translationService: translationService,
                    onSend: {
                    sendSelectedFiles(singleURL: url)
                })
            }
        }
    }

    private func sendSelectedFiles(singleURL: URL? = nil) {
        let urls = singleURL.map { [$0] } ?? selectedFileURLs
        guard !urls.isEmpty else { return }
        onSendFiles?(urls)
        selectedFileURLs.removeAll()
        Task { await reloadRecentDocuments() }
    }

    private func reloadRecentDocuments() async {
        recentDocuments = await loadRecentDocuments()
    }

    // MARK: - Recent doc row

    @ViewBuilder
    private func recentDocRow(_ msg: MessageDataItem) -> some View {
        let kind = DocumentPresentationKind.from(
            fileName: msg.message.fileName,
            mimeType: msg.message.mimeType
        )
        let resolvedURL = resolveFileURL(for: msg)

        HStack {
            Spacer().frame(width: 10)

            if kind.usesRichPreview, let url = resolvedURL {
                FileThumbnailView(fileURL: url, size: CGSize(width: 70, height: 70))
                    .cornerRadius(12).clipped()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray5))
                    .frame(width: 70, height: 70)
                    .overlay(
                        Image(systemName: kind.systemImageName)
                            .font(.title)
                            .foregroundStyle(kind.iconColor)
                    )
            }

            Spacer().frame(width: 16)
            VStack(alignment: .leading, spacing: 8) {
                Text(msg.message.fileName ?? t(ChatTranslationKeys.FILE_DOCUMENT))
                    .font(.title3).bold().foregroundStyle(Color.primary).lineLimit(1).truncationMode(.middle)
                HStack(spacing: 4) {
                    Text(
                        kind.metadataLine(
                            fileName: msg.message.fileName,
                            fileURL: resolvedURL,
                            sizeBytes: msg.message.size
                        )
                    )
                    Text("·")
                    Text(msg.displayTime)
                }
                .font(.headline).foregroundStyle(Color(.systemGray))
            }
            Spacer()
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func resolveFileURL(for msg: MessageDataItem) -> URL? {
        guard let raw = msg.message.file?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        let originalURL: URL? = if let url = URL(string: raw), url.scheme != nil {
            url
        } else {
            URL(fileURLWithPath: raw)
        }

        if let url = originalURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }

        let ext = msg.message.fileName.flatMap {
            let e = ($0 as NSString).pathExtension.lowercased()
            return e.isEmpty ? nil : e
        } ?? (originalURL?.pathExtension.lowercased() ?? "")

        if let diskURL = DiskMediaManager.shared.loadFileFromDisk(
            fileName: msg.codeMessage, ext: ext, pathName: .CHAT
        ) {
            return diskURL
        }

        return originalURL
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Document File Preview (full interactive preview via QuickLook)

struct DocumentFilePreview: View {
    let fileURL: URL
    let onSend: () -> Void
    let translationService: (any TranslationServiceProtocol)?
    @Environment(\.dismiss) private var dismiss

    init(
        fileURL: URL,
        translationService: (any TranslationServiceProtocol)? = nil,
        onSend: @escaping () -> Void
    ) {
        self.fileURL = fileURL
        self.translationService = translationService
        self.onSend = onSend
    }

    private var fileName: String {
        fileURL.lastPathComponent.removingPercentEncoding ?? fileURL.lastPathComponent
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                DocumentPreviewContent(url: fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 4) {
                    Divider()
                    HStack(spacing: 12) {
                        Image(systemName: previewDocIcon)
                            .resizable().scaledToFit().frame(width: 24)
                            .foregroundColor(previewDocIconColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(fileName)
                                .font(.subheadline).bold()
                                .lineLimit(2).truncationMode(.tail)
                            Text(previewSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .background(Color(.systemBackground))
            }
            .navigationTitle(t(ChatTranslationKeys.FILE_PREVIEW_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(common("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        onSend()
                        dismiss()
                    }) {
                        Text(common("send")).font(.headline).bold()
                    }
                }
            }
        }
    }

    private var previewSubtitle: String {
        let ext = fileURL.pathExtension.uppercased()
        let size = getFileSizeString(for: fileURL)
        if fileURL.pathExtension.lowercased() == "pdf" {
            let pages = PDFDocument(url: fileURL)?.pageCount ?? 0
            return "\(t(ChatTranslationKeys.FILE_PAGES, args: ["\(pages)"])) · \(ext) · \(size)"
        }
        return "\(ext) · \(size)"
    }

    private var previewDocIcon: String {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return "doc.fill"
        case "xls", "xlsx", "csv": return "tablecells.fill"
        case "ppt", "pptx": return "rectangle.fill.on.rectangle.fill"
        default: return "doc.text.fill"
        }
    }

    private var previewDocIconColor: Color {
        switch fileURL.pathExtension.lowercased() {
        case "pdf": return .red
        case "doc", "docx": return .blue
        case "xls", "xlsx", "csv": return .green
        case "ppt", "pptx": return .orange
        default: return .gray
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - QLPreviewController wrapper for full interactive document preview

private struct DocumentPreviewContent: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}

// MARK: - SheetActionView

struct SheetActionView: View {
    let onDismiss: () -> Void
    let onSendMedia: (_ caption: String) -> Void
    let onOpenMediaEditor: (GalleryMedia) -> Void
    let onSendFiles: (([URL]) -> Void)?
    let onSendContacts: (([ContactItem]) -> Void)?
    let onSendLocation: ((ChatLocationItem) -> Void)?
    let onSendPoll: ((_ question: String, _ options: [String], _ allowsMultipleAnswers: Bool) -> Void)?

    /// Faisceau financier de la conversation. `nil` ⇒ graphe sans finance.
    let financeSurface: ChatFinanceSurface?

    /// Le parcours financier ouvert **dans la feuille**.
    ///
    /// Porté par l'hôte et non par un `@State` local : la conversation doit
    /// pouvoir le refermer — à la fermeture de la feuille, à un changement de
    /// fil — sans attendre que la feuille veuille bien s'en apercevoir.
    var financeEntry: Binding<FinanceCatalogEntry?>?

    /// Construit l'écran d'un parcours. Fourni par la conversation, qui détient
    /// la table des destinations — la dupliquer ici en donnerait deux.
    var financeDestination: ((FinanceCatalogEntry) -> AnyView)?
    let financeContext: ChatFinanceContext?
    /// Le hub **propose** ; il n'exécute jamais. Le choix remonte ici et la
    /// décision d'ouvrir un parcours appartient à l'appelant.
    let onSelectFinanceEntry: ((FinanceCatalogEntry) -> Void)?
    let conversationId: String
    /// Waangu Copilot de l'onglet Waangu : ce fil, et le fil direct d'un contact.
    let copilotHost: CopilotConversationHost?
    let copilotMessaging: WalletPaymentFlowViewModel?
    /// La conversation Copilot — la même partout.
    let copilotStore: (any CopilotConversationStoring)?
    let loadRecentDocuments: () async -> [MessageDataItem]
    let translationService: (any TranslationServiceProtocol)?

    @ObservedObject var galleryViewModel: GalleryViewModel
    @ObservedObject var mediaViewModel: PHMediaManagerViewModel

    init(
        onDismiss: @escaping () -> Void,
        onSendMedia: @escaping (_ caption: String) -> Void,
        onOpenMediaEditor: @escaping (GalleryMedia) -> Void,
        onSendFiles: (([URL]) -> Void)? = nil,
        onSendContacts: (([ContactItem]) -> Void)? = nil,
        onSendLocation: ((ChatLocationItem) -> Void)? = nil,
        onSendPoll: ((_ question: String, _ options: [String], _ allowsMultipleAnswers: Bool) -> Void)? = nil,
        financeSurface: ChatFinanceSurface? = nil,
        financeContext: ChatFinanceContext? = nil,
        onSelectFinanceEntry: ((FinanceCatalogEntry) -> Void)? = nil,
        financeEntry: Binding<FinanceCatalogEntry?>? = nil,
        financeDestination: ((FinanceCatalogEntry) -> AnyView)? = nil,
        conversationId: String,
        copilotHost: CopilotConversationHost? = nil,
        copilotMessaging: WalletPaymentFlowViewModel? = nil,
        copilotStore: (any CopilotConversationStoring)? = nil,
        loadRecentDocuments: @escaping () async -> [MessageDataItem],
        translationService: (any TranslationServiceProtocol)? = nil,
        galleryViewModel: GalleryViewModel,
        mediaViewModel: PHMediaManagerViewModel
    ) {
        self.onDismiss = onDismiss
        self.onSendMedia = onSendMedia
        self.onOpenMediaEditor = onOpenMediaEditor
        self.onSendFiles = onSendFiles
        self.onSendContacts = onSendContacts
        self.onSendLocation = onSendLocation
        self.onSendPoll = onSendPoll
        self.financeSurface = financeSurface
        self.financeContext = financeContext
        self.onSelectFinanceEntry = onSelectFinanceEntry
        self.financeEntry = financeEntry
        self.financeDestination = financeDestination
        self.conversationId = conversationId
        self.copilotHost = copilotHost
        self.copilotMessaging = copilotMessaging
        self.copilotStore = copilotStore
        self.loadRecentDocuments = loadRecentDocuments
        self.translationService = translationService
        self.galleryViewModel = galleryViewModel
        self.mediaViewModel = mediaViewModel
    }

    @State private var caption: String = ""
    @StateObject private var keyboard = KeyboardResponder()
    @State private var selectedTab: TabAction = .gallery

    /// Hauteur courante, pilotée par l'onglet.
    @State private var sheetDetent: PresentationDetent = SheetActionView.restingDetent

    /// Les deux hauteurs admissibles, **constantes**.
    ///
    /// Stockées plutôt que construites à chaque calcul du corps : un ensemble
    /// reconstruit change d'identité, et SwiftUI peut alors réinitialiser la
    /// présentation au lieu de simplement déplacer la feuille.
    private static let detents: Set<PresentationDetent> = [SheetActionView.restingDetent, .large]

    /// Hauteur de repos, celle de tous les onglets sauf Waangu.
    ///
    /// L'onglet Waangu porte un hub, puis des parcours financiers entiers —
    /// saisie de montant, récapitulatif, confirmation. À hauteur partielle, le
    /// bouton de confirmation se retrouve sous le bord de la feuille, et
    /// l'utilisateur confirme un paiement sans voir le total. Les autres onglets
    /// — galerie, contacts, sondage — sont des sélecteurs : les agrandir les
    /// laisserait à moitié vides.
    ///
    /// Nommée plutôt qu'écrite deux fois : elle sert à l'état initial **et** au
    /// retour, et deux littéraux qui doivent rester égaux finissent par diverger.
    // `.medium` plutôt qu'une fraction : c'est un détent **standard**, auquel
    // UIKit associe un identifiant connu. Une fraction sur mesure reçoit un
    // identifiant généré, et le retour programmatique vers un tel détent est
    // précisément ce qui ne fonctionnait pas.
    private static let restingDetent: PresentationDetent = .medium

    @ViewBuilder
    private var content: some View {
        Group {
            switch selectedTab {
            case .gallery:
                GalleryView(
                    viewModel: mediaViewModel,
                    translationService: translationService,
                    selectingEnded: { _ in },
                    onDirectSelect: { media in
                        onOpenMediaEditor(media)
                    }
                )
            case .contact:
                ContactPicker(
                    viewModel: galleryViewModel,
                    translationService: translationService,
                    onDismiss: {
                    onDismiss()
                }, onSendContacts: { contacts in
                    onSendContacts?(contacts)
                })
            case .location:
                LocationPickerView(
                    galleryVM: galleryViewModel,
                    translationService: translationService,
                    onSendLocation: { location in
                        onSendLocation?(location)
                    },
                    onDismiss: {
                        onDismiss()
                    }
                )
            case .file:
                FileView(
                    conversationId: conversationId,
                    loadRecentDocuments: loadRecentDocuments,
                    translationService: translationService,
                    onSendFiles: { urls in
                        onSendFiles?(urls)
                    },
                    onDismiss: { onDismiss() }
                )
            case .poll:
                PollComposerView(
                    translationService: translationService,
                    onSendPoll: { question, options, allowsMultipleAnswers in
                        onSendPoll?(question, options, allowsMultipleAnswers)
                    },
                    onDismiss: {
                        onDismiss()
                    }
                )
            case .wallet:
                // L'onglet existait déjà, libellé « Waangu Wallet », et rendait
                // `EmptyView()`. L'entrée du chapitre 16 n'était donc pas à
                // créer : elle était là, et vide.
                if let financeSurface, let financeContext {
                    FinanceHomeView(
                        surface: financeSurface,
                        context: financeContext,
                        onSelect: { entry in
                            // Rester dans la feuille quand l'hôte sait l'y
                            // présenter. Le repli ferme la feuille et remonte
                            // à la conversation — c'est l'ancien chemin, gardé
                            // pour les hôtes qui ne fournissent pas de table.
                            if let financeEntry, financeDestination != nil {
                                financeEntry.wrappedValue = entry
                            } else {
                                onSelectFinanceEntry?(entry)
                            }
                        },
                        translationService: translationService,
                        copilotHost: copilotHost,
                        copilotMessaging: copilotMessaging,
                        copilotStore: copilotStore
                    )
                } else {
                    FinanceHubUnavailableView()
                }
            case .reply, .unknown:
                EmptyView()
            }
        }
        .id(selectedTab)
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.3), value: selectedTab)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            VStack {
                Spacer()

                Group {
                    if !mediaViewModel.selectedMedia.isEmpty && selectedTab == .gallery {
                        textFieldCaption()
                    } else {
                        VStack(spacing: 0) {
                            Divider().background(Color.gray.opacity(0.1))
                            WTabStrip(
                                items: sheetTabItems,
                                selection: $selectedTab,
                                style: .iconAbove(tint: AppColors.primary)
                            )
                            .padding(.top, 10)
                            .padding(.bottom, safeAreaInsets.bottom)
                            .background(BlurView(style: .systemThinMaterial))
                            .frame(height: 80)
                        }
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: mediaViewModel.selectedMedia.count)
            }
        }
        .ignoresSafeArea(edges: .bottom)
        // Le parcours financier se présente **sur** la feuille, qui reste
        // ouverte dessous.
        //
        // Il fermait la feuille pour rouvrir un plein écran depuis la
        // conversation : deux animations, un écran de discussion qui
        // réapparaissait entre les deux, et la perte de l'onglet d'où l'on
        // venait au retour.
        //
        // `FinanceNavigationScope` est reposé ici parce que la pile de
        // navigation du plein écran n'existe pas sur ce chemin, et que les
        // écrans de parcours poussent leurs propres destinations.
        // Variante qui reporte l'apparence choisie dans l'application : cette
        // feuille imbriquée n'hérite pas du `preferredColorScheme` du fil.
        .chatAppearanceSheet(item: financeEntry ?? .constant(nil)) { entry in
            if let financeDestination {
                FinanceNavigationScope { financeDestination(entry) }
                    .environment(\.financeFlowSurface, financeSurface)

                    .environment(\.financeOperationKeys, financeSurface?.operationKeys ?? .processLocal)
            }
        }
        // Repère de mesure pour le test d'interface.
        //
        // Un identifiant posé sur la racine se **propage à toute la
        // descendance** : chaque bouton de la feuille portait « chatActionsSheet »,
        // si bien qu'une requête par identifiant devenait ambiguë et que
        // `firstMatch` désignait un noeud différent selon l'onglet affiché.
        //
        // Un repère de 1 pt, aligné en haut, n'a pas d'enfants : son ordonnée
        // est celle du bord supérieur de la feuille, et rien d'autre ne porte
        // son identifiant.
        .overlay(alignment: .top) {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("sheetTopProbe")
                .accessibilityLabel("sheet top probe")
        }
        // La hauteur est une **fonction de l'onglet**, pas un état à part.
        //
        // L'ensemble des hauteurs, lui, reste **fixe** : SwiftUI le lit à la
        // présentation, et le rendre conditionnel — ce qu'une version précédente
        // faisait — retirait `.large` de la liste sur l'onglet Waangu, si bien
        // que la feuille ne montait plus du tout.
        //
        // Deux tentatives ont échoué avant celle-ci, et pour la même raison :
        // tant que la hauteur vit dans un `@State`, elle peut rester sur
        // `.large` — la feuille montait sur Waangu et n'en redescendait plus.
        // Écrire la sélection en lecture seule supprime le problème à la racine :
        // il n'existe plus de valeur mémorisée capable d'être périmée.
        //
        // Le `set` est volontairement vide : un glissement de l'utilisateur ne
        // fixe pas une hauteur qui contredirait l'onglet affiché.
        .presentationDetents(SheetActionView.detents, selection: $sheetDetent)
        .onChange(of: selectedTab) { _, newTab in
            sheetDetent = (newTab == .wallet) ? .large : SheetActionView.restingDetent
        }
        // Passage par UIKit pour **rétrécir**.
        //
        // Constat du test d'interface : la feuille s'agrandit à la demande mais
        // ne redescend pas, quelle que soit la façon d'écrire la sélection
        // SwiftUI — état, binding calculé, fraction ou détent standard. Les
        // quatre variantes donnent le même bord supérieur à 72 pt après retour.
        //
        // `UISheetPresentationController` accepte le changement dans les deux
        // sens. On ne remplace pas la déclaration SwiftUI — elle reste la source
        // des hauteurs — on la force à s'appliquer.
        .background(SheetDetentEnforcer(wantsLarge: selectedTab == .wallet))
        .presentationDragIndicator(.visible)
    }

    func textFieldCaption() -> some View {
        HStack(spacing: 4) {
            TextField("", text: $caption, prompt: Text(t(ChatTranslationKeys.FILE_ADD_CAPTION)).foregroundColor(.gray))
                .padding(12)
                .background(
                    BlurView(style: .systemMaterialDark)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                )
                .accentColor(.white)
                .foregroundColor(.white)
                .padding(.horizontal, 1)

            Button(action: {
                onSendMedia(caption)
                caption = ""
            }) {
                Text(common("send"))
                    .foregroundColor(.white)
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.primary)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, keyboard.currentHeight + safeAreaInsets.bottom)
        .animation(.easeOut(duration: 0.25), value: keyboard.currentHeight)
        .edgesIgnoringSafeArea(.bottom)
    }

    /// Built here rather than on `TabAction`, so the sheet keeps control of which
    /// tabs it offers and in what order — `.unknown` is deliberately not one of them.
    private var sheetTabItems: [WTabItem<TabAction>] {
        [
            WTabItem(id: .gallery, title: t(ChatTranslationKeys.SHEET_MEDIA), systemImage: "photo.fill"),
            WTabItem(id: .wallet, title: t(ChatTranslationKeys.SHEET_WAANGU), systemImage: "w.circle.fill"),
            WTabItem(id: .file, title: t(ChatTranslationKeys.SHEET_FILE), systemImage: "doc.text.fill"),
            WTabItem(id: .location, title: t(ChatTranslationKeys.SHEET_LOCATION), systemImage: "location.fill"),
            WTabItem(id: .contact, title: t(ChatTranslationKeys.SHEET_CONTACT), systemImage: "person.circle.fill"),
            WTabItem(id: .poll, title: t(ChatTranslationKeys.SHEET_POLL), systemImage: "chart.bar.fill"),
            WTabItem(id: .reply, title: t(ChatTranslationKeys.SHEET_REPLY), systemImage: "arrowshape.turn.up.left.fill")
        ]
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}


// MARK: - Application de la hauteur

/// Impose la hauteur au contrôleur de présentation sous-jacent.
///
/// Vue de fond sans rendu : elle n'existe que pour remonter jusqu'au
/// `UISheetPresentationController` de la feuille, que SwiftUI n'expose pas.
private struct SheetDetentEnforcer: UIViewControllerRepresentable {

    let wantsLarge: Bool

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        // Reporté d'un tour de boucle : au moment de la mise à jour, la vue
        // n'est pas encore rattachée à sa fenêtre, donc `sheetPresentationController`
        // est nil.
        DispatchQueue.main.async {
            guard let sheet = controller.sheetPresentationController
                    ?? controller.parent?.sheetPresentationController
                    ?? controller.presentingViewController?.presentedViewController?
                        .sheetPresentationController else { return }

            let target: UISheetPresentationController.Detent.Identifier =
                wantsLarge ? .large : .medium

            guard sheet.selectedDetentIdentifier != target else { return }
            sheet.animateChanges {
                sheet.selectedDetentIdentifier = target
            }
        }
    }
}
