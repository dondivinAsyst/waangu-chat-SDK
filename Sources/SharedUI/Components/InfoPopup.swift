// MARK: - SharedUI/Components/InfoPopup.swift

import SwiftUI

// MARK: - PopupAction

public struct PopupAction {
    public let title: String
    public let color: Color
    public let handler: () -> Void

    public init(title: String, color: Color, handler: @escaping () -> Void) {
        self.title = title
        self.color = color
        self.handler = handler
    }
}

// MARK: - InfoPopup

public struct InfoPopup: View {

    public let title: String
    public let message: String
    public let illustration: Image?
    public let headerColor: Color
    public let actions: [PopupAction]

    public init(
        title: String,
        message: String,
        illustration: Image? = nil,
        headerColor: Color,
        actions: [PopupAction]
    ) {
        self.title = title
        self.message = message
        self.illustration = illustration
        self.headerColor = headerColor
        self.actions = actions
    }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                headerColor
                    .frame(height: 110)

                VStack(spacing: 16) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.gray)

                    Text(message)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)

                    HStack {
                        Spacer()

                        ForEach(actions.indices, id: \.self) { index in
                            let action = actions[index]
                            Button(action.title) { action.handler() }
                                .foregroundColor(action.color)
                            if index != actions.count - 1 { Spacer() }
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(24)
            }
            .background(Color.white)
            .cornerRadius(14)
            .shadow(color: .black.opacity(0.2), radius: 12, y: 6)
            .padding(.horizontal, 40)

            if let illustration = illustration {
                illustration
                    .resizable()
                    .scaledToFit()
                    .frame(width: 70, height: 70)
                    .foregroundColor(Color.white)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
                    .padding(.top, 12)
            }
        }
        .padding(.top, 35)
    }
}
