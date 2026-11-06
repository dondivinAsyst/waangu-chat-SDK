//
//  File.swift
//  AppModules
//
//  Created by Asyst Resources Ltd. on 4/9/26.
//

import Foundation

public struct FindLocation: Equatable {
    public let distance: Double?
    public let search: String?
    public let start: Int?
    public let number: Int?
    public let type: LocationType?
    
    public init(distance: Double?, search: String?, start: Int?, number: Int?, type: LocationType?) {
        self.distance = distance
        self.search = search
        self.start = start
        self.number = number
        self.type = type
    }
}

public enum LocationType: String, Codable {
    case agent
    case merchant
    case atm
    case branch
}

public struct LocationCardUIState: Identifiable {
    public let id: String
    public let name: String
    public let locationText: String
    public let openHoursText: String
    public let imageURL: URL?
    
    public init(id: String, name: String, locationText: String, openHoursText: String, imageURL: URL?) {
        self.id = id
        self.name = name
        self.locationText = locationText
        self.openHoursText = openHoursText
        self.imageURL = imageURL
    }
}

public struct LocationResponseData: Equatable {
    public let err: String
    public let message: String
    public let link: String?
    public let data: [LocationData]
    
    public init(err: String, message: String, link: String?, data: [LocationData]) {
        self.err = err
        self.message = message
        self.link = link
        self.data = data
    }
}
public struct LocationData: Equatable {
    public let id: String?
    public let type: LocationType?
    public let name: String?
    public let phone: String?
    public let email: String?
    public let township: Township?
    public let province: Province?
    public let openHoursType: String?
    public let openHours: [OpenHour]?
    public let images: [String]?
    public let address: String?
    public let status: String?
    public let location: Location?
    public let lat: Double?
    public let long: Double?
    
    public init(
        id: String?,
        type: LocationType?,
        name: String?,
        phone: String?,
        email: String?,
        township: Township?,
        province: Province?,
        openHoursType: String?,
        openHours: [OpenHour]?,
        images: [String]?,
        address: String?,
        status: String?,
        location: Location?,
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
}

public struct Township: Equatable {
    public let id: String?
    public let code: String?
    public let name: String?
    
    public init(id: String?, code: String?, name: String?) {
        self.id = id
        self.code = code
        self.name = name
    }
}

public struct Province: Equatable {
    public let id: String?
    public let code: String?
    public let name: String?
    
    public init(id: String?, code: String?, name: String?) {
        self.id = id
        self.code = code
        self.name = name
    }
}

public struct OpenHour: Equatable {
    public let day: String?
    public let status: Bool?
    public let openHours: TimeRange?
    
    public init(day: String?, status: Bool?, openHours: TimeRange?) {
        self.day = day
        self.status = status
        self.openHours = openHours
    }
}

public struct TimeRange: Equatable {
    public let timeFrom: String?
    public let timeTo: String?
    
    public init(timeFrom: String?, timeTo: String?) {
        self.timeFrom = timeFrom
        self.timeTo = timeTo
    }
}

public struct Location: Equatable {
    public let type: String?
    public let coordinates: [Double]?
    
    public init(type: String?, coordinates: [Double]?) {
        self.type = type
        self.coordinates = coordinates
    }
}

public struct LocationDisplayData {
    public let id: String?
    public let name: String
    public let location: String
    public let currentDayHours: String
    public let imageURL: URL?
    public let phone: String?
    public let email: String?
    public let address: String?
    
    public init(
        id: String?,
        name: String,
        location: String,
        currentDayHours: String,
        imageURL: URL?,
        phone: String?,
        email: String?,
        address: String?
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.currentDayHours = currentDayHours
        self.imageURL = imageURL
        self.phone = phone
        self.email = email
        self.address = address
    }
}
