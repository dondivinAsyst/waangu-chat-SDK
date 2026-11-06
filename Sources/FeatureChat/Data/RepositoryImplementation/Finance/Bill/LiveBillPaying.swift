//
//  LiveBillPaying.swift
//  FeatureChat
//
//  Phase 5.1 — payer une facture (INTEGRATION_CHAT_FINANCE.md §5.1).
//

import Foundation
import WaanguCoreKit

/// Pay Bill branché sur Chat Core (§5.1).
///
/// **Catalogue** : lu et affiché. Sa forme vient de la réponse réelle du
/// backend — une liste plate de facturiers, chacun portant sa catégorie.
///
/// **Formulaire** (`/pay-bill/schema`) : lu et affiché, forme lue sur la
/// réponse réelle.
///
/// **Inquiry** (`/pay-bill/inquiry`) : appelé pour de vrai, réponse brute
/// journalisée en DEBUG (`[FinanceBill]`) — sa forme n'est pas publiée, on la
/// cartographiera une fois lue. Le paiement suivra la même voie.
struct LiveBillPaying: BillPaying {

    let dataSource: any RemoteChatFinanceDataSourceProtocol
    let session: FinanceCoreSessionRepository
    /// Prepare → devis gardé pour l'execute — le socle commun des ops quotées.
    let quoting: LiveQuotedOperations
    let deviceID: @Sendable () -> String
    /// Version du formulaire lu, renvoyée avec l'inquiry.
    var schemas = BillSchemaMemo()

    func categories() async -> Result<[BillerCategory], FinanceError> {
        // Le pays de `/experience/config` — celui du JWT, jamais choisi ici.
        let country = await session.country()
        switch await FinanceCoreError.capture({ try await dataSource.billCatalogue(country: country) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceBill] catalogue failed (country=\(country ?? "nil")): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let billers):
            return .success(Self.categories(from: billers))
        }
    }

    func form(for billerID: String) async -> Result<DynamicBiller, FinanceError> {
        switch await FinanceCoreError.capture({ try await dataSource.billSchema(billerID: billerID) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceBill] schema failed (billerId=\(billerID)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let schema):
            // Les deux versions : un facturier peut redécouper ses étapes sans
            // toucher à ses champs, et l'inverse.
            await schemas.remember(Self.version(of: schema), for: billerID)
            return .success(Self.form(from: schema))
        }
    }

    // MARK: - Formulaire

    /// Le schéma du Biller Hub dans le modèle de formulaire existant.
    ///
    /// Le type `STRING` s'affiche en texte ; un nom qui désigne un téléphone
    /// prend le clavier téléphonique. Un type inconnu reste inconnu : l'écran
    /// bloque le champ plutôt que d'en deviner la saisie.
    static func form(from schema: BillerSchemaDTO) -> DynamicBiller {
        let fields = (schema.fields ?? []).enumerated().map { index, field in
            DynamicBillerField(
                fieldName: field.name, label: label(of: field),
                dataType: field.type ?? "", inputType: inputType(of: field),
                // Un `ENUM` n'a pas de longueur : le backend rend 0/0, et une
                // borne de 0 caractère rendrait toute valeur invalide.
                minLength: isChoice(field) ? nil : field.minLength,
                maxLength: isChoice(field) ? nil : field.maxLength,
                isRequired: field.required ?? false, regex: field.pattern ?? "",
                value: "", viewDisplay: field.visibility ?? "", valueRange: "", keyName: field.name,
                placeholder: "", fieldMapping: field.name, parent: "", minBy: "", mask: "",
                err: 0, message: "", isMapping: false, valueMask: "",
                // L'ordre voulu par le facturier ; à défaut, celui du JSON.
                priority: field.order ?? index,
                allowedValues: field.allowedValues ?? [],
                step: field.step)
        }
        return DynamicBiller(
            id: schema.billerId, name: schema.billerId, shortName: schema.billerId,
            description: "", logo: "", status: 1, serviceId: schema.schemaVersion ?? "",
            biller: schema.billerId, fieldList: fields, fetchFieldFormRaw: "",
            fetchFieldForm: nil, paymentDetail: [], type: "", requireQuery: 1,
            sections: sections(from: schema))
    }

    /// Les étapes du facturier, dans l'ordre qu'il donne.
    ///
    /// Une étape sans titre est écartée : un intitulé vide ne dit rien, et un
    /// intitulé inventé ici dirait autre chose que ce que le facturier voulait.
    /// Ses champs retombent alors dans le groupe sans nom, jamais dans le vide.
    static func sections(from schema: BillerSchemaDTO) -> [DynamicBillerSection] {
        (schema.steps ?? []).compactMap { step in
            let title = (step.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { return nil }
            return DynamicBillerSection(id: step.id, title: title,
                                        detail: step.description ?? "")
        }
    }

    /// Empreinte du schéma : forme **et** parcours.
    static func version(of schema: BillerSchemaDTO) -> String? {
        let parts = [schema.schemaVersion, schema.workflowVersion].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: "+")
    }

    /// Une liste de valeurs imposées : un choix, pas une saisie.
    static func isChoice(_ field: BillerSchemaFieldDTO) -> Bool {
        (field.type ?? "").uppercased() == "ENUM" || !(field.allowedValues ?? []).isEmpty
    }

    static func inputType(of field: BillerSchemaFieldDTO) -> String {
        if isChoice(field) { return "enum" }
        let semantic = (field.semanticType ?? "").uppercased()
        let name = field.name.lowercased()
        if semantic == "MSISDN" || name.contains("phone") || name.contains("msisdn") { return "phone" }
        switch (field.type ?? "").uppercased() {
        case "STRING", "TEXT", "":           return "text"
        case "NUMBER", "NUMERIC", "INTEGER": return "number"
        case "EMAIL":                        return "email"
        case "DATE":                         return "date"
        case let type:                       return type.lowercased()
        }
    }

    /// Libellé traduit, d'abord par la **nature** du champ (`semanticType`) —
    /// elle vaut pour tous les facturiers — puis par son nom ; sinon le nom,
    /// découpé (`accountRef` → « Account ref »), jamais la clé brute.
    static func label(of field: BillerSchemaFieldDTO) -> String {
        switch (field.semanticType ?? "").uppercased() {
        case "ACCOUNT_REF":  return FinanceStrings.billFieldAccountRef
        case "MSISDN":       return FinanceStrings.billFieldCustomerPhone
        case "METER":        return FinanceStrings.billFieldMeter
        case "INVOICE_REF":  return FinanceStrings.billFieldInvoiceRef
        default:             break
        }
        return label(of: field.name)
    }

    static func label(of name: String) -> String {
        switch name {
        case "accountRef":    return FinanceStrings.billFieldAccountRef
        case "customerPhone": return FinanceStrings.billFieldCustomerPhone
        case "meterNumber":   return FinanceStrings.billFieldMeter
        case "invoiceRef":    return FinanceStrings.billFieldInvoiceRef
        case "period":        return FinanceStrings.billFieldPeriod
        default:
            let spaced = name.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2",
                                                   options: .regularExpression)
                .replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
        }
    }

    // MARK: - Catalogue

    /// Facturiers regroupés par catégorie, dans l'ordre où le serveur les rend.
    ///
    /// Seuls les facturiers `ACTIVE` sont proposés : un facturier suspendu
    /// finirait en `CF_053` au premier geste.
    static func categories(from billers: [BillerCatalogueEntryDTO]) -> [BillerCategory] {
        var order: [String] = []
        var grouped: [String: [BillerForm]] = [:]
        for biller in billers where (biller.status ?? "ACTIVE").uppercased() == "ACTIVE" {
            let category = (biller.category ?? "OTHER").uppercased()
            if grouped[category] == nil { order.append(category) }
            let name = biller.officialName ?? biller.billerId
            grouped[category, default: []].append(BillerForm(
                billerFormId: biller.billerId, name: name, shortName: name,
                logo: biller.brandingRef ?? "", type: category, form: ""))
        }
        return order.map { category in
            let look = appearance(of: category)
            return BillerCategory(id: category, name: look.name, logo: "", icon: look.symbol,
                                  shortName: look.name, billerForms: grouped[category] ?? [])
        }
    }

    /// Libellé et pictogramme d'une catégorie serveur. Explicite : deviner par
    /// sous-chaîne donnait l'éclair à `UTILITY_WATER` (« util »).
    static func appearance(of category: String) -> (name: String, symbol: String) {
        switch category {
        case let c where c.contains("WATER"):
            return (FinanceStrings.billCategoryWater, "drop.fill")
        case let c where c.contains("POWER") || c.contains("ELECTRIC"):
            return (FinanceStrings.billCategoryPower, "bolt.fill")
        case let c where c.contains("MEDIA") || c.contains("TV"):
            return (FinanceStrings.billCategoryMedia, "play.tv.fill")
        case let c where c.contains("TELECOM") || c.contains("INTERNET"):
            return (FinanceStrings.billCategoryTelecom, "antenna.radiowaves.left.and.right")
        // Bloc 10 — les frais scolaires se paient comme une facture (facturier
        // `UNIBUSCHOOLFEES`) : sans cette catégorie, ils tombaient dans « Autres
        // factures ». Même lecture que l'écran historique (`educ` / `school`).
        case let c where c.contains("EDUC") || c.contains("SCHOOL"):
            return (FinanceStrings.billCategoryEducation, "graduationcap.fill")
        default:
            return (FinanceStrings.billCategoryOther, "doc.text.fill")
        }
    }

    func lookup(billerID: String, fields: [String: String]) async -> Result<Bill, FinanceError> {
        let request = BillInquiryRequest(
            billerId: billerID, schemaVersion: await schemas.version(for: billerID),
            fields: fields.filter { !$0.value.isEmpty }, conversationId: nil)
        switch await FinanceCoreError.capture({ try await dataSource.billInquiry(request) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceBill] inquiry failed (billerId=\(billerID)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let inquiry):
            guard let bill = Self.bill(from: inquiry, billerID: billerID) else {
                // Sans montant ni devise, rien de payable n'est promis.
                return .failure(.server(statusCode: nil))
            }
            return .success(bill)
        }
    }

    /// La facture lue, telle que le Biller Hub la rend — masquée.
    ///
    /// `inquiryRef` devient la référence : c'est elle que le prepare nommera.
    /// Le paiement partiel n'est pas annoncé par la réponse : il n'est donc pas
    /// offert — payer moins que le dû sans accord du facturier serait refusé.
    static func bill(from inquiry: BillInquiryDTO, billerID: String,
                     now: Date = Date()) -> Bill? {
        guard let minor = inquiry.dueAmountMinor, let currency = inquiry.currency, !currency.isEmpty
        else { return nil }
        let customer = [inquiry.customerNameMasked, inquiry.accountRefMasked]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        return Bill(
            reference: FinancialReference(type: .bill, id: inquiry.inquiryRef, version: 0,
                                          correlationID: CorrelationId()),
            billerID: inquiry.billerId ?? billerID,
            customerLabel: customer,
            amountDue: FcoCardMapper.amount(minor: minor, currency: currency),
            currency: currency,
            fetchedAt: now,
            allowsPartialPayment: false)
    }

    /// Ce service demande toujours un devis : `/pay-bill/prepare`, puis la
    /// confirmation humaine. Un refus du prepare est **le** résultat, pas une
    /// raison de tenter autre chose.
    var providesQuotes: Bool { true }

    func pay(_ bill: Bill, amount: Decimal?,
             idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
        // Jamais de débit direct : le paiement passe par `quote` puis la
        // confirmation explicite — contrat §5, « Pattern commun ».
        .failure(.capabilityUnavailable)
    }

    /// `POST /pay-bill/prepare`. Le corps n'est pas publié : l'inquiry lue, le
    /// facturier, le montant — et l'appareil et le canal, sur lesquels porte
    /// l'empreinte de confirmation (leur absence faisait refuser l'execute de
    /// Pay Request en `CF_021`).
    func quote(_ bill: Bill, amount: Decimal, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        var body: [String: Any] = [
            "inquiryRef": bill.reference.id,
            "billerId": bill.billerID,
            "amountMinor": LiveSendMoney.minorUnits(amount, currency: bill.currency),
            "currency": bill.currency,
            "deviceId": deviceID(),
            "channel": "MOBILE",
        ]
        if let conversationID { body["conversationId"] = conversationID }
        let result = await quoting.prepare(.payBill, body: body, idempotency: idempotency)
        #if DEBUG
        if case .failure(let error) = result {
            print("[FinanceBill] prepare failed (inquiryRef=\(bill.reference.id)): \(error)")
        }
        #endif
        return result
    }

    // MARK: - Doute

    /// `POST /pay-bill/requery` — relit le débit et la livraison, sans rien
    /// rejouer. Un paiement abouti que le facturier n'a pas pris en compte
    /// reste `.pendingReconciliation` (``FcoCardMapper/overlayStatus``).
    func requery(_ reference: FinancialReference) async -> Result<PaymentStatus, FinanceError> {
        let request = TopUpRefRequest(financialIntentRef: reference.id, conversationId: nil)
        switch await FinanceCoreError.capture({ try await dataSource.billRequery(request) }) {
        case .failure(let error):
            #if DEBUG
            print("[FinanceBill] requery failed (ref=\(reference.id)): \(error)")
            #endif
            return .failure(error.financeError)
        case .success(let overlay):
            #if DEBUG
            print("[FinanceBill] overlay: payment=\(overlay.paymentStatus ?? "nil") "
                  + "fulfillment=\(overlay.fulfillmentStatus ?? "nil") "
                  + "delivery=\(overlay.deliveryStatus ?? "nil")")
            #endif
            return .success(FcoCardMapper.overlayStatus(payment: overlay.paymentStatus,
                                                        fulfillment: overlay.fulfillmentStatus,
                                                        delivery: overlay.deliveryStatus))
        }
    }

    /// Le JSON tel que reçu, indenté, pour le lire dans la console.
    static func describe(_ value: JSONValue) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8) else { return "<unreadable>" }
        return text
    }
}

/// Version de formulaire lue par facturier — l'inquiry la renvoie.
actor BillSchemaMemo {
    private var versions: [String: String] = [:]
    func remember(_ version: String?, for billerID: String) { versions[billerID] = version }
    func version(for billerID: String) -> String? { versions[billerID] }
}

extension LiveBillPaying {
    /// Libellé d'une valeur imposée. Traduit quand on la connaît, épelé sinon
    /// (`MONTH_CURRENT` → « Month current ») — jamais la valeur brute.
    static func optionLabel(_ value: String) -> String {
        switch value.uppercased() {
        case "MONTH_CURRENT":  return FinanceStrings.billPeriodMonthCurrent
        case "MONTH_PREVIOUS": return FinanceStrings.billPeriodMonthPrevious
        case "ARREARS":        return FinanceStrings.billPeriodArrears
        default:
            let spaced = value.replacingOccurrences(of: "_", with: " ")
            return spaced.prefix(1).uppercased() + spaced.dropFirst().lowercased()
        }
    }
}
