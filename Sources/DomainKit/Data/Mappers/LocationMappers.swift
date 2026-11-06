//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/9/26.
//

import Foundation
import WaanguCoreKit

enum LocationMappers {

    // MARK: - FindLocation Request Mapping
    
    static func map(dto: FindLocationRequestDTO) -> FindLocation {
        return FindLocation(
            distance: dto.distance,
            search: dto.search,
            start: dto.start,
            number: dto.number,
            type: dto.type.flatMap { LocationType(rawValue: $0) }
        )
    }

    static func map(entity: FindLocation) -> FindLocationRequestDTO {
        return FindLocationRequestDTO(
            distance: entity.distance,
            search: entity.search,
            start: entity.start,
            number: entity.number,
            type: entity.type?.rawValue
        )
    }

    // MARK: - FindLocation Response Mapping

    static func map(responseDTO: FindLocationResponseDTO) -> LocationResponseData? {

        guard let data = responseDTO.data else { return nil }

        return LocationResponseData(
            err: String(responseDTO.err),
            message: responseDTO.message,
            link: responseDTO.link,
            data: mapList(dtos: data)
        )
    }

    // MARK: - Location Mapping

    static func map(dto: LocationDTO) -> LocationData {

        let openHoursMapped = dto.openHours?.mapOpenHours()

        let locationMapped = dto.location.map {
            Location(
                type: $0.type,
                coordinates: $0.coordinates
            )
        }

        return LocationData(
            id: dto.id,
            type: dto.type.flatMap { LocationType(rawValue: $0.rawValue) },
            name: dto.name,
            phone: dto.phone,
            email: dto.email,
            township: dto.township.map {
                Township(
                    id: $0.id,
                    code: $0.code,
                    name: $0.name
                )
            },
            province: dto.province.map {
                Province(
                    id: $0.id,
                    code: $0.code,
                    name: $0.name
                )
            },
            openHoursType: dto.openHoursType,
            openHours: openHoursMapped,
            images: dto.images,
            address: dto.address,
            status: dto.status,
            location: locationMapped,
            lat: dto.lat,
            long: dto.long
        )
    }

    static func map(entity: LocationData) -> LocationDTO {

        let openHoursMapped = entity.openHours?.map { oh in
            OpenHourDTO(
                day: oh.day,
                status: oh.status,
                openHours: oh.openHours.map {
                    TimeRangeDTO(
                        timeFrom: $0.timeFrom,
                        timeTo: $0.timeTo
                    )
                }
            )
        }

        let locationMapped = entity.location.map {
            GeoLocationDTO(
                type: $0.type,
                coordinates: $0.coordinates
            )
        }

        return LocationDTO(
            id: entity.id,
            type: entity.type.flatMap { LocationTypeDTO(rawValue: $0.rawValue) },
            name: entity.name,
            phone: entity.phone,
            email: entity.email,
            township: entity.township.map {
                TownshipDTO(
                    id: $0.id,
                    code: $0.code,
                    name: $0.name
                )
            },
            province: entity.province.map {
                ProvinceDTO(
                    id: $0.id,
                    code: $0.code,
                    name: $0.name
                )
            },
            openHoursType: entity.openHoursType,
            openHours: openHoursMapped.map(OpenHoursContainer.array),
            images: entity.images,
            address: entity.address,
            status: entity.status,
            location: locationMapped,
            lat: entity.lat,
            long: entity.long
        )
    }

    // MARK: - List Mapping

    static func mapList(dtos: [LocationDTO]) -> [LocationData] {
        return dtos.map { map(dto: $0) }
    }

    static func mapList(entities: [LocationData]) -> [LocationDTO] {
        return entities.map { map(entity: $0) }
    }
}
