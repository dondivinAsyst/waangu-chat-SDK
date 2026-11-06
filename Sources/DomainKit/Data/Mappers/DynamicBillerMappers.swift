//
//  DynamicBillerMappers.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation
import WaanguCoreKit

enum DynamicBillerMappers {
    static func toDomain(_ dto: DynamicBillerDTO) -> DynamicBiller {
        DynamicBiller(
            id: dto.id,
            name: dto.name,
            shortName: dto.shortName,
            description: dto.description,
            logo: dto.logo,
            status: dto.status,
            serviceId: dto.serviceId,
            biller: dto.biller,
            fieldList: dto.fieldList.map { toDomain($0) },
            fetchFieldFormRaw: dto.fetchFieldFormRaw,
            fetchFieldForm: parseFetchFieldForm(dto.fetchFieldFormRaw),
            paymentDetail: dto.paymentDetail.map { toDomain($0) },
            type: dto.type,
            requireQuery: dto.requireQuery
        )
    }

    private static func parseFetchFieldForm(_ raw: String) -> DynamicBillerFetchFieldForm? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return nil }
        guard let obj = try? JSONDecoder().decode(FetchFieldFormJSON.self, from: data) else { return nil }
        return DynamicBillerFetchFieldForm(
            url: obj.url,
            method: obj.method,
            data: obj.data ?? [:],
            childs: obj.childs ?? []
        )
    }

    private struct FetchFieldFormJSON: Decodable {
        let url: String
        let method: String
        let data: [String: String]?
        let childs: [String]?
    }
    
    static func toDomain(_ dto: BillerCategoryDTO) -> BillerCategory {
        BillerCategory(
            id: dto.id,
            name: dto.name,
            logo: dto.logo,
            icon: dto.icon,
            shortName: dto.shortName,
            billerForms: dto.billerForms.map { toDomain($0) }
        )
    }
    
    private static func toDomain(_ dto: DynamicBillerFieldDTO) -> DynamicBillerField {
        DynamicBillerField(
            fieldName: dto.fieldName,
            label: dto.label,
            dataType: dto.dataType,
            inputType: dto.inputType,
            minLength: dto.minLength,
            maxLength: dto.maxLength,
            isRequired: dto.isRequired,
            regex: dto.regex,
            value: dto.value,
            viewDisplay: dto.viewDisplay,
            valueRange: dto.valueRange,
            keyName: dto.keyName,
            placeholder: dto.placeholder,
            fieldMapping: dto.fieldMapping,
            parent: dto.parent,
            minBy: dto.minBy,
            mask: dto.mask,
            err: dto.err,
            message: dto.message,
            isMapping: dto.isMapping,
            valueMask: dto.valueMask,
            priority: dto.priority,
            children: dto.children ?? []
        )
    }
    
    private static func toDomain(_ dto: DynamicBillerPaymentDetailDTO) -> DynamicBillerPaymentDetail {
        DynamicBillerPaymentDetail(
            name: dto.name,
            value: dto.value,
            dataType: dto.dataType,
            priority: dto.priority,
            inputType: dto.inputType,
            action: dto.action
        )
    }
    
    private static func toDomain(_ dto: BillerFormDTO) -> BillerForm {
        BillerForm(
            billerFormId: dto.billerFormId,
            name: dto.name,
            shortName: dto.shortName,
            logo: dto.logo,
            type: dto.type,
            form: dto.form
        )
    }
}
