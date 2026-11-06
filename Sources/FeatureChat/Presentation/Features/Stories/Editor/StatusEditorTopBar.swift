import SwiftUI
import WaanguCoreKit

// MARK: - StatusEditorTopBar.swift
struct StatusEditorTopBar: View {
    let dismiss: DismissAction?
    var onSend: () -> Void
    var openColorSelector:Bool = false
    var openTextStyleSelector : Bool = false
    @Binding var text: String
    let translationService: (any TranslationServiceProtocol)?
    
    // 👇 external functions (callbacks) you can pass in
    var onTextTapped: () -> Void
    var onAppearTab : () -> Void
    var onPaletteTapped: () -> Void
    
    init(
        dismiss: DismissAction?,
        onSend: @escaping () -> Void,
        openColorSelector: Bool = false,
        openTextStyleSelector: Bool = false,
        translationService: (any TranslationServiceProtocol)? = nil,
        text: Binding<String>,
        onTextTapped: @escaping () -> Void,
        onAppearTab: @escaping () -> Void,
        onPaletteTapped: @escaping () -> Void
    ) {
        self.dismiss = dismiss
        self.onSend = onSend
        self.openColorSelector = openColorSelector
        self.openTextStyleSelector = openTextStyleSelector
        self.translationService = translationService
        self._text = text
        self.onTextTapped = onTextTapped
        self.onAppearTab = onAppearTab
        self.onPaletteTapped = onPaletteTapped
    }
   
    
    var body: some View {
        HStack {
            // Done button
            Button(action: {    if openColorSelector {
                onPaletteTapped()
            } else if openTextStyleSelector {
                onTextTapped()
            } else {
                if text.isEmpty {
                    dismiss?()
                }else{
                    onSend()
//                    dismiss?()
                    onAppearTab()
                }
              
            } }) {
                if text.isEmpty {
                    Image(systemName: "xmark")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 17)
                        .foregroundColor(.white)
                        .padding()
                    
                            
                }else{
                    Text(t(ChatTranslationKeys.STORIES_DONE))
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(openColorSelector ? Color.black :openTextStyleSelector ? Color.black : Color.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                               Capsule()
                                .fill(openColorSelector ? Color.white :openTextStyleSelector ? Color.white:  Color.white.opacity(0.3))
                        )

                }
            }
            
            Spacer()
            if !openTextStyleSelector {
                
                // "T" Button
                Button(action: { onTextTapped() }) {
                    Circle()
                        .fill(Color(red: 0.6, green: 0.3, blue: 0.3))
                        .frame(width: 44, height: 44)
                        .overlay(
                            Text("T")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.white)
                        )
                }
            }
            if !openColorSelector{
                
                // Palette Button
                       Button(action: { onPaletteTapped() }) {
                           Circle()
                               .fill(Color(red: 0.6, green: 0.3, blue: 0.3))
                               .frame(width: 44, height: 44)
                               .overlay(
                                   Image(systemName: "paintpalette")
                                       .resizable()
                                       .scaledToFit()
                                       .frame(width: 24, height: 24)
                                       .foregroundColor(.white)
                               )
                       }
            }
       
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .ignoresSafeArea(.keyboard)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}


