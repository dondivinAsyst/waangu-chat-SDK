//
//  PaymentSheetContent.swift
//  Pods
//
//  Created by Asyst on 6/25/25.
//

import SwiftUI
import WaanguCoreKit

struct PaymentSheetContent: View {
    @State private var amount: Int = 10
    @State private var textAmount: String = ""
    @FocusState private var isTextFieldFocused: Bool
    let translationService: (any TranslationServiceProtocol)? = nil

    var body: some View {
        VStack(spacing: 20) {
            Spacer().frame(height: 60)

            HStack(spacing: 40) {
                Button(action: {
                    if amount > 1 { amount -= 1 }
                }) {
                    Image(systemName: "minus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color(.systemGray4))
                        .clipShape(Circle())
                }

                Text("$\(amount)")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundColor(.white)

                Button(action: {
                    amount += 1
                }) {
                    Image(systemName: "plus")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color(.systemGray4))
                        .clipShape(Circle())
                }
            }

            // Tap here to show keyboard
            Text(t(ChatTranslationKeys.PAYMENT_SHOW_KEYPAD))
                .foregroundColor(.gray)
                .font(.system(size: 16))
                .onTapGesture {
                    isTextFieldFocused = true
                }

            // Hidden textfield to trigger the keyboard
            TextField("", text: $textAmount)
                .keyboardType(.numberPad)
                .focused($isTextFieldFocused)
                .frame(width: 0, height: 0)
                .opacity(0)

            HStack(spacing: 20) {
                Button(action: {
                    // Handle request
                }) {
                    Text(t(ChatTranslationKeys.PAYMENT_REQUEST))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: {
                    // Handle send
                }) {
                    Text(common("send"))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray4))
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding()
        .background(Color.black)
        .cornerRadius(20)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
