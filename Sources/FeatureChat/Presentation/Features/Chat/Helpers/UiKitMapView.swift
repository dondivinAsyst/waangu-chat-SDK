//
//  UiKitMapView.swift
//  chatpreview
//
//  Created by Asyst on 7/1/25.
//

import SwiftUI
import MapKit

struct EquatableRegion: Equatable {
    var center: CLLocationCoordinate2D
    var span: MKCoordinateSpan

    init(_ region: MKCoordinateRegion) {
        self.center = region.center
        self.span = region.span
    }

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center, span: span)
    }

    static func == (lhs: EquatableRegion, rhs: EquatableRegion) -> Bool {
        lhs.center.latitude == rhs.center.latitude &&
        lhs.center.longitude == rhs.center.longitude &&
        lhs.span.latitudeDelta == rhs.span.latitudeDelta &&
        lhs.span.longitudeDelta == rhs.span.longitudeDelta
    }
}

struct UIKitMapView: UIViewRepresentable {
    var initialRegion: EquatableRegion
    var defaultZoomLevel: Double = 0.03
    var mapType: MKMapType = .standard
//    @Binding var scrollOffset: CGFloat
    var onRegionChange: ((EquatableRegion) -> Void)?
    
    
    
    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        
        // Configuration initiale
        let initial = MKCoordinateRegion(
            center: initialRegion.region.center,
            span: MKCoordinateSpan(
                latitudeDelta: defaultZoomLevel,
                longitudeDelta: defaultZoomLevel
            )
        )
        
        mapView.setRegion(initial, animated: false)
        mapView.mapType = mapType
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        return mapView
    }
    
    func updateUIView(_ uiView: MKMapView, context: Context) {
        
        uiView.mapType = mapType
        
//        uiView.transform = CGAffineTransform(translationX: 0, y: -scrollOffset * 0.5)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: UIKitMapView
        
        init(_ parent: UIKitMapView) {
            self.parent = parent
        }
        
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            // callback uniquement quand l’utilisateur bouge la map
            let newRegion = EquatableRegion(mapView.region)
            parent.onRegionChange?(newRegion)
        }
    }
}



//MARK: GOOGLE PLACES

//struct GooglePlace: Codable {
//    let name: String
//    let geometry: Geometry
//    let vicinity: String?
//    let types: [String]?
//    let place_id: String?
//    
//    struct Geometry: Codable {
//        let location: Location
//    }
//    
//    struct Location: Codable {
//        let lat: Double
//        let lng: Double
//    }
//    
//    var coordinate: CLLocationCoordinate2D {
//        return CLLocationCoordinate2D(latitude: geometry.location.lat, longitude: geometry.location.lng)
//    }
//}
//
//struct GooglePlacesResponse: Codable {
//    let results: [GooglePlace]
//    let status: String
//}
//
//class GooglePlacesService {
//    private let apiKey = <retirée : clé divulguée, à révoquer côté Google Cloud — jamais en clair dans le code>
//    private let baseURL = "https://maps.googleapis.com/maps/api/place/nearbysearch/json"
//    
//    func fetchNearbyPlaces(center: CLLocationCoordinate2D,
//                         radius: CLLocationDistance = 500,
//                         completion: @escaping (Result<[GooglePlace], Error>) -> Void) {
//        
//       
//        let radiusInMeters = Int(radius)
//        
//        // Create query parameters
//        var components = URLComponents(string: baseURL)!
////        components.queryItems = [
////            URLQueryItem(name: "location", value: "\(center.latitude),\(center.longitude)"),
////            URLQueryItem(name: "radius", value: "\(radiusInMeters)"),
////            URLQueryItem(name: "key", value: apiKey),
//////            URLQueryItem(name: "type", value: "establishment")
////        ]
//        
//        components.queryItems = [
//            URLQueryItem(name: "location", value: "\(center.latitude),\(center.longitude)"),
//            URLQueryItem(name: "rankby", value: "distance"),
//            URLQueryItem(name: "key", value: apiKey),
////            URLQueryItem(name: "type", value: "establishment")
//        ]
//
//        
//        guard let url = components.url else {
//            completion(.failure(NSError(domain: "Invalid URL", code: 0, userInfo: nil)))
//            return
//        }
//        
//        var request = URLRequest(url: url)
//        request.httpMethod = "GET"
//        request.setValue("application/json", forHTTPHeaderField: "Accept")
//        
//        let task = URLSession.shared.dataTask(with: request) { data, response, error in
//            if let error = error {
//                completion(.failure(error))
//                return
//            }
//            
//            guard let data = data else {
//                completion(.failure(NSError(domain: "No data received", code: 0, userInfo: nil)))
//                return
//            }
//            
//            do {
//                let decoder = JSONDecoder()
//                let placesResponse = try decoder.decode(GooglePlacesResponse.self, from: data)
//                
//                if placesResponse.status == "OK" {
//                    completion(.success(placesResponse.results))
//                } else {
//                    let error = NSError(domain: "Google Places API", code: 0,
//                                      userInfo: [NSLocalizedDescriptionKey: "API Error: \(placesResponse.status)"])
//                    completion(.failure(error))
//                }
//            } catch {
//                completion(.failure(error))
//            }
//        }
//        
//        task.resume()
//    }
//    
//    // Convert GooglePlace to MKMapItem if needed
//    func convertToMKMapItems(googlePlaces: [GooglePlace]) -> [MKMapItem] {
//        return googlePlaces.map { place in
//            let placemark = MKPlacemark(coordinate: place.coordinate)
//            let mapItem = MKMapItem(placemark: placemark)
//            mapItem.name = place.name
//            return mapItem
//        }
//    }
//}

//
//func fetchNearbyPlacesGoogle(
//    center: CLLocationCoordinate2D,
//    radius: CLLocationDistance = 300,
//    completion: @escaping ([MKMapItem]
//    ) -> Void) {
//    
//    let placesService = GooglePlacesService()
//    
//    placesService.fetchNearbyPlaces(center: center, radius: radius) { result in
//        switch result {
//        case .success(let googlePlaces):
//            let mapItems = placesService.convertToMKMapItems(googlePlaces: googlePlaces)
//            completion(mapItems)
//        case .failure(let error):
//            print("Google Places API Error: \(error.localizedDescription)")
//            completion([])
//        }
//    }
//}

//



