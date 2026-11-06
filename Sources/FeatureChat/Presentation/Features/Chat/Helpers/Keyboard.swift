////
////  Keyboardy.swift
////  WhatsAppClone
////
////  Created by Asyst on 7/17/25.
////
//
//import Foundation
//import SwiftUI
//import Combine
//
//final class KeyboardResponder: ObservableObject {
//    @Published var currentHeight: CGFloat = 0
//    private var cancellableSet: Set<AnyCancellable> = []
//
//    init() {
//        let keyboardWillShow = NotificationCenter.default
//            .publisher(for: UIResponder.keyboardWillShowNotification)
//            .compactMap { $0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect }
//            .map { $0.height }
//
//        let keyboardWillHide = NotificationCenter.default
//            .publisher(for: UIResponder.keyboardWillHideNotification)
//            .map { _ in CGFloat(0) }
//
//        Publishers.Merge(keyboardWillShow, keyboardWillHide)
//            .receive(on: RunLoop.main)
//            .assign(to: \.currentHeight, on: self)
//            .store(in: &cancellableSet)
//    }
//}
//
// var safeAreaInsets: UIEdgeInsets {
//    guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
//          let window = windowScene.windows.first else {
//        return .zero
//    }
//    return window.safeAreaInsets
//}
