//
//  AppUserServicesResponseDTO.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//
import WaanguNetworkKit

typealias AppUserServiceResponseDTO = APIResponseDTO<[AppUserServiceDTO]>

struct AppUserServiceDTO: Codable {
    let id: String
    let code: String
    let name: String
    let desc: String
    let channels: [String]
    let status: Int
    let version: Int?
}
