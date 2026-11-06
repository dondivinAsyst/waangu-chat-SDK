//
//  DynamicBillerModels.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//


public struct DynamicBillerField: Equatable, Sendable {
    public let fieldName: String
    public let label: String
    public let dataType: String
    public let inputType: String
    public let minLength: Int?
    public let maxLength: Int?
    public let isRequired: Bool
    public let regex: String
    public let value: String
    public let viewDisplay: String
    public let valueRange: String
    public let keyName: String
    public let placeholder: String
    public let fieldMapping: String
    public let parent: String
    public let minBy: String
    public let mask: String
    public let err: Int
    public let message: String
    public let isMapping: Bool
    public let valueMask: String
    public let priority: Int
    /// Champs enfants à réinitialiser quand ce champ change (flux React Native `children`).
    public let children: [String]
    /// Valeurs admises, quand le backend en impose une liste (champ `ENUM`).
    /// Vide ⇒ saisie libre. Le client n'en invente jamais.
    public let allowedValues: [String]

    /// Étape du formulaire où le facturier range ce champ (`step`).
    ///
    /// `nil` : formulaire d'un seul tenant, ou facturier qui ne découpe pas.
    /// Le client ne regroupe jamais de lui-même — c'est le facturier qui sait
    /// ce qui va ensemble.
    public let step: Int?

    public init(
        fieldName: String,
        label: String,
        dataType: String,
        inputType: String,
        minLength: Int?,
        maxLength: Int?,
        isRequired: Bool,
        regex: String,
        value: String,
        viewDisplay: String,
        valueRange: String,
        keyName: String,
        placeholder: String,
        fieldMapping: String,
        parent: String,
        minBy: String,
        mask: String,
        err: Int,
        message: String,
        isMapping: Bool,
        valueMask: String,
        priority: Int,
        children: [String] = [],
        allowedValues: [String] = [],
        step: Int? = nil
    ) {
        self.fieldName = fieldName
        self.label = label
        self.dataType = dataType
        self.inputType = inputType
        self.minLength = minLength
        self.maxLength = maxLength
        self.isRequired = isRequired
        self.regex = regex
        self.value = value
        self.viewDisplay = viewDisplay
        self.valueRange = valueRange
        self.keyName = keyName
        self.placeholder = placeholder
        self.fieldMapping = fieldMapping
        self.parent = parent
        self.minBy = minBy
        self.mask = mask
        self.err = err
        self.message = message
        self.isMapping = isMapping
        self.valueMask = valueMask
        self.priority = priority
        self.children = children
        self.allowedValues = allowedValues
        self.step = step
    }
}

/// Configuration optionnelle pour charger des champs dynamiques (2C2B / fetch) — JSON serveur.
public struct DynamicBillerFetchFieldForm: Equatable, Sendable {
    public let url: String
    public let method: String
    /// Corps de requête : valeurs peuvent être littérales ou références `fieldList_<fieldName>` à remplacer.
    public let data: [String: String]
    public let childs: [String]

    public init(url: String, method: String, data: [String: String], childs: [String]) {
        self.url = url
        self.method = method
        self.data = data
        self.childs = childs
    }
}

public struct DynamicBillerPaymentDetail: Equatable, Sendable {
    public let name: String
    public let value: String
    public let dataType: String
    public let priority: Int
    public let inputType: String
    /// Comportement RN (`chooseVoucher`, etc.) — chaîne vide si absent côté API.
    public let action: String

    public init(
        name: String,
        value: String,
        dataType: String,
        priority: Int,
        inputType: String,
        action: String = ""
    ) {
        self.name = name
        self.value = value
        self.dataType = dataType
        self.priority = priority
        self.inputType = inputType
        self.action = action
    }
}

public struct DynamicBiller: Equatable, Sendable {
    public let id: String
    public let name: String
    public let shortName: String
    public let description: String
    public let logo: String
    public let status: Int
    public let serviceId: String
    public let biller: String
    public let fieldList: [DynamicBillerField]
    /// Chaîne brute JSON si le backend renvoie un objet non mappé.
    public let fetchFieldFormRaw: String
    public let fetchFieldForm: DynamicBillerFetchFieldForm?
    public let paymentDetail: [DynamicBillerPaymentDetail]
    public let type: String
    public let requireQuery: Int

    /// Les étapes déclarées par le facturier (`steps`), dans son ordre.
    ///
    /// Vide ⇒ un seul bloc. Titres et descriptions sont **rédigés par le
    /// serveur** : ce sont des phrases pour l'utilisateur, pas des clés.
    public let sections: [DynamicBillerSection]

    public init(
        id: String,
        name: String,
        shortName: String,
        description: String,
        logo: String,
        status: Int,
        serviceId: String,
        biller: String,
        fieldList: [DynamicBillerField],
        fetchFieldFormRaw: String,
        fetchFieldForm: DynamicBillerFetchFieldForm?,
        paymentDetail: [DynamicBillerPaymentDetail],
        type: String,
        requireQuery: Int,
        sections: [DynamicBillerSection] = []
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.description = description
        self.logo = logo
        self.status = status
        self.serviceId = serviceId
        self.biller = biller
        self.fieldList = fieldList
        self.fetchFieldFormRaw = fetchFieldFormRaw
        self.fetchFieldForm = fetchFieldForm
        self.paymentDetail = paymentDetail
        self.type = type
        self.requireQuery = requireQuery
        self.sections = sections
    }
}

/// Une étape du formulaire facturier — `steps[]` du schéma.
///
/// Le facturier découpe sa saisie et nomme chaque partie : « Identification »,
/// « Compteur », « Facture ». Rendre les cinq champs à la suite perd ce
/// découpage, et avec lui la seule explication que l'utilisateur reçoit sur ce
/// qu'on lui demande et pourquoi.
public struct DynamicBillerSection: Equatable, Sendable, Identifiable {
    public let id: Int
    /// Rédigé par le serveur, affiché tel quel.
    public let title: String
    /// Peut être vide : tous les facturiers n'en donnent pas.
    public let detail: String

    public init(id: Int, title: String, detail: String = "") {
        self.id = id
        self.title = title
        self.detail = detail
    }
}

public struct BillerForm: Equatable, Sendable {
    public let billerFormId: String
    public let name: String
    public let shortName: String
    public let logo: String
    public let type: String
    public let form: String
    
    public init(billerFormId: String, name: String, shortName: String, logo: String, type: String, form: String) {
        self.billerFormId = billerFormId
        self.name = name
        self.shortName = shortName
        self.logo = logo
        self.type = type
        self.form = form
    }
}

public struct BillerCategory: Equatable, Sendable {
    public let id: String
    public let name: String
    public let logo: String
    public let icon: String
    public let shortName: String
    public let billerForms: [BillerForm]
    
    public init(id: String, name: String, logo: String, icon: String, shortName: String, billerForms: [BillerForm]) {
        self.id = id
        self.name = name
        self.logo = logo
        self.icon = icon
        self.shortName = shortName
        self.billerForms = billerForms
    }
}

/// Ce qui ne va pas dans un champ de formulaire facturier — **sans texte**.
///
/// La règle (DomainKit) dit *quoi* ; chaque écran dit *comment*, dans sa
/// langue. Une phrase toute faite, rendue par la règle, n'existait qu'en
/// français et s'affichait telle quelle partout.
public enum BillFieldIssue: Equatable, Sendable {
    case required
    case tooShort(min: Int)
    case tooLong(max: Int)
    case invalidFormat
}
