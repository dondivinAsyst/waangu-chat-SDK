
//
//  AlbumView.swift
//  Pods
//
//  Created by Asyst on 8/31/25.
//
import SwiftUI
import SDWebImageSwiftUI
import AVKit
import WaanguCoreKit


struct ActionItem: Identifiable {
    let id = UUID()
    let iconLabel: String
    let icon: String
    var isDestructive: Bool = false
}

var deleteAction: [ActionItem] = [
    ActionItem(iconLabel: "Delete for me ", icon: "square.and.arrow.down"),
    ActionItem(iconLabel: "Reply", icon: "arrowshape.turn.up.left"),
    ActionItem(iconLabel: "Delete", icon: "trash", isDestructive: true)
]

var actions: [ActionItem] = [
    ActionItem(iconLabel: "Save Image", icon: "square.and.arrow.down"),
    ActionItem(iconLabel: "Reply", icon: "arrowshape.turn.up.left"),
    ActionItem(iconLabel: "Delete", icon: "trash", isDestructive: true)
]

struct MediaAlbumView: View {
    
   let imageTransitionNamespace: Namespace.ID
   let userName: String
   let mediaMessages: [MessageDataItem]
   let selectedIndex: Int
   let sourceFrame: CGRect
   let selectedMessage: MessageDataItem?
   let onIndexChange: (MessageDataItem) -> Void
   let onDismiss: () -> Void
   let translationService: (any TranslationServiceProtocol)?
    
    init(
        imageTransitionNamespace: Namespace.ID,
        userName: String,
        mediaMessages: [MessageDataItem],
        selectedIndex: Int,
        sourceFrame: CGRect,
        selectedMessage: MessageDataItem?,
        onIndexChange: @escaping (MessageDataItem) -> Void,
        onDismiss: @escaping () -> Void,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.imageTransitionNamespace = imageTransitionNamespace
        self.userName = userName
        self.mediaMessages = mediaMessages
        self.selectedIndex = selectedIndex
        self.sourceFrame = sourceFrame
        self.selectedMessage = selectedMessage
        self.onIndexChange = onIndexChange
        self.onDismiss = onDismiss
        self.translationService = translationService
    }
    
    @State private var currentIndex: Int = 0
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var deleteConfirmationShown = false
    @State private var animateIn = false
    @State private var showAlbum = false
    @State private var animateOut = false
    @State private var scale: CGFloat = 0
    @State private var offset: CGSize = .zero
    @State private var backgroundOpacity = 1.0
    @State private var contentScale: CGFloat = 0.8
    @State private var contentOffset: CGSize = .zero
    
    @State private var renderFirstTime: Bool = true
    
    private var currentMedia: MessageDataItem {
        mediaMessages[currentIndex]
    }
    
    var body: some View {
        GeometryReader { proxy in
            VStack {
                
                ZStack {
                    
                    Color.clear
                        .contentShape(Rectangle())
                        .zIndex(10)
                        .onTapGesture {
                            showControls.toggle()
                        }
                    
               
                        TabView(selection: $currentIndex) {
                            ForEach(Array(mediaMessages.enumerated()), id: \.element.id) { index, media in
                                
                                MediaDetailView(
                                    media: media,
                                    animateIn: animateIn,
                                    translationService: translationService
                                )
                                    .tag(index)
                                
//                                MediaDetailView(
//                                    namespace: imageTransitionNamespace,
//                                    media: media,
//                                    animateIn: animateIn
//                                )
//                                .tag(index)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(
                            width: animateIn ? proxy.size.width : sourceFrame.width,
                            height: animateIn ? proxy.size.height : sourceFrame.height
                        )
                        .position(
                            x: animateIn ? proxy.size.width / 2 : sourceFrame.minX - proxy.frame(in: .global).minX + sourceFrame.width / 2,
                            y: animateIn ? proxy.size.height / 2 : sourceFrame.minY - proxy.frame(in: .global).minY + sourceFrame.height / 2
                        )
                        .onChange(of: currentIndex){ newValue in
                            onIndexChange(mediaMessages[newValue])
                        }
//
                    
                    
                    if showControls {
                        VStack {
                            HeaderView
                            Spacer()
                            FooterView
                        }
                        .transition(.opacity)
                        .animation(.easeInOut(duration: 0.3), value: showControls)
                        .opacity(animateIn ? 1.0 : 0.0)
                        .zIndex(11)
                    }
                }
                .statusBar(hidden: !showControls)
                .onAppear {
                    currentIndex = selectedIndex
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        animateIn = true
                        
                    }
                    
                }
                
            }
            .background(.black.opacity(backgroundOpacity))
            .padding(.zero)
            
        }
    }
        // MARK: - Components
        
        private var FooterView: some View {
            HStack(alignment: .center) {
                Button(action: {}) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                
                Spacer()
                
                VStack {
                    Text(currentMedia.senderName)
                        .font(.headline)
                        .foregroundColor(.white)
                    //                    .padding(8)
                    //                    .background(Capsule().fill(Color.black.opacity(0.4)))
                    Text(currentMedia.displayTime)
                        .font(.caption)
                        .foregroundColor(.white)
                }
                
                Spacer()
                
                Button(action: { deleteConfirmationShown = true }) {
                    Image(systemName: "trash")
                        .font(.title2)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Circle().fill(Color.black.opacity(0.4)))
                }
                .confirmationDialog(t(ChatTranslationKeys.GALLERY_CHOOSE_ACTION), isPresented: $deleteConfirmationShown ){
                    Button(t(ChatTranslationKeys.GALLERY_DELETE_FOR_ME), role: .destructive){}
                    Button(t(ChatTranslationKeys.GALLERY_DELETE_FOR_ME_AND_USER, args: [userName]), role: .destructive){}
                    Button(common("cancel"), role: .cancel) {}
                }
            }
            .padding(.horizontal)
            
        }
   
    
    private var HeaderView: some View {
        HStack {
            Button(action: {
             
                
                onIndexChange(currentMedia)
              
               
                withAnimation(.easeInOut(duration: 0.2)) {
                    backgroundOpacity = 0
                    animateIn = false
                }

//                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
//                    animateIn = false
//                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                       onDismiss()
                    }
                  
                }
              
            }) {
                Image(systemName: "xmark")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(12)
                    .background(Circle().fill(Color.black.opacity(0.4)))
            }
            
            Spacer()
            
            Text("\(currentIndex + 1)/\(mediaMessages.count)")
                .font(.headline)
                .foregroundColor(.white)
                .padding(8)
                .background(Capsule().fill(Color.black.opacity(0.4)))
            
            Spacer()
            
            Menu {
        
                ForEach(actions) { act in
                    Button(role: act.isDestructive ? .destructive : nil) {
                        if act.isDestructive {
                            deleteConfirmationShown = true
                        }
                    } label: {
                        HStack {
                            Text(act.iconLabel)
                            if !act.icon.isEmpty {
                                Image(systemName: act.icon)
                            }
                        }
                        .padding(8)
                    }
                }

            } label: {
                Button {} label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.white)
                        .font(.title2)
                        .padding(8)
                }
                
            }
            .menuStyle(BorderlessButtonMenuStyle())
            .font(.system(size: 14))
        }
        .padding(.horizontal)
        .padding(.top, 50) // Ajoutez un padding en haut pour éviter le notch
    }
  
    
    // MARK: - Gestures
    
    private var tapGesture: some Gesture {
        TapGesture()
            .onEnded {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showControls.toggle()
                }
//                resetControlsTimer()
            }
    }
    
    // MARK: - Actions
    
    private func dismiss() {
//        isPresented = false // Utilisez le binding correctement
    }
    
    private func shareMedia() {
        guard let urlString = currentMedia.message.image,
              let url = URL(string: urlString) else { return }
        
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootViewController = windowScene.windows.first?.rootViewController {
            rootViewController.present(activityVC, animated: true)
        }
    }
    
    // MARK: - Timer Management
    
//    private func startControlsTimer() {
//        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
//            withAnimation {
//                showControls = false
//            }
//        }
//    }
//
//    private func stopControlsTimer() {
//        controlsTimer?.invalidate()
//        controlsTimer = nil
//    }
//
//    private func resetControlsTimer() {
//        stopControlsTimer()
//        if showControls {
//            startControlsTimer()
//        }
//    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

struct MediaDetailView: View {
//    let namespace: Namespace.ID
    let media: MessageDataItem
    let animateIn: Bool
    let translationService: (any TranslationServiceProtocol)?

    init(
        media: MessageDataItem,
        animateIn: Bool,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.media = media
        self.animateIn = animateIn
        self.translationService = translationService
    }

    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    
    var body: some View {
        ZStack {
         
            
            if media.typeMessage == .IMAGE {
                imageView
            } else if media.typeMessage.isVideo {
                videoView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .gesture(doubleTapGesture)
        .gesture(magnificationGesture)
        .gesture(dragGesture)
        .padding(.zero)
    }
    
    private var imageView: some View {
        Group {
           
            if let urlString = media.message.image, let url = URL(string: urlString) {
                WebImage(url: url)
                    .resizable()
//                    .matchedGeometryEffect(
//                        id: media.id,
//                        in: namespace,
//                        isSource: false
//                    )
                    .scaledToFit()
                    .scaleEffect(scale)
                    .offset(offset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var videoView: some View {
        Group {
            if let urlString = media.message.video, let url = URL(string: urlString) {
                VideoPlayer(player: AVPlayer(url: url))
                    .edgesIgnoringSafeArea(.all)
            } else {
                Text(t(ChatTranslationKeys.GALLERY_VIDEO_UNAVAILABLE))
                    .foregroundColor(.white)
            }
        }
    }
    
    // MARK: - Gestures
    
    private var doubleTapGesture: some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    if scale > 1.0 {
                        resetZoom()
                    } else {
                        scale = 3.0
                    }
                }
            }
    }
    
    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                scale = min(max(scale * delta, 1.0), 5.0)
                lastScale = value
            }
            .onEnded { _ in
                lastScale = 1.0
                if scale <= 1.0 {
                    withAnimation {
                        resetZoom()
                    }
                }
            }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
    
    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                }
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }
    
    private func resetZoom() {
        scale = 1.0
        offset = .zero
        lastOffset = .zero
    }
}

