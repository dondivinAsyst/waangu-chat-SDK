//
//  FinanceBillCatalogueTests.swift
//  FeatureChatTests
//
//  §5.1 — le catalogue Pay Bill, sur la réponse réelle du backend (22/09).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceBillCatalogueTests: XCTestCase {

    /// Copie exacte de la réponse reçue.
    private static let catalogue = #"""
    [{"billerId":"STUB_REGIE_EAU","officialName":"Régie des Eaux (stub)","category":"UTILITY_WATER","country":"BURUNDI","verified":true,"brandingRef":"stub://stub_regie_eau","status":"ACTIVE"},{"billerId":"STUB_REGIE_ELEC","officialName":"Régie Électricité (stub)","category":"UTILITY_POWER","country":"BURUNDI","verified":true,"brandingRef":"stub://stub_regie_elec","status":"ACTIVE"},{"billerId":"STUB_TV","officialName":"TV / Cable (stub)","category":"MEDIA","country":"BURUNDI","verified":true,"brandingRef":"stub://stub_tv","status":"ACTIVE"}]
    """#

    private func billers(_ json: String = catalogue) throws -> [BillerCatalogueEntryDTO] {
        try JSONDecoder().decode([BillerCatalogueEntryDTO].self, from: Data(json.utf8))
    }

    func test_realCatalogue_becomesOneCategoryPerKind_inServerOrder() throws {
        let categories = LiveBillPaying.categories(from: try billers())

        XCTAssertEqual(categories.map(\.id), ["UTILITY_WATER", "UTILITY_POWER", "MEDIA"])
        XCTAssertEqual(categories.map(\.icon), ["drop.fill", "bolt.fill", "play.tv.fill"],
                       "L'eau n'hérite pas de l'éclair de « util »")
        let water = try XCTUnwrap(categories.first)
        XCTAssertEqual(water.billerForms.map(\.billerFormId), ["STUB_REGIE_EAU"])
        XCTAssertEqual(water.billerForms.first?.name, "Régie des Eaux (stub)")
    }

    func test_inactiveBillers_areNotOffered() throws {
        let json = #"[{"billerId":"A","officialName":"A","category":"MEDIA","status":"SUSPENDED"},{"billerId":"B","officialName":"B","category":"MEDIA","status":"ACTIVE"}]"#
        let categories = LiveBillPaying.categories(from: try billers(json))
        XCTAssertEqual(categories.first?.billerForms.map(\.billerFormId), ["B"])
    }

    // MARK: - Formulaire

    /// Copie exacte du schéma reçu pour `STUB_REGIE_EAU`.
    private static let schema = #"""
    {"billerId":"STUB_REGIE_EAU","schemaVersion":"stub-form-1","fields":[{"name":"accountRef","type":"STRING","required":true,"minLength":4,"maxLength":32,"pattern":null,"pashotId":null},{"name":"customerPhone","type":"STRING","required":false,"minLength":8,"maxLength":15,"pattern":null,"pashotId":null}]}
    """#

    func test_realSchema_becomesTheForm() throws {
        let dto = try JSONDecoder().decode(BillerSchemaDTO.self, from: Data(Self.schema.utf8))
        let form = LiveBillPaying.form(from: dto)

        XCTAssertEqual(form.fieldList.map(\.fieldName), ["accountRef", "customerPhone"])
        let account = try XCTUnwrap(form.fieldList.first)
        XCTAssertTrue(account.isRequired)
        XCTAssertEqual(account.minLength, 4)
        XCTAssertEqual(account.maxLength, 32)
        XCTAssertEqual(account.inputType, "text")
        XCTAssertNotEqual(account.label, "accountRef", "Jamais la clé brute à l'écran")
        let phone = try XCTUnwrap(form.fieldList.last)
        XCTAssertFalse(phone.isRequired)
        XCTAssertEqual(phone.inputType, "phone", "Un téléphone prend le clavier téléphonique")
    }

    /// La raison de la règle partagée devient une phrase qui nomme le champ
    /// et la borne — jamais une clé, jamais une phrase figée d'une autre langue.
    func test_fieldIssue_isWordedWithLabelAndBound() {
        let short = FinanceStrings.billFieldError(.tooShort(min: 4), label: "Compte")
        XCTAssertTrue(short.contains("Compte") && short.contains("4"), short)
        let long = FinanceStrings.billFieldError(.tooLong(max: 15), label: "Téléphone")
        XCTAssertTrue(long.contains("Téléphone") && long.contains("15"), long)
        XCTAssertTrue(FinanceStrings.billFieldError(.required, label: "Compte").contains("Compte"))
        XCTAssertTrue(FinanceStrings.billFieldError(.invalidFormat, label: "Compte").contains("Compte"))
    }

    // MARK: - Inquiry

    /// Copie exacte de la réponse reçue pour `STUB_REGIE_EAU`.
    private static let inquiry = #"""
    {"inquiryRef":"inq_stub_d14cad3c-d183-4068-a603-7ccb51684e78","billerId":"STUB_REGIE_EAU","accountRefMasked":"****8990","dueAmountMinor":12500,"currency":"BIF","customerNameMasked":"J*** D**","snapshotId":null}
    """#

    func test_realInquiry_becomesTheBillToReview() throws {
        let dto = try JSONDecoder().decode(BillInquiryDTO.self, from: Data(Self.inquiry.utf8))
        let bill = try XCTUnwrap(LiveBillPaying.bill(from: dto, billerID: "STUB_REGIE_EAU"))

        XCTAssertEqual(bill.reference.id, "inq_stub_d14cad3c-d183-4068-a603-7ccb51684e78")
        XCTAssertEqual(bill.reference.type, .bill)
        XCTAssertEqual(bill.amountDue, 12500, "BIF n'a pas de décimales")
        XCTAssertEqual(bill.currency, "BIF")
        XCTAssertEqual(bill.customerLabel, "J*** D** · ****8990", "Masqué, tel que rendu")
        XCTAssertFalse(bill.allowsPartialPayment, "Non annoncé ⇒ non offert")
        XCTAssertTrue(bill.accepts(amount: 12500))
    }

    func test_inquiryWithoutAmount_promisesNothing() throws {
        let json = #"{"inquiryRef":"inq_1","currency":"BIF"}"#
        let dto = try JSONDecoder().decode(BillInquiryDTO.self, from: Data(json.utf8))
        XCTAssertNil(LiveBillPaying.bill(from: dto, billerID: "X"))
    }

    // MARK: - Schéma v2 (steps, semanticType, ENUM)

    /// Copie exacte du schéma `stub-form-2` reçu pour `STUB_REGIE_EAU`.
    private static let schemaV2 = #"""
    {"billerId":"STUB_REGIE_EAU","schemaVersion":"stub-form-2","workflowVersion":"stub-wf-2","steps":[{"id":1,"title":"Identification","description":"Référence abonné et contact"},{"id":2,"title":"Compteur","description":"Numéro de compteur et période"},{"id":3,"title":"Facture","description":"Référence de facture si connue"}],"fields":[{"name":"accountRef","type":"STRING","semanticType":"ACCOUNT_REF","required":true,"minLength":6,"maxLength":20,"pattern":"^[A-Za-z0-9]{6,20}$","order":1,"step":1,"visibility":"ALWAYS","allowedValues":null,"pashotId":null},{"name":"customerPhone","type":"STRING","semanticType":"MSISDN","required":false,"minLength":8,"maxLength":15,"pattern":"^[0-9+]{8,15}$","order":2,"step":1,"visibility":"ALWAYS","allowedValues":null,"pashotId":null},{"name":"meterNumber","type":"STRING","semanticType":"METER","required":true,"minLength":6,"maxLength":16,"pattern":"^[A-Za-z0-9]{6,16}$","order":3,"step":2,"visibility":"ALWAYS","allowedValues":null,"pashotId":null},{"name":"period","type":"ENUM","semanticType":"ENUM_CHOICE","required":true,"minLength":0,"maxLength":0,"pattern":null,"order":4,"step":2,"visibility":"ALWAYS","allowedValues":["MONTH_CURRENT","MONTH_PREVIOUS","ARREARS"],"pashotId":null},{"name":"invoiceRef","type":"STRING","semanticType":"INVOICE_REF","required":false,"minLength":6,"maxLength":24,"pattern":"^[A-Za-z0-9\\-]{6,24}$","order":5,"step":3,"visibility":"ALWAYS","allowedValues":null,"pashotId":null}]}
    """#

    private func formV2() throws -> DynamicBiller {
        let dto = try JSONDecoder().decode(BillerSchemaDTO.self, from: Data(Self.schemaV2.utf8))
        return LiveBillPaying.form(from: dto)
    }

    func test_schemaV2_keepsTheBillersOrder_andNamesEveryField() throws {
        let form = try formV2()
        XCTAssertEqual(form.fieldList.map(\.fieldName),
                       ["accountRef", "customerPhone", "meterNumber", "period", "invoiceRef"])
        XCTAssertEqual(form.fieldList.map(\.priority), [1, 2, 3, 4, 5], "L'ordre est celui du facturier")
        for field in form.fieldList {
            XCTAssertNotEqual(field.label, field.fieldName, "Jamais la clé brute : \(field.fieldName)")
        }
    }

    /// Le champ qui disait « nécessite une mise à jour » : une liste imposée.
    func test_enumField_becomesAChoice_withItsValues() throws {
        let period = try XCTUnwrap(try formV2().fieldList.first { $0.fieldName == "period" })
        XCTAssertEqual(period.inputType, "enum")
        XCTAssertEqual(SupportedFieldKind(rawInputType: period.inputType), .choice)
        XCTAssertEqual(period.allowedValues, ["MONTH_CURRENT", "MONTH_PREVIOUS", "ARREARS"])
        XCTAssertTrue(period.isRequired)
        // 0/0 rendu par le backend : ce ne sont pas des bornes de saisie.
        XCTAssertNil(period.minLength)
        XCTAssertNil(period.maxLength)
        XCTAssertEqual(LiveBillPaying.optionLabel("MONTH_CURRENT"), FinanceStrings.billPeriodMonthCurrent)
        XCTAssertEqual(LiveBillPaying.optionLabel("SOMETHING_NEW"), "Something new", "Épelé, jamais brut")
    }

    func test_patternAndLengths_comeFromTheSchema() throws {
        let meter = try XCTUnwrap(try formV2().fieldList.first { $0.fieldName == "meterNumber" })
        XCTAssertEqual(meter.regex, "^[A-Za-z0-9]{6,16}$")
        XCTAssertEqual(meter.minLength, 6)
        XCTAssertEqual(meter.maxLength, 16)
        XCTAssertEqual(meter.label, FinanceStrings.billFieldMeter)
    }

    /// Une visibilité que cette version ne sait pas évaluer masque le champ —
    /// et ne bloque donc pas la recherche.
    func test_conditionalField_isHidden() {
        let always = DynamicBillerField(fieldName: "a", label: "A", dataType: "", inputType: "text",
                                        minLength: nil, maxLength: nil, isRequired: false, regex: "",
                                        value: "", viewDisplay: "ALWAYS", valueRange: "", keyName: "a",
                                        placeholder: "", fieldMapping: "a", parent: "", minBy: "", mask: "",
                                        err: 0, message: "", isMapping: false, valueMask: "", priority: 1)
        let conditional = DynamicBillerField(fieldName: "b", label: "B", dataType: "", inputType: "text",
                                             minLength: nil, maxLength: nil, isRequired: true, regex: "",
                                             value: "", viewDisplay: "WHEN_ARREARS", valueRange: "", keyName: "b",
                                             placeholder: "", fieldMapping: "b", parent: "", minBy: "", mask: "",
                                             err: 0, message: "", isMapping: false, valueMask: "", priority: 2)
        let form = DynamicBiller(id: "x", name: "x", shortName: "x", description: "", logo: "", status: 1,
                                 serviceId: "", biller: "x", fieldList: [always, conditional],
                                 fetchFieldFormRaw: "", fetchFieldForm: nil, paymentDetail: [],
                                 type: "", requireQuery: 1)
        XCTAssertEqual(PayBillView.visibleFields(of: form).map(\.fieldName), ["a"])
    }

    func test_unknownFieldName_isSpelledOut() {
        XCTAssertEqual(LiveBillPaying.label(of: "contractNumber"), "Contract number")
    }

    func test_unknownCategory_fallsIntoOther() {
        XCTAssertEqual(LiveBillPaying.appearance(of: "INSURANCE_PREMIUM").symbol, "doc.text.fill")
    }

    // MARK: - Bloc 10 — frais scolaires

    /// Les frais scolaires se paient comme une facture : leur catégorie a son
    /// propre nom et son pictogramme, au lieu de « Autres factures ».
    func test_schoolCategory_isNamedEducation_notOther() {
        for category in ["EDUCATION", "SCHOOL_FEES", "SCHOOL"] {
            let look = LiveBillPaying.appearance(of: category)
            XCTAssertEqual(look.symbol, "graduationcap.fill", category)
            XCTAssertEqual(look.name, FinanceStrings.billCategoryEducation, category)
        }
    }

    /// Un facturier scolaire actif est proposé, dans sa propre catégorie, dans
    /// l'ordre du serveur — et passe ensuite par le même parcours que toute
    /// facture (inquiry, devis, confirmation : FinanceBillPayTests).
    func test_schoolBiller_isOfferedInItsOwnCategory() throws {
        let json = #"[{"billerId":"STUB_REGIE_EAU","officialName":"Régie des Eaux","category":"UTILITY_WATER","status":"ACTIVE"},{"billerId":"UNIBUSCHOOLFEES","officialName":"Université du Burundi — frais","category":"EDUCATION","status":"ACTIVE"}]"#
        let billers = try JSONDecoder().decode([BillerCatalogueEntryDTO].self, from: Data(json.utf8))

        let categories = LiveBillPaying.categories(from: billers)

        XCTAssertEqual(categories.map(\.id), ["UTILITY_WATER", "EDUCATION"])
        let school = try XCTUnwrap(categories.last)
        XCTAssertEqual(school.icon, "graduationcap.fill")
        XCTAssertEqual(school.billerForms.map(\.billerFormId), ["UNIBUSCHOOLFEES"])
    }
}
