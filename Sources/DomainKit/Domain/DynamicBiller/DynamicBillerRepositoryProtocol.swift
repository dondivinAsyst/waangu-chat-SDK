//
//  DynamicBillerRepositoryProtocol.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import Foundation
import WaanguCoreKit

protocol DynamicBillerRepositoryProtocol {
    func getBillerFormParams(billerFormId: String) async -> Result<DynamicBiller, AppError>
    func getBillerCategories() async -> Result<[BillerCategory], AppError>
    func fetchFieldForm(url: String, method: String, body: [String: String]) async -> Result<[String: String], AppError>
}
