//
//  LocationPickerView.swift
//  Pods
//
//  Created by Asyst on 6/26/25.
//




import SwiftUI
import MapKit
import WaanguCoreKit


struct SearchBar: View {
    @Binding var text: String
    let translationService: (any TranslationServiceProtocol)?
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
            
            TextField(t(ChatTranslationKeys.LOCATION_SEARCH), text: $text, prompt: Text(t(ChatTranslationKeys.LOCATION_SEARCH_NEARBY)))
                .foregroundColor(.primary)
                .disableAutocorrection(true)
                .textInputAutocapitalization(.never)
                .focused($isFocused) // liaison focus
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                       isFocused = true   // focus automatique
                    }
                }
            
            if !text.isEmpty {
                Button(action: { text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct LocationPickerView: View {
    
    @ObservedObject var galleryVM: GalleryViewModel
    let onSendLocation: ((ChatLocationItem) -> Void)?
    let onDismiss: (() -> Void)?
    let translationService: (any TranslationServiceProtocol)?
    
    @State private var isSearching:Bool = false
    @State private var showActions:Bool = true
    @State private var isShowingPlaces:Bool = true
    @State var showMapType: Bool = false
    @FocusState private var isSearchFocused: Bool

    @State private var mapHeight: CGFloat = 300
    
    @StateObject private var viewModel: LocationPickerViewModel
    @StateObject private var searchVM =  SearchPlacesViewModel()
    
    @Environment(\.dismiss) private var dismiss
    
    init(
        galleryVM: GalleryViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onSendLocation: ((ChatLocationItem) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self._galleryVM = ObservedObject(initialValue: galleryVM)
        self.translationService = translationService
        self.onSendLocation = onSendLocation
        self.onDismiss = onDismiss
        self._viewModel = StateObject(
            wrappedValue: LocationPickerViewModel(roomId: "")
        )
    }

    var body: some View {
        VStack {
            ZStack(alignment: .top) {
                
                // MAP
                ParallaxMapContainerRepresentable(
                    viewModel: viewModel,
                    mapHeight: 300
                )
                .edgesIgnoringSafeArea(.all)
                .frame(maxHeight: .infinity)
                .zIndex(0)
                
                // HEADER (toujours au-dessus de la carte)
                VStack {
                    header()
                        .overlay(Divider(), alignment: .bottom)
                    
                    if viewModel.isMapExpanded {
                        Button(t(ChatTranslationKeys.LOCATION_PLACES_IN_AREA)) {
                            withAnimation {
                                viewModel.isMapExpanded.toggle()
                            }
                        }
                        .font(.subheadline)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.2), radius: 5, x: 0, y: 2)
                        .padding(.top, 5)
                    }
                    
                    if viewModel.showActions && !isSearching {
                        mapActions()
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                            .animation(.easeInOut(duration: 0.3), value: [viewModel.showActions, isSearching])
                    }
                }
                .zIndex(2)
                
           
                if isSearching {
                    SearchPlacesView(viewModel: searchVM, locationVM: viewModel, translationService: translationService)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 65)
                        .background(Color.white)
                        .zIndex(1)
                }
            }
             .onReceive(viewModel.$currentLocation) { location in
                searchVM.currentLocation = location
            }
             .onAppear{
                 searchVM.currentLocation = viewModel.currentLocation
                 viewModel.onDismiss = { 
                     onDismiss?()
                     dismiss() 
                 }
                 viewModel.onSendLocation = { location in
                     onSendLocation?(location)
                 }
             }
     
             .confirmationDialog(
                  t(ChatTranslationKeys.LOCATION_LIVE_SHARE_PROMPT),
                   isPresented: $viewModel.showLiveLocationDialog,
                   titleVisibility: .visible,
               ) {
                   Button(t(ChatTranslationKeys.LOCATION_FOR_15_MIN)) {
                       viewModel.startLiveLocationWithTimer(for: 15 * 60)
                   }
                   
                   Button(t(ChatTranslationKeys.LOCATION_FOR_1_HOUR)) {
                       viewModel.startLiveLocationWithTimer(for: 60 * 60)
                   }
                   
                   Button(t(ChatTranslationKeys.LOCATION_FOR_8_HOURS)) {
                       viewModel.startLiveLocationWithTimer(for: 8 * 60 * 60)
                   }
                   
                   Button(t(ChatTranslationKeys.LOCATION_UNTIL_TURNED_OFF)) {
                       // The contract has no unbounded share — 15, 30, 60 and
                       // 480 minutes are the only durations it accepts — so
                       // this takes the longest one. It used to take 15
                       // minutes, which is the option furthest from what the
                       // button says.
                       viewModel.startLiveLocationWithTimer(
                           for: LiveLocationDuration.eightHours.seconds
                       )
                   }
                   
                   Button(common("cancel"), role: .cancel) {
                       viewModel.isTrackingLiveLocation = false
                       debugLog("canceled_live")
                   }
               }
        }
    }


    
   
    }




extension LocationPickerView {
    
    @ViewBuilder
    func mapActions () -> some View {
         
        HStack {
            Spacer()
           
               VStack( spacing: 0) {
                   Button(action: {
                       withAnimation{
                           showMapType.toggle()
                       }
                   }) {
                       Image(systemName: showMapType ? "info.circle.fill" : "info.circle")
                           .padding()
                           .background(Color.white)
                           .foregroundColor(.blue)
                   }
                   .buttonStyle(PlainButtonStyle())
                   Divider().frame(width: 1,).foregroundColor(.gray)
                   Button(action: {
                       debugLog("Filter tapped")
                   }) {
                       Image(systemName: "location.fill")
                           .padding()
                           .background(Color.white)
                           .foregroundColor(.blue)

                   }.buttonStyle(PlainButtonStyle())
               }
               .cornerRadius(16)
               .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
               .padding(.trailing)
               .frame(width:30)
               .padding(.trailing)
            
        }
        
    }
    
    @ViewBuilder
    func header() -> some View {
        VStack(spacing: 0) {
            
            HStack {
                if isSearching {
                    SearchBar(text: $searchVM.query, translationService: translationService)
                        .transition(.move(edge: .leading).combined(with: .opacity))
                    
                    Button(common("cancel")) {
                        withAnimation(.easeInOut) {
                            isSearching = false
                            searchVM.query = ""
                        }
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    
                } else {
                    Button(common("cancel")) {
                        dismiss()
                    }
                    Spacer()
                    Text(t(ChatTranslationKeys.LOCATION_SCREEN_TITLE))
                        .bold()
                        .transition(.opacity)
                    
                    Spacer()
                    
                    Button(action: {
                        withAnimation(.easeInOut) {
                            isSearching = true
                            showMapType = false
                        }
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
                
            }
            .padding()
            .animation(.easeInOut, value: isSearching)
            
            
            if showMapType && !isSearching {
                Picker("Map Type", selection: $viewModel.selectedMapType) {
                    ForEach(MapTypeOption.allCases) { option in
                        Text(option.rawValue.capitalized).tag(option)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                
                .padding(.top, 4)
                .padding(.bottom, 8)
                .padding(.horizontal, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: showMapType)
            }
            
           
        }   .background(
            ZStack {
                Color.clear.background(.ultraThinMaterial)
                Color.white.opacity(0.8)
            }
        )
     
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }

}


struct RoundedCornersShape: Shape {
    var corners: UIRectCorner
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}

struct SearchPlacesView: View {

    @ObservedObject var viewModel: SearchPlacesViewModel
    @ObservedObject var locationVM: LocationPickerViewModel
    let translationService: (any TranslationServiceProtocol)?
    
    init(viewModel: SearchPlacesViewModel, locationVM: LocationPickerViewModel, translationService: (any TranslationServiceProtocol)? = nil) {
        self.viewModel = viewModel
        self.locationVM = locationVM
        self.translationService = translationService
    }

    var body: some View {
        VStack {

            Group {
                if viewModel.errorMessage == nil &&
                   viewModel.isLoading == false &&
                   viewModel.places.count == 0 {
                    
                    Text(t(ChatTranslationKeys.LOCATION_NO_PLACES))
                    Text(t(ChatTranslationKeys.LOCATION_NO_PLACES_QUERY, args: [viewModel.query]))
                       
                }else {
                    List(viewModel.places, id: \.self) { item in
                        
                        PlaceRow(
                            icon:locationVM.mapKitIconName(for: item),
                            name: item.name ?? "Lieu inconnu",
                            location: item.placemark.title ?? ""
                        )
                    
                    }
                    .listStyle(.plain)
                }
            }
            
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        
        
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}



private struct PlaceRow: View {
    let icon: String
    let name: String
    let location: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(Color.orange)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 16))
                 
                if !location.isEmpty {
                    Text(location)
                        .font(.system(size: 14))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}


