//
//  LocationPickerViewKit.swift
//  Pods
//
//  Created by Asyst on 9/22/25.
//

import UIKit
import MapKit
import SwiftUI
import Combine


class ParallaxMapContainerViewController: UIViewController, UIScrollViewDelegate, MKMapViewDelegate {

    // MARK: - UI
    private let mapView = MKMapView()
    private let scrollView = UIScrollView()
    private let centerPin = UIImageView(image: UIImage(systemName: "mappin"))
    private let contentView = UIView()
    
    private var isMapExpanded = false
    
    // MARK: CONSTRAINTS
    private var bottomSheetTopConstraint: NSLayoutConstraint?
    private var centerPinYConstraint: NSLayoutConstraint?
    
    // MARK: - Propriétés
    private var bottomSheetView: MapBottomSheet?
    private var miniBottomSheetView: MapBottomSheet?
    private var mapHeightConstraint: NSLayoutConstraint?

    private let mapHeight: CGFloat
    private var onRegionChange: ((EquatableRegion) -> Void)?
    
    private let viewModel: LocationPickerViewModel


    private var subscriptions = Set<AnyCancellable>()
    
    // MARK: - Init
    init(
        _ viewModel: LocationPickerViewModel,
        mapHeight: CGFloat
    ) {
        self.viewModel = viewModel
        self.mapHeight = mapHeight
        super.init(nibName: nil, bundle: nil)
    }

    
    override func viewDidLoad() {
        super.viewDidLoad()

        setupScrollView()
        setupMap()
        setupBottomSheet()
        
        setupListeners()
        
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleMapGesture(_:)))
           panGesture.delegate = self
           mapView.addGestureRecognizer(panGesture)

           let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handleMapGesture(_:)))
           pinchGesture.delegate = self
           mapView.addGestureRecognizer(pinchGesture)
    }

    
    deinit {
        NotificationCenter.default.removeObserver(self)
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
    }
    

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    
    // MARK: - Setup Listeners
    
     private func setupListeners() {
        
         viewModel.$isMapExpanded
             .dropFirst()
             .debounce(for: .milliseconds(20), scheduler: DispatchQueue.main)
             .sink { [weak self] isMapExpanded in
                 guard let self = self else { return }
                 if isMapExpanded {
                     self.expandMapAndShowMiniBottomSheet()
                 } else {
                     self.collapseMapAndShowBottomSheet()
                 }
             }
             .store(in: &subscriptions)

         
          viewModel.$selectedMapType
             .debounce(for: .milliseconds(0), scheduler: DispatchQueue.main)
             .sink { [weak self] mapType in
                 guard let self = self else { return }
                
                 mapView.mapType  = mapType.mapKitType
                 
             }.store(in: &subscriptions)
         
         viewModel.$actionMiniBottomSheet
            .dropFirst()
            .debounce(for: .milliseconds(0), scheduler: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self = self else { return }
               
                if self.viewModel.isMapExpanded {
                    self.setupMiniBottomSheet()
                }
                
            }.store(in: &subscriptions)
         
         viewModel.$actionsMiniBottomSheet
            .dropFirst()
            .debounce(for: .milliseconds(0), scheduler: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self = self else { return }
                self.setupBottomSheet(actionsMiniBottomSheet:data)
            }.store(in: &subscriptions)
         
         
         viewModel.$places
            .dropFirst()
            .debounce(for: .milliseconds(0), scheduler: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self = self else { return }
                self.setupBottomSheet(places:data)
            }.store(in: &subscriptions)
         
         viewModel.$initialRegion
            .dropFirst()
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] initial in
                guard let self = self else { return }
                
                let initial = MKCoordinateRegion(
                    center: viewModel.initialRegion.region.center,
                    span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                )

                mapView.setRegion(initial, animated: false)
                
            }.store(in: &subscriptions)
         
    }

    // MARK: - Setup Map
    
    private func mapPinView(in parent: UIView) {
        centerPin.tintColor = .systemBlue
        centerPin.translatesAutoresizingMaskIntoConstraints = false
        parent.addSubview(centerPin)
        
        centerPinYConstraint = centerPin.centerYAnchor.constraint(equalTo: parent.centerYAnchor, constant: -20)
        
        NSLayoutConstraint.activate([
            centerPin.centerXAnchor.constraint(equalTo: parent.centerXAnchor),
            centerPinYConstraint!,
            centerPin.widthAnchor.constraint(equalToConstant: 42),
            centerPin.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    private func setupMap() {

//        mapView.setRegion(viewModel.initialRegion.region, animated: false)
        mapView.mapType = viewModel.selectedMapType.mapKitType
        mapView.showsUserLocation = true
        mapView.userTrackingMode = .follow
        
        mapView.delegate = self
        
        contentView.addSubview(mapView)
        mapView.translatesAutoresizingMaskIntoConstraints = false

//      let maxHeigh = UIScreen.main.bounds.height
        mapHeightConstraint = mapView.heightAnchor.constraint(equalToConstant: mapHeight)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mapHeightConstraint!
        ])
        
        mapPinView(in : mapView)
    }



    // MARK: - Setup ScrollView
    private func setupScrollView() {
           scrollView.delegate = self
           scrollView.contentInsetAdjustmentBehavior = .never
           
           view.addSubview(scrollView)
           scrollView.translatesAutoresizingMaskIntoConstraints = false
           
           // Add content view to scroll view
           scrollView.addSubview(contentView)
           contentView.translatesAutoresizingMaskIntoConstraints = false
           
           NSLayoutConstraint.activate([
               scrollView.topAnchor.constraint(equalTo: view.topAnchor),
               scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
               scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
               scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
               
               contentView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
               contentView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
               contentView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
               contentView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
               contentView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor)
           ])
       }
    
    

    // MARK: - Setup BottomSheet
    private func setupBottomSheet(
        skeletonCount: Int = 15,
        actionsMiniBottomSheet: [PlaceAction]? = nil,
        places: [MKMapItem]? = nil
    ) {
        var placesList: [UIView] = []
        var actionsItems: [UIView] = []
        var skeletonList: [UIView] = []
           
          for action in viewModel.actionsMiniBottomSheet {
            let row = PlaceRowKit(
                icon: action.icon,
                name: action.name,
                location: action.location,
                color: action.action == .sendCurrentLocation ? .systemBlue : .systemGreen
            )
            
            row.onTap = {
                self.viewModel.onTapAction(action: action.action)
            }
            
            actionsItems.append(row)
         }
        
        for place in viewModel.places {
          let row = PlaceRowKit(
            icon: viewModel.mapKitIconName(for: place),
            name: place.name ?? "Lieu inconnu",
            location: place.placemark.title ?? ""
          )
          
          row.onTap = {
              self.viewModel.onTapPlaceItem(for: place)
          }
          
          placesList.append(row)
       }

           
        for _ in 0..<skeletonCount {
            let skeletonRow = PlaceRowSkeletonView()
            skeletonRow.startAnimating()
            skeletonList.append(skeletonRow)
        }
        
        let dataItems = placesList.count > 0 ? placesList : skeletonList
        let sheet = MapBottomSheet(
        items: actionsItems + dataItems)
        contentView.addSubview(sheet)
        sheet.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
           sheet.topAnchor.constraint(equalTo: mapView.bottomAnchor, constant: -20),
           sheet.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
           sheet.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
           sheet.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
         ])

        
        bottomSheetView = sheet
    }
    
 


    
    private func setupMiniBottomSheet() {
        let data = viewModel.actionMiniBottomSheet
        
        let row = PlaceRowKit(
            icon: data.icon,
            name: data.name,
            location: data.location,
            color: .systemBlue ,
            isBordered: false
        )
        
        row.onTap = {
            self.viewModel.onSendPinedLocation()
            
        }

        var itemsToShow: [UIView] = []
        itemsToShow.append(row)

        if let miniSheet = miniBottomSheetView {
            miniSheet.updateItems(itemsToShow)
            miniSheet.animateAppearance()
            return
        }

  
        let miniSheet = MapBottomSheet(items: itemsToShow)
        view.addSubview(miniSheet)
        miniSheet.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            miniSheet.topAnchor.constraint(equalTo: view.bottomAnchor, constant: -160),
            miniSheet.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            miniSheet.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            miniSheet.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        miniSheet.animateAppearance()
        miniBottomSheetView = miniSheet
    }




    // MARK: - ScrollViewDelegate (Parallax)
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        
        guard !viewModel.isMapExpanded else { return }
        
        let offsetY = scrollView.contentOffset.y
        let factor: CGFloat = 0.5
       
        let offset = offsetY * factor
        if offset > 45 {
            if viewModel.showActions {
                viewModel.showActions = false
            }
              
           } else {
               if  !viewModel.showActions {
                   viewModel.showActions = true
               }
           }
        
          mapView.transform = CGAffineTransform(translationX: 0, y: offset)
    }
    

    // MARK: - Map Delegate
    func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
        onRegionChange?(EquatableRegion(mapView.region))
        animatePin(to: -20)
        let center = mapView.centerCoordinate
        viewModel.fetchPlaceDetails(for: center)
        
     }
     func mapView(_ mapView: MKMapView, regionWillChangeAnimated animated: Bool) {
           animatePin(to: -40)
        
     }
    
    
    private func animatePin(to constant: CGFloat) {
        centerPinYConstraint?.constant = constant
        UIView.animate(withDuration: 0.3, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    
    private func expandMapAndShowMiniBottomSheet() {
        bottomSheetView?.removeFromSuperview()
        bottomSheetView = nil
        
        scrollView.isScrollEnabled = false
        
        let maxHeight = UIScreen.main.bounds.height
        
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut]) {
            self.mapHeightConstraint?.constant = maxHeight
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.transferMapToMainView()
            self.setupMiniBottomSheet()
        }
    }

    private func transferMapToMainView() {
        let currentFrame = mapView.frame
        mapView.removeFromSuperview()
        
        // 3. Désactiver toutes les contraintes
        NSLayoutConstraint.deactivate(mapView.constraints)
        
        // 4. Ajouter à la view principale avec le même frame
        mapView.translatesAutoresizingMaskIntoConstraints = true
        mapView.frame = currentFrame
        view.addSubview(mapView)
        
        mapView.translatesAutoresizingMaskIntoConstraints = false

        let maxHeigh = UIScreen.main.bounds.height
        mapHeightConstraint = mapView.heightAnchor.constraint(equalToConstant: maxHeigh)

        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: view.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            mapHeightConstraint!
        ])
        
        mapPinView(in : mapView)
        
        // 6. Supprimer le scrollView
        scrollView.removeFromSuperview()
        contentView.removeFromSuperview()
    }

    private func collapseMapAndShowBottomSheet() {
        // 1. Supprimer la mini bottom sheet
        miniBottomSheetView?.removeFromSuperview()
        miniBottomSheetView = nil
        
        setupScrollView()
        
        // 3. Sauvegarder le frame actuel de la map
        let currentFrame = mapView.frame
        
        // 4. Préparer la map pour le transfert
        mapView.removeFromSuperview()
        NSLayoutConstraint.deactivate(mapView.constraints)
        
        //Remettre la map dans le contentView avec la même position
        mapView.translatesAutoresizingMaskIntoConstraints = true
        mapView.frame = currentFrame
        contentView.addSubview(mapView)
        
        view.layoutIfNeeded()
        
        mapView.translatesAutoresizingMaskIntoConstraints = false
        mapHeightConstraint = mapView.heightAnchor.constraint(equalToConstant: mapHeight)
        
        NSLayoutConstraint.activate([
            mapView.topAnchor.constraint(equalTo: contentView.topAnchor),
            mapView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            mapView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            mapHeightConstraint!
        ])
        
        mapPinView(in : mapView)
        
        UIView.animate(withDuration: 0.4, delay: 0, options: [.curveEaseInOut]) {
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.scrollView.isScrollEnabled = true
            self.setupBottomSheet()
        }
        
       
    }
    
 

 }

extension ParallaxMapContainerViewController : UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    @objc private func handleMapGesture(_ gesture: UIGestureRecognizer) {
        guard !viewModel.isMapExpanded else { return }
        if gesture.state == .began {
            DispatchQueue.main.async {
                if !self.viewModel.isMapExpanded {
                    self.viewModel.isMapExpanded = true
                }
            }
        }
    }
}


struct ParallaxMapContainerRepresentable: UIViewControllerRepresentable {
    
    var viewModel: LocationPickerViewModel
    let mapHeight: CGFloat
 
    func makeUIViewController(context: Context) -> ParallaxMapContainerViewController {
        let vc = ParallaxMapContainerViewController(
            viewModel,
            mapHeight: mapHeight,
        )
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ParallaxMapContainerViewController, context: Context) {
        // synchronisation vers UIKit si nécessaire
        uiViewController.view.layoutIfNeeded()
    }
}


struct TestScrollOffsetView: View {
    @State private var region = EquatableRegion(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: -3.382546, longitude:29.365116),
            span: MKCoordinateSpan(latitudeDelta: 0.035, longitudeDelta: 0.035)
        )
    )
    
    @State private var isPresented: Bool = true
    
//    @StateObject private var viewModel = LocationPickerViewModel()
    
    var body: some View {
        Color.red.chatAppearanceSheet(isPresented:$isPresented){
            EmptyView()
//            ParallaxMapContainerRepresentable(
//                viewModel: viewModel,
//                mapHeight: 300,
//              
//            )
//            .edgesIgnoringSafeArea(.all)
        }
       
    }
}

