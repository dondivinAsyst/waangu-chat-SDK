
import Foundation
import CoreLocation
import MapKit
import Combine
import WaanguCoreKit


enum LocationPlacesActions: String, Identifiable {
    case sendCurrentLocation
    case sendLiveLocation
    
    var id: String { rawValue }

}

struct PlaceAction {
    let name: String
    var location: String
    let icon: String
    let action: LocationPlacesActions
}

enum MapTypeOption: String, CaseIterable, Identifiable {
    case map
    case satellite
    case hybrid
    
    var id: String { rawValue }
    
    var mapKitType: MKMapType {
        switch self {
        case .map: return .standard
        case .satellite: return .satellite
        case .hybrid: return .hybrid
        }
    }
}

enum SearchResult<T> {
    case success(T)
    case failure(Error)
}





//MARK: VIEWMODEL
final class LocationPickerViewModel: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Properties
    private let locationManager = CLLocationManager()
    /// True only between the user asking to share live and the duration being
    /// picked — it gates the dialog that appears once permission is granted.
    /// The share itself is owned by `LiveLocationSessionManager`.
    var isTrackingLiveLocation = false

    @Published var currentLocation: CLLocationCoordinate2D?
    @Published var horizontalAccuracy: CLLocationAccuracy = 0
    @Published var textMessage = ""
    @Published var isMapExpanded = false
    @Published var mapType: MKMapType = .standard
    @Published var initialRegion: EquatableRegion
    @Published var selectedMapType: MapTypeOption = .map
    @Published var showActions: Bool = true
    
    @Published var showLiveLocationDialog: Bool = false
    
    @Published var places: [MKMapItem] = []
    
    var onDismiss: (() -> Void)?
    var onSendLocation: ((ChatLocationItem) -> Void)?
    
    // Actions mini bottom sheet avec précision dynamique
    
   @Published var  actionMiniBottomSheet = PlaceAction(
        name: "Send this location",
        location: "Loading...",
        icon: "mappin.circle.fill",
        action: .sendCurrentLocation
    )
    
    @Published var actionsMiniBottomSheet: [PlaceAction] = [
        PlaceAction(
            name: "Send My Current Location",
            location: "Accurate to -- meters",
            icon: "mappin.circle.fill",
            action: .sendCurrentLocation
        ),
        PlaceAction(
            name: "Share my Live Location",
            location: "Share your live location for a period of time",
            icon: "sensor.tag.radiowaves.forward.fill",
            action: .sendLiveLocation
        )
    ]

    // MARK: - Init
     init(roomId: String) {
        self.initialRegion = EquatableRegion(
            MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            )
        )
        super.init()
        setupLocationManager()
        requestLocationPermissions()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 10
        locationManager.pausesLocationUpdatesAutomatically = false
    }
    
    private func requestLocationPermissions() {
        locationManager.requestWhenInUseAuthorization()
    }

    // MARK: - CLLocationManagerDelegate
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            if isTrackingLiveLocation {
                self.showLiveLocationDialog = true
            }else{
                locationManager.requestLocation()
            }
        case .denied, .restricted:
            isTrackingLiveLocation = false
            debugLog("called_initAndRequestLiveLocationPermissions restricted or denied ")
            debugLog("Location permission denied or restricted")
        case .notDetermined:
            debugLog("called_initAndRequestLiveLocationPermissions notDetermined ")
               isTrackingLiveLocation = false
//               locationManager.requestAlwaysAuthorization()
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        if !isTrackingLiveLocation {
            self.initialRegion = EquatableRegion(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(
                        latitude:location.coordinate.latitude,
                        longitude: location.coordinate.longitude
                    ),
                    span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
                )
            )
            
            self.fetchNearbyPlaces(center:self.initialRegion.center)
        }
        DispatchQueue.main.async {
            self.currentLocation = location.coordinate
            self.horizontalAccuracy = location.horizontalAccuracy
            self.actionsMiniBottomSheet[0].location = "Accurate to \(Int(location.horizontalAccuracy)) meters"
            
        }

    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        debugLog("Location error: \(error.localizedDescription)")
    }

    // MARK: - Actions
    func onTapAction(action: LocationPlacesActions) {
        switch action {
        case .sendCurrentLocation:
            onSendPinedLocation()

        case .sendLiveLocation:
            initAndRequestLiveLocationPermissions()
        }
        
  
    }
    
    func onSendPinedLocation() {
        if let coord = currentLocation {
            let location = ChatLocationItem(
                coords: CoordsLocation(lat: coord.latitude, lng: coord.longitude),
                title: nil,
                address: actionMiniBottomSheet.location,
                duration: nil,
                distance: nil
            )
            onSendLocation?(location)
            onDismiss?()
        }
    }

    func onTapPlaceItem(for item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        let address = item.placemark.title ?? ""
        let title = item.name ?? "Unknown Location"
        
        let location = ChatLocationItem(
            coords: CoordsLocation(lat: coordinate.latitude, lng: coordinate.longitude),
            title: title,
            address: address,
            duration: nil,
            distance: nil
        )
        onSendLocation?(location)
        onDismiss?()
    }

    // MARK: - Live Location Tracking
    
    private func initAndRequestLiveLocationPermissions() {
        guard !isTrackingLiveLocation else { return }
        isTrackingLiveLocation = true

        let status = locationManager.authorizationStatus
        switch status {
        case .authorizedAlways:
            // Already have permission, show duration dialog
            self.showLiveLocationDialog = true
        case .authorizedWhenInUse:
            // Need to upgrade to Always
            locationManager.requestAlwaysAuthorization()
        case .notDetermined:
            // Request initial permission
            locationManager.requestAlwaysAuthorization()
        case .denied, .restricted:
            isTrackingLiveLocation = false
            debugLog("Location permission denied or restricted")
        @unknown default:
            isTrackingLiveLocation = false
        }

        debugLog("called_initAndRequestLiveLocationPermissions permission")
    }

    
    /// Sends the anchor message for a live share, once.
    ///
    /// This used to start its own location updates and emit a whole new chat
    /// message every 10 metres — one bubble, one server write and one push per
    /// movement. The share is now a single message plus GPS ticks on Realtime,
    /// so all this does is describe the share; `LiveLocationSessionManager`
    /// does the publishing, and it outlives this screen.
    func startLiveLocationWithTimer(for seconds: TimeInterval) {
        guard let coord = currentLocation else {
            // Nothing to anchor the share to yet. Better to send nothing than a
            // live bubble sitting at (0, 0) until the first tick corrects it.
            isTrackingLiveLocation = false
            return
        }

        let duration = LiveLocationDuration.nearest(toSeconds: seconds)
        let location = ChatLocationItem(
            coords: CoordsLocation(lat: coord.latitude, lng: coord.longitude),
            title: nil,
            address: actionMiniBottomSheet.location,
            duration: duration.seconds,
            distance: nil,
            isLive: true,
            // The share id is the anchor message's code, which only exists once
            // the message is built — the room fills it in on the way out.
            shareId: nil,
            expiresAt: Date().addingTimeInterval(duration.seconds)
        )

        isTrackingLiveLocation = false
        onSendLocation?(location)
        onDismiss?()
    }


  
//MARK: GEOCODING, PLACES
    func mapKitIconName(for item: MKMapItem) -> String {
           guard let name = item.name?.lowercased() else { return "mappin.and.ellipse" }
           if name.contains("cafe") || name.contains("coffee") { return "cup.and.saucer.fill" }
           if name.contains("restaurant") { return "fork.knife" }
           if name.contains("park") { return "leaf.fill" }
           if name.contains("hotel") { return "bed.double.fill" }
           if name.contains("store") || name.contains("shop") { return "bag.fill" }
           return "mappin.and.ellipse"
    }

    func fetchNearbyPlaces(center: CLLocationCoordinate2D, radius: CLLocationDistance = 1000) {
      
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                debugLog("Erreur MKLocalSearch: \(error)")
        
                return
            }
            self.places = response?.mapItems ?? []
        }
    }
    
    func fetchPlaceDetails(for coordinate: CLLocationCoordinate2D) {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let geocoder = CLGeocoder()
        
        geocoder.reverseGeocodeLocation(location) { placemarks, error in
            guard error == nil else {
                debugLog("Geocoding error: \(error!.localizedDescription)")
                return
            }
            
            if let placemark = placemarks?.first {
                let name = placemark.name ?? ""
                let thoroughfare = placemark.thoroughfare ?? ""
                let subThoroughfare = placemark.subThoroughfare ?? ""
                let locality = placemark.locality ?? ""
                let administrativeArea = placemark.administrativeArea ?? ""
                let postalCode = placemark.postalCode ?? ""
                let country = placemark.country ?? ""
                
                let fullAddress = "\(name) \(subThoroughfare) \(thoroughfare), \(locality), \(administrativeArea) \(postalCode), \(country)"
                
                debugLog("Geocoding error: \(fullAddress)")
                self.actionMiniBottomSheet.location = fullAddress

            } else {
                debugLog("Geocoding error: ")
            }
        }
    }

}



class SearchPlacesViewModel: ObservableObject {
    @Published var query: String = ""
    @Published var places: [MKMapItem] = []
    @Published var errorMessage: String?
    @Published var isLoading: Bool = true

    private var cancellables = Set<AnyCancellable>()
    public var currentLocation: CLLocationCoordinate2D? = nil

    init() {
           $query
               .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
               .removeDuplicates()
               .sink { [weak self] newText in
                   guard let self = self else { return }
                   if newText.isEmpty {
                       self.places = []
                       self.errorMessage = nil
                   } else {
                       if newText.count >= 3 {
                           self.isLoading = true
                           self.search(newText)
                       }
                     
                   }
               }
               .store(in: &cancellables)
       }
    
    
    
     private func search(_ text: String) {
         
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text

      
        if let current = currentLocation {
            print ("currentLoc", current.latitude)
            request.region = MKCoordinateRegion(
                center: current,
                span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
            )
        }

        let search = MKLocalSearch(request: request)
        search.start { [weak self] response, error in
            guard let self = self else { return }
            
            self.isLoading = false
            
            DispatchQueue.main.async {
               
                if let error = error {
                    self.errorMessage = "Erreur: \(error.localizedDescription)"
                    self.places = []
                } else {
                    self.places = response?.mapItems ?? []
                    self.errorMessage = nil
                }
            }
        }
    }
}
