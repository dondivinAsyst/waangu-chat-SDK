////
////  TextInputToolbarArea.swift
////  chatpreview
////
////  Created by Asyst on 6/30/25.
////
//
//import SwiftUI
//
//struct TextInputToolbarArea: View {
//    
//    @State private var text: String = ""
//    @State private var isSheetVisible = false
//    
//    var body: some View {
//    
//            HStack(alignment: .bottom) {
//                
//            actionPicker()
//            messageTextField()
//                .animation(.spring(), value: text.isEmpty)
//                .transition(.scale.combined(with: .opacity))
//                    
//                    audioRecorderButton()
//            }.padding()
//            .background(Color.clear)
//            .padding(.bottom, 10)
//            .overlay(
//                Divider(), alignment: .top
//             )
//            
//     
//        
//    }
//    
//    private func messageTextField() -> some View {
//        if #available(iOS 16.0, *) {
//            TextField("", text: $text, axis: .vertical)
//                .padding(5)
//                .padding(.horizontal,10)
//                .background(
//                    RoundedRectangle(cornerRadius: 15, style: .continuous)
//                        .fill(.thinMaterial)
//                )
//                .overlay(textViewBorder())
//        } else {
//            TextField("", text: $text)
//                .padding(5)
//                .padding(.horizontal,10)
//                .background(
//                    RoundedRectangle(cornerRadius: 15, style: .continuous)
//                        .fill(.thinMaterial)
//                )
//                .overlay(textViewBorder())
//        }
//    }
//    
//    private func textViewBorder() -> some View {
//        RoundedRectangle(cornerRadius: 15, style: .continuous)
//            .stroke(Color(.systemGray5), lineWidth: 1)
//    }
//    
//    private func actionPicker() -> some View {
//        Button(action: {isSheetVisible = true }) {
//            Image(systemName: "plus")
//                .foregroundColor(Color.black)
//                .font(.system(size: 24))
//                .padding(5)
//        }
//        .sheet(isPresented: $isSheetVisible) {
//            if #available(iOS 16.0, *) {
//                let sheet = SheetActionView(onDismiss: {isSheetVisible = false})
//                  
//                   .presentationDetents(
//                    [.fraction(0.7), .medium, .large],
//                       selection: .constant(.fraction(0.7))
//                   ).environmentObject(SharedData.shared)
//                
//                
//                    sheet
//                 
//            } else {
//                SheetActionView(onDismiss: {
//                    isSheetVisible = false
//                }).environmentObject(SharedData.shared)
//            }
//        }
//        .onAppear{
//            let appearance = UINavigationBarAppearance()
//              appearance.configureWithTransparentBackground()
//              appearance.backgroundEffect = UIBlurEffect(style: .systemMaterialLight)
//              appearance.backgroundColor = .clear
//
//              let navBar = UINavigationBar.appearance()
//              navBar.standardAppearance = appearance
//              navBar.scrollEdgeAppearance = appearance
//              navBar.compactAppearance = appearance
//        }
//        
//    }
//    
//    @ViewBuilder
//        private func audioRecorderButton() -> some View {
//            if text.isEmpty {
//                Button(action: {
//                    print("Record audio")
//                }) {
//                    Image(systemName: "mic")
//                        .foregroundColor(.black)
//                        .font(.system(size: 24))
//                }
//                .transition(.scale(scale: 1.5).combined(with: .opacity))
//            } else {
//                Button(action: {
//                    print("Send message")
//                }) {
//                    Image(systemName: "arrow.up")
////                        .fontWeight(.heavy)
//                        .foregroundColor(.white)
//                        .padding(10)
//                        .background(Color.blue)
//                        .clipShape(Circle())
//                }
//                .transition(.scale(scale: 1.5).combined(with: .opacity))
//            }
//        }
// }
//
//
//
//struct BlurViewToolbar: UIViewRepresentable {
//    let style: UIBlurEffect.Style
//
//    init(style: UIBlurEffect.Style = .systemMaterial) {
//        self.style = style
//    }
//
//    func makeUIView(context: Context) -> UIVisualEffectView {
//        return UIVisualEffectView(effect: UIBlurEffect(style: style))
//    }
//
//    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
//        uiView.effect = UIBlurEffect(style: style)
//    }
//}
//
//
//#Preview {
//    TextInputToolbarArea()
//}
