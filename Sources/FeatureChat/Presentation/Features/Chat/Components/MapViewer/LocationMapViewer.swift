//
//  LocationMapViewer.swift
//  FeatureChat
//
//  Created by Kiro on 2/12/26.
//

import SwiftUI
import MapKit
import WaanguCoreKit

/// WhatsApp-style internal map viewer for location messages
struct LocationMapViewer: View {
    let location: ChatLocationItem
    let senderName: String
    /// The sharer's current profile picture, for the live marker.
    let senderAvatarURL: String?
    let translationService: (any TranslationServiceProtocol)?
    @Environment(\.dismiss) private var dismiss

    @State private var region: MKCoordinateRegion
    @State private var showDirections = false

    /// Follows the share this location anchors, when it is a live one.
    @StateObject private var liveTracker: LiveLocationTracker

    init(
        location: ChatLocationItem,
        senderName: String,
        messageCode: String,
        senderAvatarURL: String? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.location = location
        self.senderName = senderName
        self.senderAvatarURL = senderAvatarURL
        self.translationService = translationService
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: location.coords.lat,
                longitude: location.coords.lng
            ),
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        ))
        _liveTracker = StateObject(wrappedValue: LiveLocationTracker(
            shareId: location.shareId ?? messageCode,
            expiresAt: location.expiresAt,
            declaredLive: location.isLive == true
        ))
    }

    /// True when this message anchors a live share, running or ended.
    private var isLiveShare: Bool {
        location.isLive == true
    }

    /// Still publishing — a stop that arrived over the wire and a deadline that
    /// has passed both end it, and only the message knows about the second.
    private var isShareRunning: Bool {
        guard location.isLiveActive() else { return false }
        return liveTracker.isLive
    }

    /// The last tick's position while one exists, the anchor's own otherwise.
    private var currentCoordinate: CLLocationCoordinate2D {
        guard let tick = liveTracker.tick else {
            return CLLocationCoordinate2D(
                latitude: location.coords.lat,
                longitude: location.coords.lng
            )
        }
        return CLLocationCoordinate2D(latitude: tick.latitude, longitude: tick.longitude)
    }

    var body: some View {
        ZStack {
            // Map View
            Map(coordinateRegion: $region,
                interactionModes: .all,
                showsUserLocation: true,
                annotationItems: [location]) { _ in
                // Drawn at the live position rather than the anchor's, so the
                // pin is where the sender is now, not where they started.
                MapAnnotation(coordinate: currentCoordinate) {
                    if isLiveShare {
                        // Same marker the bubble draws, so a share opened from
                        // one looks like the thing that was tapped.
                        LiveLocationMarkerView(
                            avatarURL: senderAvatarURL,
                            fallbackName: senderName,
                            isLive: isShareRunning,
                            diameter: 46
                        )
                    } else {
                        VStack(spacing: 0) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 40))
                                .foregroundColor(.red)
                                .shadow(radius: 3)

                            Image(systemName: "arrowtriangle.down.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.red)
                                .offset(y: -5)
                        }
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear {
                guard isLiveShare else { return }
                liveTracker.start()
            }
            .onDisappear { liveTracker.stop() }
            .onReceive(liveTracker.$tick.compactMap { $0 }) { tick in
                // Follow the sender, keeping whatever zoom the viewer chose.
                withAnimation(.easeInOut(duration: 0.4)) {
                    region.center = CLLocationCoordinate2D(
                        latitude: tick.latitude,
                        longitude: tick.longitude
                    )
                }
            }
            
            // Top Bar
            VStack {
                topBar
                Spacer()
                bottomCard
            }
        }
        .chatAppearanceSheet(isPresented: $showDirections) {
            directionsSheet
        }
    }
    
    // MARK: - Top Bar
    
    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            Spacer()
            
            Button {
                shareLocation()
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding()
        .padding(.top, 40)
    }
    
    // MARK: - Live status

    /// A red dot and the time left while the share runs; a plain ended label
    /// once it is over. Ticks stop arriving either way, so without this the
    /// viewer would give no way to tell a finished share from a stalled one.
    private var liveStatusRow: some View {
        HStack(spacing: 6) {
            if isShareRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)

                Text(t(ChatTranslationKeys.LOCATION_LIVE_BADGE))
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.red)

                if let remaining = liveTracker.remaining {
                    Text(LiveLocationTracker.countdown(remaining))
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            } else {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Text(t(ChatTranslationKeys.LOCATION_LIVE_ENDED))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Bottom Card

    private var bottomCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Sender info
            HStack {
                Image(systemName: "person.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
                
                Text(senderName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            if isLiveShare {
                liveStatusRow
            }

            // Location title
            if let title = location.title, !title.isEmpty {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            // Address
            if let address = location.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            // Coordinates — the live ones while a share is running.
            Text("\(currentCoordinate.latitude), \(currentCoordinate.longitude)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospaced()
            
            // Action Buttons
            HStack(spacing: 12) {
                Button {
                    showDirections = true
                } label: {
                    HStack {
                        Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                        Text(t(ChatTranslationKeys.LOCATION_DIRECTIONS))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue)
                    .cornerRadius(10)
                }
                
                Button {
                    openInMaps()
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                        Text(t(ChatTranslationKeys.LOCATION_OPEN_IN_MAPS))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(UIColor.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
        )
        .padding()
    }
    
    // MARK: - Directions Sheet
    
    private var directionsSheet: some View {
        NavigationView {
            VStack(spacing: 20) {
                Button {
                    openInAppleMaps()
                    showDirections = false
                } label: {
                    HStack {
                        Image(systemName: "map.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text(t(ChatTranslationKeys.LOCATION_APPLE_MAPS))
                                .font(.headline)
                            Text(t(ChatTranslationKeys.LOCATION_GET_DIRECTIONS))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Button {
                    openInGoogleMaps()
                    showDirections = false
                } label: {
                    HStack {
                        Image(systemName: "map.circle.fill")
                            .font(.title2)
                            .foregroundColor(.green)
                            .frame(width: 50)
                        
                        VStack(alignment: .leading) {
                            Text(t(ChatTranslationKeys.LOCATION_GOOGLE_MAPS))
                                .font(.headline)
                            Text(t(ChatTranslationKeys.LOCATION_GET_DIRECTIONS))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle(t(ChatTranslationKeys.LOCATION_GET_DIRECTIONS))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(common("cancel")) {
                        showDirections = false
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    private func openInMaps() {
        let coordinate = CLLocationCoordinate2D(
            latitude: location.coords.lat,
            longitude: location.coords.lng
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.title ?? t(ChatTranslationKeys.LOCATION_SCREEN_TITLE)
        mapItem.openInMaps(launchOptions: nil)
    }
    
    private func openInAppleMaps() {
        let coordinate = CLLocationCoordinate2D(
            latitude: location.coords.lat,
            longitude: location.coords.lng
        )
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = location.title ?? t(ChatTranslationKeys.LOCATION_SCREEN_TITLE)
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
    
    private func openInGoogleMaps() {
        let urlString = "comgooglemaps://?daddr=\(location.coords.lat),\(location.coords.lng)&directionsmode=driving"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to web version
            let webUrlString = "https://www.google.com/maps/dir/?api=1&destination=\(location.coords.lat),\(location.coords.lng)"
            if let webUrl = URL(string: webUrlString) {
                UIApplication.shared.open(webUrl)
            }
        }
    }
    
    private func shareLocation() {
        let coordinate = location.coords
        let text = """
        \(location.title ?? "Location")
        \(location.address ?? "")
        https://maps.apple.com/?ll=\(coordinate.lat),\(coordinate.lng)
        """
        
        let activityVC = UIActivityViewController(
            activityItems: [text],
            applicationActivities: nil
        )
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }
}

// MARK: - ChatLocationItem Identifiable Extension

extension ChatLocationItem: Identifiable {
    public var id: String {
        "\(coords.lat),\(coords.lng)"
    }
}
