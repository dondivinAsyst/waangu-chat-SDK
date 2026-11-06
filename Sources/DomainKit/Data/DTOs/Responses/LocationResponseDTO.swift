//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/9/26.
//

import Foundation
import WaanguCoreKit

public struct FindLocationResponseDTO: Codable {
    
    public let err: Int
    public let message: String
    public let link: String?
    public let data: [LocationDTO]?
    
    public init(
        err: Int,
        message: String,
        link: String?,
        data: [LocationDTO]?
    ) {
        self.err = err
        self.message = message
        self.link = link
        self.data = data
    }
}

public struct LocationDTO: Codable {
    
    public let id: String?
    public let type: LocationTypeDTO?
    public let name: String?
    public let phone: String?
    public let email: String?
    public let township: TownshipDTO?
    public let province: ProvinceDTO?
    public let openHoursType: String?
    public let openHours: OpenHoursContainer?
    public let images: [String]?
    public let address: String?
    public let status: String?
    public let location: GeoLocationDTO?
    public let lat: Double?
    public let long: Double?
    
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case type
        case name
        case phone
        case email
        case township
        case province
        case openHoursType
        case openHours
        case images
        case address
        case status
        case location
        case lat
        case long
    }
    
    public init(
        id: String?,
        type: LocationTypeDTO?,
        name: String?,
        phone: String?,
        email: String?,
        township: TownshipDTO?,
        province: ProvinceDTO?,
        openHoursType: String?,
        openHours: OpenHoursContainer?,
        images: [String]?,
        address: String?,
        status: String?,
        location: GeoLocationDTO?,
        lat: Double?,
        long: Double?
    ) {
        self.id = id
        self.type = type
        self.name = name
        self.phone = phone
        self.email = email
        self.township = township
        self.province = province
        self.openHoursType = openHoursType
        self.openHours = openHours
        self.images = images
        self.address = address
        self.status = status
        self.location = location
        self.lat = lat
        self.long = long
    }
}

public struct TownshipDTO: Codable {
    
    public let id: String?
    public let code: String?
    public let name: String?
    
    public init(id: String?, code: String?, name: String?) {
        self.id = id
        self.code = code
        self.name = name
    }
}

public struct ProvinceDTO: Codable {
    
    public let id: String?
    public let code: String?
    public let name: String?
    
    public init(id: String?, code: String?, name: String?) {
        self.id = id
        self.code = code
        self.name = name
    }
}

public struct OpenHourDTO: Codable {
    
    public let day: String?
    public let status: Bool?
    public let openHours: TimeRangeDTO?
    
    public init(day: String?, status: Bool?, openHours: TimeRangeDTO?) {
        self.day = day
        self.status = status
        self.openHours = openHours
    }
}

public struct TimeRangeDTO: Codable {
    
    public let timeFrom: String?
    public let timeTo: String?
    
    public init(timeFrom: String?, timeTo: String?) {
        self.timeFrom = timeFrom
        self.timeTo = timeTo
    }
}

public struct GeoLocationDTO: Codable {
    
    public let type: String?
    public let coordinates: [Double]?
    
    public init(type: String?, coordinates: [Double]?) {
        self.type = type
        self.coordinates = coordinates
    }
}

// MARK: - OpenHours Container
public enum OpenHoursContainer: Codable {
    case array([OpenHourDTO])
    case string(String)
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let arrayValue = try? container.decode([OpenHourDTO].self) {
            self = .array(arrayValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(
                OpenHoursContainer.self,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Expected OpenHoursContainer to be either array or string"
                )
            )
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .array(let array):
            try container.encode(array)
        case .string(let string):
            try container.encode(string)
        }
    }
}

// MARK: - OpenHoursContainer Extension
extension OpenHoursContainer {
    func mapOpenHours() -> [OpenHour]? {
        switch self {
        case .array(let openHourDTOs):
            return openHourDTOs.map { oh in
                OpenHour(
                    day: oh.day,
                    status: oh.status,
                    openHours: oh.openHours.map {
                        TimeRange(
                            timeFrom: $0.timeFrom,
                            timeTo: $0.timeTo
                        )
                    }
                )
            }
        case .string(let openHoursString):
            // Handle string format - could be JSON string or simple text
            // For now, return nil for string format, but you could parse it if needed
            debugLog("OpenHours received as string: \(openHoursString)")
            return nil
        }
    }
}

public enum LocationTypeDTO: String, Codable {
    case agent = "agent"
    case merchant = "merchant"
    case atm = "atm"
    case branch = "branch"
}
