//
//  BubbleLocationView.swift
//  chatpreview
//
//  Created by Asyst on 7/1/25.
//

import SwiftUI
import MapKit
import WaanguCoreKit


struct BubbleLocationView: View {
    let message: MessageDataItem
    let isSelectionMode: Bool
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    @State private var showMapOptions = false
    @State private var showMapViewer = false
    @Environment(\.colorScheme) private var colorScheme

    /// Follows the share this bubble anchors, when it is a live one. Created
    /// even for an ordinary pinned location — it costs nothing until `start()`,
    /// which only a live bubble calls.
    @StateObject private var liveTracker: LiveLocationTracker

    init(message: MessageDataItem, isSelectionMode: Bool, chatVM: ChatRoomViewModel) {
        self.message = message
        self.isSelectionMode = isSelectionMode
        self.chatVM = chatVM
        let location = message.message.location
        _liveTracker = StateObject(wrappedValue: LiveLocationTracker(
            // The sender names a share id only when it differs from the anchor
            // message's own code, which is what the contract recommends using.
            shareId: location?.shareId ?? message.codeMessage,
            expiresAt: location?.expiresAt,
            declaredLive: location?.isLive == true
        ))
    }

    /// True when this message anchors a live share, whether or not it is still
    /// running — an ended share still says so in the bubble.
    private var isLiveShare: Bool {
        message.message.location?.isLive == true
    }

    /// Still publishing. Both halves matter: the tracker knows about a stop
    /// that arrived over the wire, and the message knows about a deadline that
    /// has passed — including one moved to now when this device ended its own
    /// share, which is the only record of that surviving a relaunch.
    private var isShareRunning: Bool {
        guard message.message.location?.isLiveActive() == true else { return false }
        return liveTracker.isLive
    }

    /// The last tick's position while the share is running, the anchor
    /// message's own otherwise. A share that has ended keeps its final tick.
    var latitude: Double {
        liveTracker.tick?.latitude ?? message.message.location?.coords.lat ?? 0
    }

    var longitude: Double {
        liveTracker.tick?.longitude ?? message.message.location?.coords.lng ?? 0
    }

    var duration: Double {
        message.message.location?.duration ?? 0
    }


    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    private var region: EquatableRegion {
         EquatableRegion(
             MKCoordinateRegion(
                 center: coordinate,
                 span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
             )
         )
     }

    private var hasLocationTitle: Bool {
        guard let title = message.message.location?.title, !title.isEmpty else { return false }
        return true
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack{
                if message.direction == .sent {
                    VStack(spacing: 8) {
                        shareButton()
                    }
                }
                
                messageView()
                    .onTapGesture {
                        // Disable tap when in selection mode
                        guard !isSelectionMode else { return }
                        showMapViewer = true
                    }
                    .allowsHitTesting(!isSelectionMode)
                
                if message.direction == .received {
                    VStack(spacing: 8) {
                        shareButton()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .padding(.leading, message.direction == .received ? 5 : 55)
        .padding(.trailing, message.direction == .received ? 55 : 5)
        .confirmationDialog(t(ChatTranslationKeys.LOCATION_OPEN_TITLE), isPresented: $showMapOptions, titleVisibility: .visible) {
            Button(t(ChatTranslationKeys.LOCATION_OPEN_APPLE_MAPS)) {
                openInAppleMaps()
            }
            Button(t(ChatTranslationKeys.LOCATION_OPEN_GOOGLE_MAPS)) {
                openInGoogleMaps()
            }
            Button(common("cancel"), role: .cancel) {}
        }
        .id(message.id)
        .onAppear {
            // Only a live share has ticks to follow; an ordinary pin never
            // subscribes, so the timeline pays nothing for this.
            guard isLiveShare else { return }
            liveTracker.start()
        }
        .onDisappear { liveTracker.stop() }
        .chatAppearanceFullScreenCover(isPresented: $showMapViewer) {
            if let location = message.message.location {
                LocationMapViewer(
                    location: location,
                    senderName: message.senderName,
                    messageCode: message.codeMessage,
                    senderAvatarURL: chatVM.senderAvatarURLForMarker(message),
                    translationService: chatVM.translationService
                )
            }
        }
    }
    
    private func messageView() -> some View {
        VStack(spacing: 4) {
            // Forwarded indicator inside the bubble
            forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")

            ZStack {
                UIKitMapViewBubble(initialRegion: region, defaultZoomLevel: 0.005)
                .allowsHitTesting(false)

                if isLiveShare {
                    // A face, not a pin: the share is about who is moving, and
                    // the halo says whether they still are.
                    LiveLocationMarkerView(
                        avatarURL: chatVM.senderAvatarURLForMarker(message),
                        fallbackName: message.senderName,
                        isLive: isShareRunning,
                        diameter: 34
                    )
                } else {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Color(.systemBlue))
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: 150,
                maxHeight: UIScreen.main.bounds.height * 0.2
            )
            .overlay(alignment: .topLeading) {
                if isLiveShare {
                    liveBadge()
                        .padding(8)
                }
            }
            .clipShape(
                   RoundedRectangle(cornerRadius: 10, style: .continuous)
               )

            
            if showsStopControl {
                stopSharingButton()
            }

            if hasLocationTitle, let title = message.message.location?.title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                    Text(message.message.location?.address ?? "")
                        .foregroundColor(Color(.systemBlue))
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 5)
                .padding(.trailing, 72)
                .padding(.bottom, 2)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if hasLocationTitle {
                BubbleMetaOverlay(message: message, style: .bubble(colorScheme: colorScheme), translationService: chatVM.translationService)
                    .padding(8)
            } else {
                BubbleMetaOverlay(message: message, style: .media, translationService: chatVM.translationService)
            }
        }
        .padding(5)
        .background(message.backgroundColor)
        .clipShape(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .applyTailView(message.direction)
        .applyStrokeOnBubbleView()
        .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
    }

    /// "● Live · 14:32" while the share runs, and a plain ended label after.
    ///
    /// The countdown is the honest signal here: a share whose sender went
    /// offline stops moving but says nothing, and the time left is the only
    /// thing on screen that keeps telling the truth.
    @ViewBuilder
    private func liveBadge() -> some View {
        HStack(spacing: 4) {
            if isShareRunning {
                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)

                Text(t(ChatTranslationKeys.LOCATION_LIVE_BADGE))
                    .font(.caption2.weight(.semibold))

                if let remaining = liveTracker.remaining {
                    Text(LiveLocationTracker.countdown(remaining))
                        .font(.caption2.monospacedDigit())
                }
            } else {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 8))

                Text(t(ChatTranslationKeys.LOCATION_LIVE_ENDED))
                    .font(.caption2.weight(.semibold))
            }
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.55))
        .clipShape(Capsule())
    }

    /// Only the sender can end a share, and only while this device is the one
    /// publishing it — a share resumed on another device, or one that already
    /// ended, has nothing here to stop.
    private var showsStopControl: Bool {
        guard isLiveShare, message.direction == .sent, isShareRunning else { return false }
        return LiveLocationSessionManager.shared.isSharing(shareId: shareId)
    }

    private var shareId: String {
        message.message.location?.shareId ?? message.codeMessage
    }

    private func stopSharingButton() -> some View {
        Button {
            guard !isSelectionMode else { return }
            chatVM.stopLiveLocationShare(shareId: shareId)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "stop.circle.fill")
                Text(t(ChatTranslationKeys.LOCATION_LIVE_STOP))
            }
            .font(.caption.weight(.semibold))
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .disabled(isSelectionMode)
        .padding(.horizontal, 5)
        .padding(.top, 2)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
    
    private func playButton() -> some View {
        
        Button{
            
        } label: {
            Image(systemName: "play.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(12)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
    }

    private func shareButton() -> some View {
        Button{
            // Disable share button when in selection mode
            guard !isSelectionMode else { return }
            showMapOptions = true
        } label: {
            Image(systemName: "square.and.arrow.up.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 18, height: 18)
                .padding(10)
                .foregroundColor(.white)
                .background(Color.black.opacity(0.4))
                .clipShape(Circle())
        }
        .disabled(isSelectionMode)
        .allowsHitTesting(!isSelectionMode)
    }
    
    // MARK: - Open in Maps Functions
    
    private func openInMaps() {
        showMapOptions = true
    }
    
    private func openInAppleMaps() {
        let placemark = MKPlacemark(coordinate: coordinate)
        let mapItem = MKMapItem(placemark: placemark)
        mapItem.name = message.message.location?.title ?? "Location"
        mapItem.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving
        ])
    }
    
    private func openInGoogleMaps() {
        let urlString = "comgooglemaps://?q=\(latitude),\(longitude)"
        if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else {
            // Fallback to web version if Google Maps app is not installed
            let webUrlString = "https://www.google.com/maps/search/?api=1&query=\(latitude),\(longitude)"
            if let webUrl = URL(string: webUrlString) {
                UIApplication.shared.open(webUrl)
            }
        }
    }
}


struct UIKitMapViewBubble: UIViewRepresentable {
    var initialRegion: EquatableRegion
    var defaultZoomLevel: CLLocationDegrees
    
    class Coordinator {
        let mapView = MKMapView()

        /// The centre last handed to the map. MapKit adjusts the region it is
        /// given, so its own `region` cannot be compared against the requested
        /// one to decide whether anything changed.
        var appliedCenter: CLLocationCoordinate2D?

        init() {
           mapView.isScrollEnabled = false
           mapView.isZoomEnabled = false
           mapView.isRotateEnabled = false
           mapView.isPitchEnabled = false
           mapView.showsCompass = false
           mapView.showsScale = false
           mapView.showsUserLocation = false
           mapView.isUserInteractionEnabled = false
            
        }
        
        func centerOnUser() {
            mapView.showsUserLocation = true
            mapView.userTrackingMode = .follow
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator()
    }
    
    func makeUIView(context: Context) -> MKMapView {
        let mv = context.coordinator.mapView
        mv.setRegion(initialRegion.region, animated: false)
        context.coordinator.appliedCenter = initialRegion.center

        mv.pointOfInterestFilter = .excludingAll
        mv.showsBuildings = false
        mv.showsTraffic = false

        return mv
    }



    /// Re-centres when the pin moves.
    ///
    /// `makeUIView` sets the region once, which is all a pinned location ever
    /// needs — but a live share moves, and without this the bubble would stay
    /// on the position the share started from for its whole duration.
    func updateUIView(_ uiView: MKMapView, context: Context) {
        let center = initialRegion.center
        if let applied = context.coordinator.appliedCenter,
           applied.latitude == center.latitude,
           applied.longitude == center.longitude {
            return
        }
        context.coordinator.appliedCenter = center
        uiView.setRegion(initialRegion.region, animated: true)
    }
    /// Méthode publique pour bouton externe
    func centerOnUser(_ coordinator: Coordinator) {
        coordinator.centerOnUser()
    }
}
