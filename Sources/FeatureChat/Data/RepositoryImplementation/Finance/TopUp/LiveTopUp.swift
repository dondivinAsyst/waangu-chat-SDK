//
//  LiveTopUp.swift
//  FeatureChat
//
//  Phase 5.3 — recharger une ligne (INTEGRATION_CHAT_FINANCE.md §5.3).
//

import Foundation
import WaanguCoreKit

/// `TopUpOrdering` servi par Chat Core (§5.3).
///
/// **Catalogue** : le numéro est d'abord résolu par le serveur
/// (`/top-up/resolve-msisdn`), puis les produits du pays sont lus
/// (`/top-up/catalogue?country=`). Les deux appels sont nécessaires : le second
/// seul ne dirait rien de l'opérateur, et le premier seul ne propose rien.
///
/// **Aucun filtrage par opérateur ici.** Le catalogue ne publie pas d'opérateur
/// sur ses produits — seulement un `billerId` — et `operatorHint` est déclaré
/// non autoritatif par la réponse elle-même. Rapprocher les deux serait une
/// devinette : elle viderait la liste quand les noms diffèrent, et proposerait
/// le mauvais opérateur quand ils se ressemblent. C'est le serveur qui tranche,
/// au prepare.
///
/// `order` reste **fermé** : le contrat prépare, fait confirmer, puis exécute.
struct LiveTopUp: TopUpOrdering {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let session: FinanceCoreSessionRepository
    /// Prepare → devis gardé pour l'execute — le socle commun des ops quotées.
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String
    /// Numéro normalisé par le serveur, retenu entre le catalogue et le prepare.
    var resolutions = TopUpResolutionMemo()

    /// Ce service demande toujours un devis : `/top-up/prepare`, puis la
    /// confirmation humaine. Un refus du prepare est **le** résultat.
    var providesQuotes: Bool { true }

    // MARK: - Catalogue

    func catalog(for msisdn: String) async -> Result<[TopUpProduct], FinanceError> {
        let typed = msisdn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return .success([]) }

        // Le numéro d'abord : sans lui le prepare partirait sur la saisie brute,
        // et `CF_044` est le refus d'un numéro irrésolu.
        let resolved: ResolvedMsisdnDTO
        switch await FinanceCoreError.capture({
            try await dataSource.resolveMsisdn(TopUpMsisdnRequest(msisdn: typed))
        }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceTopUp] resolve-msisdn failed: \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let dto):
            resolved = dto
        }
        await resolutions.remember(resolved, for: typed)

        // Le pays de `/experience/config` — celui du JWT, jamais choisi ici.
        let country = await session.country()
        switch await FinanceCoreError.capture({ try await dataSource.topUpCatalogue(country: country) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceTopUp] catalogue failed (country=\(country ?? "nil")): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let products):
            let offered = Self.products(from: products, operatorName: resolved.operatorHint ?? "")
            #if DEBUG
            // Le silence du succès a coûté un aller-retour : le catalogue
            // répondait `200` avec cinq produits, tous écartés, et l'écran
            // disait seulement « aucun forfait ». On dit maintenant lesquels.
            print("[FinanceTopUp] catalogue(country=\(country ?? "nil")): "
                  + "\(products.count) received, \(offered.count) offered — "
                  + products.map { "\($0.code)/\($0.kind ?? "nil")/\($0.status ?? "nil")" }
                      .joined(separator: " "))
            #endif
            return .success(offered)
        }
    }

    /// Les produits du catalogue, dans l'ordre où le serveur les rend.
    ///
    /// **Le catalogue est servi tel quel.** Ce que le serveur met sur cette
    /// route est ce qui s'affiche : aucune catégorie n'est jugée ici.
    ///
    /// Deux écarts seulement, et ni l'un ni l'autre n'est un avis sur le
    /// produit — ils lisent ce que le serveur dit de lui :
    /// - `status` autre qu'`ACTIVE` : le serveur l'annonce indisponible, et il
    ///   finirait en refus au premier geste (même règle qu'au catalogue des
    ///   facturiers).
    /// - montant ou devise absents : une tuile sans prix ne se choisit pas, et
    ///   aucun prix ne se devine.
    static func products(from entries: [TopUpProductDTO], operatorName: String) -> [TopUpProduct] {
        entries.compactMap { entry in
            guard (entry.status ?? "ACTIVE").uppercased() == "ACTIVE",
                  let minor = entry.amountMinor,
                  let currency = entry.currency, !currency.isEmpty
            else { return nil }
            let kind = kind(of: entry.kind)
            return TopUpProduct(
                id: entry.code,
                kind: kind,
                // Le libellé rédigé par le serveur ; à défaut le code, jamais
                // un intitulé fabriqué ici.
                labelKey: entry.label ?? entry.code,
                amount: FcoCardMapper.amount(minor: minor, currency: currency),
                currency: currency,
                operatorName: operatorName)
        }
    }

    /// La catégorie du catalogue → la nature affichée.
    ///
    /// **Rien n'est écarté pour sa catégorie : le catalogue est la décision du
    /// serveur.** C'est lui qui établit ce qui est offert sur ce marché, et un
    /// client qui trierait selon sa propre idée de ce qu'est une recharge
    /// masquerait un produit que le serveur vient d'ouvrir — sans que personne
    /// voie l'omission, ni côté app ni côté serveur.
    ///
    /// Une catégorie que ce client ne sait pas nommer devient donc
    /// `.unspecified` : le produit s'affiche, sous son libellé serveur, dans la
    /// grille sans intitulé de section. C'est aussi le cas de `TOPUP`, employé
    /// aujourd'hui pour le crédit d'appel **comme** pour le forfait data.
    ///
    /// `AIRTIME` et `DATA` sont le vocabulaire que le contrat publie (§5.3.1) ;
    /// le serveur ne l'envoie pas encore, et ils sont reconnus pour le jour où
    /// il le fera — ce jour-là, les sections reviennent toutes seules.
    static func kind(of raw: String?) -> TopUpKind {
        switch (raw ?? "").uppercased() {
        case "AIRTIME": return .airtime
        case "DATA":    return .data
        case "VOICE":   return .voice
        case "SMS":     return .sms
        case "BUNDLE":  return .bundle
        case "ROAMING": return .roaming
        default:        return .unspecified
        }
    }

    // MARK: - Devis

    /// `POST /top-up/prepare` — un devis à confirmer, jamais une recharge lancée.
    ///
    /// Corps publié (§5.3.1) : `conversationId` (absent ⇒ dossier `SELF`),
    /// `idempotencyKey` — posé par l'endpoint —, `productCode`, `msisdn`,
    /// `deviceId`. `channel` suit les autres prepares : son absence faisait
    /// refuser l'execute en `CF_021`.
    ///
    /// Le numéro envoyé est **celui que le serveur a normalisé**, quand le
    /// catalogue l'a appris ; la saisie sinon.
    func quote(_ request: TopUpOrderRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        // Une ligne par devis. `/top-up/bulk` rend un FCO **par ligne**, chacun
        // avec sa confirmation : un devis unique ne les représenterait pas.
        guard let line = request.lines.first, request.lines.count == 1 else {
            return .failure(.capabilityUnavailable)
        }

        let msisdn = await resolutions.normalized(for: line.msisdn) ?? line.msisdn
        var body: [String: Any] = [
            "productCode": line.productID,
            "msisdn": msisdn,
            "deviceId": deviceID(),
            "channel": "MOBILE",
        ]
        if let conversation = request.conversationID, !conversation.isEmpty {
            body["conversationId"] = conversation
        }
        let outcome = await quoting.prepare(.topUp, body: body, idempotency: idempotency)
        #if DEBUG
        if case .failure(let error) = outcome {
            print("[FinanceTopUp] prepare failed (product=\(line.productID)): \(error)")
        }
        #endif
        return outcome
    }

    /// `POST /top-up/bulk` — **un devis par ligne**, jamais un seul pour le lot.
    ///
    /// Le corps publié (§5.3.1) porte un seul `productCode` et la liste des
    /// numéros. La réponse rend un `QuotedPrepareResponse` par ligne : chacun
    /// repasse par l'acceptation commune, donc chacun a son propre permis, sa
    /// propre expiration et son propre execute.
    ///
    /// Une ligne refusée — gel conformité, devis illisible — **n'annule pas les
    /// autres** : elle est simplement absente du lot confirmable. Tout refuser
    /// parce qu'un numéro sur cinq est bloqué empêcherait de recharger les
    /// quatre que le serveur a acceptés.
    func quoteBatch(_ request: TopUpOrderRequest,
                    idempotency: IdempotencyContext) async -> Result<[TopUpQuotedLine], FinanceError> {
        guard let product = request.lines.first?.productID, !request.lines.isEmpty else {
            return .failure(.capabilityUnavailable)
        }
        if let refusal = await quoting.writeRefusal(for: .topUp) {
            return .failure(refusal)
        }

        // Le numéro normalisé par le serveur quand le catalogue l'a appris.
        var msisdns: [String] = []
        for line in request.lines {
            msisdns.append(await resolutions.normalized(for: line.msisdn) ?? line.msisdn)
        }
        let body = TopUpBulkRequest(
            conversationId: request.conversationID.flatMap { $0.isEmpty ? nil : $0 },
            productCode: product,
            msisdns: msisdns,
            deviceId: deviceID())

        switch await FinanceCoreError.capture({
            try await dataSource.topUpBulk(body, idempotency: idempotency)
        }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceTopUp] bulk failed (product=\(product), lines=\(msisdns.count)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let result):
            let responses = result.lines ?? []
            // Le serveur rend les lignes dans l'ordre envoyé : c'est ce qui
            // rattache un devis à son numéro. Sans cet ordre, rien dans la
            // réponse ne dit à qui appartient `fco_…`, et le compte rendu
            // nommerait le mauvais destinataire.
            guard responses.count == msisdns.count else {
                #if DEBUG
                print("[FinanceTopUp] bulk returned \(responses.count) lines for "
                      + "\(msisdns.count) numbers — no line is attributable")
                #endif
                return .failure(.server(statusCode: nil))
            }

            var quoted: [TopUpQuotedLine] = []
            for (msisdn, response) in zip(msisdns, responses) {
                let outcome = await quoting.accept(response, operation: .topUp,
                                                   correlationID: idempotency.correlationID)
                switch outcome {
                case .success(let quote):
                    quoted.append(TopUpQuotedLine(msisdn: msisdn, quote: quote))
                case .failure(let error):
                    #if DEBUG
                    print("[FinanceTopUp] bulk line refused (ref=\(response.financialIntentRef)): \(error)")
                    #endif
                }
            }
            // Aucune ligne confirmable : le refus du serveur **est** le
            // résultat, et il vaut mieux le dire que montrer un lot vide.
            guard !quoted.isEmpty else { return .failure(.complianceBlocked(displayReason: nil)) }
            return .success(quoted)
        }
    }

    /// **Jamais une recharge directe.** Le parcours passe par ``quote`` puis la
    /// confirmation explicite — §5.3, et §0.3.1.
    func order(_ request: TopUpOrderRequest,
               idempotency: IdempotencyContext) async -> Result<TopUpOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    // MARK: - Doute

    func requery(_ reference: FinancialReference) async -> Result<TopUpOrder, FinanceError> {
        let request = TopUpRefRequest(financialIntentRef: reference.id, conversationId: nil)
        switch await FinanceCoreError.capture({ try await dataSource.topUpRequery(request) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceTopUp] requery failed (ref=\(reference.id)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let overlay):
            #if DEBUG
            print("[FinanceTopUp] overlay: payment=\(overlay.paymentStatus ?? "nil") "
                  + "fulfillment=\(overlay.fulfillmentStatus ?? "nil") "
                  + "delivery=\(overlay.deliveryStatus ?? "nil")")
            #endif
            return .success(Self.order(from: overlay, reference: reference))
        }
    }

    /// L'overlay lu, en ordre d'une ligne.
    ///
    /// `/bulk` n'est pas ouvert : `bulkLineRefs` est donc lu mais ne fabrique
    /// pas de lignes — en inventer une par référence, sans statut propre,
    /// donnerait un résultat par destinataire dont aucun ne serait vrai.
    static func order(from overlay: TopUpOverlayDTO,
                      reference: FinancialReference) -> TopUpOrder {
        TopUpOrder(
            reference: reference,
            results: [TopUpLineResult(
                id: overlay.financialIntentRef,
                msisdn: overlay.msisdnMasked ?? "",
                status: status(of: overlay),
                failureReasonKey: nil)])
    }

    /// Le sort d'une recharge : le débit **et** la livraison.
    ///
    /// Un paiement abouti dont le crédit télécom n'est pas livré n'est pas un
    /// succès — c'est le `TOPUP_NOT_DELIVERED` des litiges (§litiges). Il
    /// devient « en attente de rapprochement », comme un `COMPLETED` sans
    /// `visualSuccessFinal` sur une carte (`FcoCardMapper.status`).
    ///
    /// Une valeur de livraison que ce client ne connaît pas n'est pas une
    /// livraison : rien n'autorise à la lire comme telle.
    ///
    /// Le vocabulaire est celui des cartes (`FcoCardMapper.paymentStatus`) :
    /// l'overlay emploie les mêmes mots, et `SUBMITTED` comme `SETTLED` n'ont
    /// pas de `PaymentStatus` de même nom.
    static func status(of overlay: TopUpOverlayDTO) -> PaymentStatus {
        FcoCardMapper.overlayStatus(payment: overlay.paymentStatus,
                                    fulfillment: overlay.fulfillmentStatus,
                                    delivery: overlay.deliveryStatus)
    }
}

/// Numéro normalisé par le serveur, par numéro saisi.
///
/// Le catalogue le reçoit, le prepare en a besoin : sans cette mémoire, le
/// prepare repartirait sur la saisie brute que le serveur venait de corriger.
actor TopUpResolutionMemo {
    private var resolved: [String: ResolvedMsisdnDTO] = [:]

    func remember(_ resolution: ResolvedMsisdnDTO, for typed: String) {
        resolved[typed] = resolution
    }

    func normalized(for typed: String) -> String? {
        guard let value = resolved[typed]?.msisdnNormalized, !value.isEmpty else { return nil }
        return value
    }
}
