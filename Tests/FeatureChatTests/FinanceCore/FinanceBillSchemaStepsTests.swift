//
//  FinanceBillSchemaStepsTests.swift
//  FeatureChatTests
//
//  §5.1 — schéma facturier découpé en étapes (`steps`).
//

import XCTest
import SwiftUI
import WaanguCoreKit
import WaanguSharedUI
@testable import WaanguFeatureChat

// MARK: - Schéma par étapes (réponse du 24/09)

final class FinanceBillSchemaStepsTests: XCTestCase {

    /// Le schéma `stub-form-2` de `STUB_REGIE_EAU`, tel que le serveur le rend.
    private static let payload = """
    {"billerId":"STUB_REGIE_EAU","schemaVersion":"stub-form-2","workflowVersion":"stub-wf-2",
     "steps":[{"id":1,"title":"Identification","description":"Référence abonné et contact"},
              {"id":2,"title":"Compteur","description":"Numéro de compteur et période"},
              {"id":3,"title":"Facture","description":"Référence de facture si connue"}],
     "fields":[
      {"name":"accountRef","type":"STRING","semanticType":"ACCOUNT_REF","required":true,"minLength":6,"maxLength":20,"pattern":"^[A-Za-z0-9]{6,20}$","order":1,"step":1,"visibility":"ALWAYS","allowedValues":null},
      {"name":"customerPhone","type":"STRING","semanticType":"MSISDN","required":false,"minLength":8,"maxLength":15,"pattern":"^[0-9+]{8,15}$","order":2,"step":1,"visibility":"ALWAYS","allowedValues":null},
      {"name":"meterNumber","type":"STRING","semanticType":"METER","required":true,"minLength":6,"maxLength":16,"pattern":"^[A-Za-z0-9]{6,16}$","order":3,"step":2,"visibility":"ALWAYS","allowedValues":null},
      {"name":"period","type":"ENUM","semanticType":"ENUM_CHOICE","required":true,"minLength":0,"maxLength":0,"pattern":null,"order":4,"step":2,"visibility":"ALWAYS","allowedValues":["MONTH_CURRENT","MONTH_PREVIOUS","ARREARS"]},
      {"name":"invoiceRef","type":"STRING","semanticType":"INVOICE_REF","required":false,"minLength":6,"maxLength":24,"pattern":null,"order":5,"step":3,"visibility":"ALWAYS","allowedValues":null}]}
    """

    private func schema() throws -> BillerSchemaDTO {
        try JSONDecoder().decode(BillerSchemaDTO.self, from: Data(Self.payload.utf8))
    }

    /// Les trois étapes du facturier, avec **ses** mots.
    func test_steps_areRead_withTheServersOwnWords() throws {
        let sections = LiveBillPaying.sections(from: try schema())

        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections.map(\.id), [1, 2, 3])
        XCTAssertEqual(sections.first?.title, "Identification")
        XCTAssertEqual(sections.first?.detail, "Référence abonné et contact")
    }

    /// Chaque champ garde l'étape où le facturier le range.
    func test_eachField_keepsItsStep() throws {
        let form = LiveBillPaying.form(from: try schema())
        let steps = Dictionary(uniqueKeysWithValues: form.fieldList.map { ($0.fieldName, $0.step) })

        XCTAssertEqual(steps["accountRef"], 1)
        XCTAssertEqual(steps["customerPhone"], 1)
        XCTAssertEqual(steps["meterNumber"], 2)
        XCTAssertEqual(steps["period"], 2)
        XCTAssertEqual(steps["invoiceRef"], 3)
    }

    /// Un `ENUM` rend `0/0` : ces bornes ne doivent pas devenir « au plus zéro
    /// caractère », sans quoi toute valeur choisie serait refusée.
    func test_enumField_hasNoLengthBounds() throws {
        let form = LiveBillPaying.form(from: try schema())
        let period = form.fieldList.first { $0.fieldName == "period" }

        XCTAssertNil(period?.minLength)
        XCTAssertNil(period?.maxLength)
        XCTAssertEqual(period?.allowedValues, ["MONTH_CURRENT", "MONTH_PREVIOUS", "ARREARS"])
    }

    /// L'empreinte du cache porte la forme **et** le parcours : redécouper les
    /// étapes sans toucher aux champs doit invalider le schéma gardé.
    func test_cacheVersion_coversFormAndWorkflow() throws {
        XCTAssertEqual(LiveBillPaying.version(of: try schema()), "stub-form-2+stub-wf-2")
    }

    /// Une étape sans titre ne devient pas un intitulé vide — et ses champs ne
    /// disparaissent pas pour autant : ils rejoignent le groupe sans nom.
    func test_untitledStep_isDropped_butItsFieldsAreNot() throws {
        let payload = """
        {"billerId":"B","schemaVersion":"v1","workflowVersion":null,
         "steps":[{"id":1,"title":"   ","description":null}],
         "fields":[{"name":"ref","type":"STRING","required":true,"order":1,"step":1,"visibility":"ALWAYS"}]}
        """
        let schema = try JSONDecoder().decode(BillerSchemaDTO.self, from: Data(payload.utf8))
        let form = LiveBillPaying.form(from: schema)

        XCTAssertTrue(LiveBillPaying.sections(from: schema).isEmpty)
        XCTAssertEqual(form.fieldList.count, 1, "Le champ reste exigé par le facturier")
    }
}

// MARK: - Assistant : saisie et blocage

final class FinanceBillWizardTests: XCTestCase {

    /// La règle injectée par l'app — celle du Wallet, reproduite ici dans ce
    /// qu'elle a d'essentiel. `FeatureChat` ne dépend pas de DomainKit : c'est
    /// bien une **fermeture** que l'écran reçoit, et c'est elle qu'on éprouve.
    private static let rule: BillFieldValidating = { field, values in
        guard field.isRequired else { return nil }
        let value = (values[field.fieldName] ?? "").trimmingCharacters(in: .whitespaces)
        if value.isEmpty { return .required }
        if let min = field.minLength, value.count < min { return .tooShort(min: min) }
        if let max = field.maxLength, value.count > max { return .tooLong(max: max) }
        return nil
    }

    private func field(_ name: String, required: Bool, min: Int? = nil,
                       max: Int? = nil, regex: String = "") -> DynamicBillerField {
        DynamicBillerField(
            fieldName: name, label: name, dataType: "STRING", inputType: "text",
            minLength: min, maxLength: max, isRequired: required, regex: regex, value: "",
            viewDisplay: "ALWAYS", valueRange: "", keyName: name, placeholder: "",
            fieldMapping: name, parent: "", minBy: "", mask: "", err: 0, message: "",
            isMapping: false, valueMask: "", priority: 0)
    }

    /// Un champ requis et vide **bloque** l'étape : `goForward` ne passe que sur
    /// une validation sans refus.
    func test_requiredFieldEmpty_blocksTheStep() {
        let results: [WizardValidationResult] = PayBillView.results(
            of: [field("accountRef", required: true)],
            values: [:],
            validator: Self.rule)

        guard case .invalid(let name, _)? = results.first else {
            return XCTFail("un champ requis vide doit refuser l'étape")
        }
        XCTAssertEqual(name, "accountRef")
    }

    /// Rempli et conforme, l'étape passe.
    func test_filledField_letsTheStepThrough() {
        let results: [WizardValidationResult] = PayBillView.results(
            of: [field("accountRef", required: true, min: 6, max: 20)],
            values: ["accountRef": "ABC123"],
            validator: Self.rule)

        XCTAssertEqual(results, [.valid])
    }

    /// Trop court : refusé aussi, et nommément.
    func test_tooShort_isRefusedByName() {
        let results: [WizardValidationResult] = PayBillView.results(
            of: [field("accountRef", required: true, min: 6, max: 20)],
            values: ["accountRef": "AB"],
            validator: Self.rule)

        guard case .invalid(let name, let message)? = results.first else {
            return XCTFail("une valeur trop courte doit refuser l'étape")
        }
        XCTAssertEqual(name, "accountRef")
        XCTAssertFalse(message.isEmpty, "Le refus se dit, il ne se devine pas")
    }

    /// Un champ optionnel laissé vide n'empêche rien.
    func test_optionalField_neverBlocks() {
        let results: [WizardValidationResult] = PayBillView.results(
            of: [field("invoiceRef", required: false, min: 6)],
            values: [:],
            validator: Self.rule)

        XCTAssertEqual(results, [.valid])
    }

    /// La saisie vit dans l'état de l'assistant — c'est ce qui manquait : elle
    /// partait dans la vue, l'assistant ne la voyait pas, et le champ restait
    /// vide à l'écran.
    func test_typing_landsInTheWizardState() {
        var state: WizardFormState = [:]
        let binding = Binding(get: { state }, set: { state = $0 })
        let target = field("meterNumber", required: true, max: 16)

        PayBillView.binding(in: binding, field: target, kind: .text).wrappedValue = "MTR001"

        XCTAssertEqual(PayBillView.values(of: state)["meterNumber"], "MTR001")
    }

    /// La longueur maximale s'applique **pendant** la frappe, dans l'assistant
    /// comme sur la page simple.
    func test_wizardTyping_respectsMaxLength() {
        var state: WizardFormState = [:]
        let binding = Binding(get: { state }, set: { state = $0 })
        let target = field("meterNumber", required: true, max: 4)

        PayBillView.binding(in: binding, field: target, kind: .text).wrappedValue = "123456789"

        XCTAssertEqual(PayBillView.values(of: state)["meterNumber"], "1234")
    }
}
