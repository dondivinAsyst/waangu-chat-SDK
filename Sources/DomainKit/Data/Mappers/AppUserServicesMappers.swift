//
//  WalletServicesMappers.swift
//  AppModules
//
//  Created by Asyst on 3/29/26.
//

import Foundation

import WaanguCoreKit


enum AppUserServicesMappers {
    
    static func map(from serviceType : TypeService) -> AppUserServiceRequestDTO {
        return AppUserServiceRequestDTO(type: serviceType.rawValue)
    }
    
   static func map(from dto: AppUserServiceResponseDTO) -> [AppUserService] {
        
     guard let data = dto.data else { return [] }
        
     return data.map { serviceDTO in
                AppUserService(
                    id: serviceDTO.id,
                    code: serviceDTO.code,
                    name: serviceDTO.name,
                    desc: serviceDTO.desc,
                    channels: serviceDTO.channels.map { Channel(rawValue: $0) ?? .unknown },
                    status: ServiceStatus(rawValue: serviceDTO.status) ?? .unknown,
                    version: serviceDTO.version
                )
            }
    }
}
