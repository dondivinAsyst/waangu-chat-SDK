// MARK: - StatusEditorView.swift
import SwiftUI
import UIKit
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct StatusEditorView: View {
    @Environment(\.dismiss) var dismiss
    let statusStore:StoriesViewModel
    let translationService: (any TranslationServiceProtocol)?
    @State private var selectedColor: Color = ConstantColors.customColors.randomElement() ?? Color(red: 1.0, green: 0.4, blue: 0.4)
    @State private var statusText: String = ""
    @State private var selectedTab: EditorTab = .text
    @State private var textHeight: CGFloat = 40
//    @State private var text: String = ""
    @State private var textWidth: CGFloat = 0
    @State private var openColorSelector: Bool = false
    @State private var openTextStyleSelector: Bool = false
    @State private var isAtLimit : Bool = false
    var onAppearTab: () -> Void
    /// True while the text tab is the selected one. Drives keyboard focus, since
    /// the view now stays mounted while other tabs are showing.
    var isActive: Bool = true
    @State private var  selectedFontIndex : Int = 0
    @State private var fontSize: CGFloat = TextStatusFontSizing.baseFontSize
//       private let fontData = FontData.shared
    private let fontData = ConstantFont.shared.AllFonts
    private let colors = ConstantColors.customColors
    
    init(
        statusStore: StoriesViewModel,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAppearTab: @escaping () -> Void,
        isActive: Bool = true
    ) {
        self.statusStore = statusStore
        self.translationService = translationService
        self.onAppearTab = onAppearTab
        self.isActive = isActive
    }
    
    private func onPublishStatus(){
       
        let status:StoryToSend = StoryToSend(
            id: StatusIDGenerator.newCode(),
            userId: CurrentSessionInfo.shared.currentUid,
                                              type: .text,
                                              content: statusText,
                                              background: selectedColor.toHex(),
                                               fontText: fontData[selectedFontIndex].family , fontWeight: fontData[selectedFontIndex].weight ,fontSize:Int(fontSize),userName: CurrentSessionInfo.shared.userName,userImage:nil)
      
        Task{
            await statusStore.addOwnStatus(story:status)
            dismiss()
        }
    }

    let screenWidth = UIScreen.main.bounds.width
    @State private var inputWidth: CGFloat = 0
    
    var body: some View {
        ZStack {
            selectedColor.ignoresSafeArea()
//            StatusEditorTopBar(dismiss: dismiss)
            
            VStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
                // Top Bar
//                StatusEditorTopBar(dismiss: dismiss)
                
                Spacer()
//                Text("Width: \(screenWidth)")
//                    .padding()
                VStack {
//
                        
//
//                    PerfectCenteredTextEditor(text:$statusText,CurrentFontStyle: fontData.getFont(for: selectedFontIndex, size: fontSize), fontSize: $fontSize, isAtLimit: $isAtLimit, textColor: .white).onTapGesture {
                    PerfectCenteredTextEditor(text:$statusText,CurrentFontStyle: .applyFontCustom(fontData[selectedFontIndex],size: fontSize), fontSize: $fontSize, isAtLimit: $isAtLimit, textColor: .white, translationService: translationService, isActive: isActive).onTapGesture {
                        debugLog("Tapped")
                    }

                    
                    
                    Spacer()
                 
                }
            }.navigationBarBackButtonHidden(true)
            VStack{
                Spacer()
                if openColorSelector {
                    
                    // Color Picker
                                      ColorPickerBar(colors: colors, selectedColor: $selectedColor)
                }
                if openTextStyleSelector {
                    FontStylePickerBar(selectedIndex: $selectedFontIndex)
                }
              
            } .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            // Fixed Top Bar
            VStack {
                StatusEditorTopBar(
                     dismiss:
                        dismiss
                    ,
                    
                    onSend: {
                        onPublishStatus()
                    },
                             openColorSelector:openColorSelector,
                             openTextStyleSelector:openTextStyleSelector,
                             translationService: translationService,
                             text: $statusText,
                             onTextTapped: {
                               openTextStyleSelector = !openTextStyleSelector
                                 openColorSelector = false
                             },
                             onAppearTab : onAppearTab,
                             onPaletteTapped: {
                               openColorSelector = !openColorSelector
                                 openTextStyleSelector = false
                             }
                             
                         )
                
                Spacer() // pushes it to the top
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.vertical,50)
        }.onAppear(){
           selectedColor = ConstantColors.customColors.randomElement() ?? Color(red: 1.0, green: 0.4, blue: 0.4)
        }
    }
}

public enum EditorTab: CaseIterable, Hashable {
    case video, photo, text

    /// The camera mode this tab implies, or `nil` for the text editor.
    var cameraMode: CameraMode? {
        switch self {
        case .video: return .video
        case .photo: return .photo
        case .text:  return nil
        }
    }
}


// Most reliable approach using frame alignment

struct PerfectCenteredTextEditor: View {
    @Binding var text: String
    @State private var currentHeight: CGFloat = 200
    @FocusState private var isFocused: Bool   // iOS 15+ focus tracking
    var CurrentFontStyle : Font
    @Binding var fontSize : CGFloat
    @Binding var isAtLimit : Bool
    @State var showToast : Bool = false
    var textColor: Color  // NEW: injected text color
    let translationService: (any TranslationServiceProtocol)?
    
    var placeholder: String = "Type a status"
    /// When false the editor is off-screen behind another tab and must not hold
    /// the keyboard.
    var isActive: Bool = true
    
    init(
        text: Binding<String>,
        CurrentFontStyle: Font,
        fontSize: Binding<CGFloat>,
        isAtLimit: Binding<Bool>,
        textColor: Color,
        translationService: (any TranslationServiceProtocol)? = nil,
        placeholder: String = "Type a status",
        isActive: Bool = true
    ) {
        self._text = text
        self.CurrentFontStyle = CurrentFontStyle
        self._fontSize = fontSize
        self._isAtLimit = isAtLimit
        self.textColor = textColor
        self.translationService = translationService
        self.placeholder = placeholder
        self.isActive = isActive
    }
    
    var body: some View {
        ZStack {
            Color.clear
                .ignoresSafeArea()
            
            // Text Editor
            if #available(iOS 16.0, *) {
                TextEditorView(text: $text, height: $currentHeight)
                    .frame(height: currentHeight)
                    .bold()
                    .font(CurrentFontStyle)
                    .foregroundColor(textColor) // UPDATED
                    .focused($isFocused)
                    .padding(.top,150)
                
                    .onChange(of: text) { newValue in
                        if newValue.count > TextStatusFontSizing.maxCharacterCount {
                            text = String(newValue.prefix(TextStatusFontSizing.maxCharacterCount))
                            withAnimation {
                                showToast = true
                            }
                            isAtLimit = true
                        } else {
                            isAtLimit = newValue.count >= TextStatusFontSizing.maxCharacterCount
                        }
                        // WhatsApp-like: shrink only when text no longer fits the screen rect.
                        fontSize = TextStatusFontSizing.fittedFontSizeForScreen(text: text)
                    }
                    .task {
                        // 👇 Give editor focus when view appears, but only if the
                        // text tab is the one actually showing.
                        guard isActive else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if isActive { isFocused = true }
                        }
                    }
                    .onChange(of: isActive) { _, active in
                        // Coming back to the text tab reopens the keyboard;
                        // leaving it puts the keyboard away.
                        isFocused = active
                    }
            } else {
                // Fallback on earlier versions
            }
            
            // Overlay indicator (like a placeholder)
            if text.isEmpty {
                Text(placeholder)
                    .foregroundColor(.gray)
                    .font(.title)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: text.isEmpty).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Toast overlay
                      if showToast {
                          Text(t(ChatTranslationKeys.STORIES_CHARACTER_LIMIT))
                              .padding()
                              .background(.black.opacity(0.5))
                              .foregroundColor(.white)
                              .cornerRadius(10)
                              .transition(.move(edge: .bottom).combined(with: .opacity))
                              .zIndex(1)
                              .onAppear {
                                  // Hide after 2 seconds
                                  DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                      withAnimation {
                                          showToast = false
                                      }
                                  }
                              }
                              .padding(.top, 300)
                      }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}



struct TextEditorView: View {
    @Binding var text: String
    @Binding var height: CGFloat
    
    // New callback to notify when user taps or enters
    var onActivate: (() -> Void)? = nil
    
    @State private var hasActivated = false // ensure callback runs only once on appear
    
    var body: some View {
        ZStack(alignment: .center) {
            // Detect user tap anywhere in the view
            Color.clear
                .contentShape(Rectangle()) // make entire area tappable
                .onTapGesture {
                    onActivate?()
                }
            
            // Measuring text (hidden)
            Text(text.isEmpty ? " " : text)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { geometry in
                        Color.clear
                            .onAppear { calculateHeight(geometry.size.height) }
                            .onChange(of: text) { _ in calculateHeight(geometry.size.height) }
                    }
                )
                .opacity(0)
            
            // Actual TextEditor
            VStack(alignment: .center) {
                Spacer()
                    .frame(maxHeight: min(height * 0.9, 0))
                
                if #available(iOS 16.0, *) {
                    TextEditor(text: $text)
                        .frame(height: height)
                        .multilineTextAlignment(.center)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                } else {
                    // Fallback on earlier versions
                }
                
                Spacer()
                    .frame(maxHeight: min(height * 0.9, 0))
            }
        }
        .onAppear {
            // Trigger callback once when view appears
            if !hasActivated {
                onActivate?()
                hasActivated = true
            }
        }
    }
    
    private func calculateHeight(_ textHeight: CGFloat) {
        let minHeight: CGFloat = 200
        let maxHeight: CGFloat = UIScreen.main.bounds.height - 100
        let newHeight = max(minHeight, min(textHeight + 40, maxHeight))
        
        withAnimation(.interactiveSpring(response: 0.3, dampingFraction: 0.7)) {
            height = newHeight
        }
    }
}
