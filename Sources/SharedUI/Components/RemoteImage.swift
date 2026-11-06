//
//  RemoteImage.swift
//  AppModules
//
//  Created by Asyst on 4/9/26.
//

//
//  RemoteImage.swift
//  AppModules
//
//  Created by Asyst on 4/9/26.
//
import SwiftUI
import SDWebImageSwiftUI

public struct RemoteImage<PlaceholderView: View, FallbackView: View>: View {

    private let url: URL?
    private let contentMode: ContentMode
    private let size: CGSize?
    private let placeholderContent: () -> PlaceholderView
    private let fallbackContent: () -> FallbackView

    @State private var loadFailed = false

    // MARK: - Init générique
    public init(
        url: URL?,
        contentMode: ContentMode = .fill,
        size: CGSize? = nil,
        @ViewBuilder placeholder: @escaping () -> PlaceholderView,
        @ViewBuilder fallback: @escaping () -> FallbackView
    ) {
        self.url = url
        self.contentMode = contentMode
        self.size = size
        self.placeholderContent = placeholder
        self.fallbackContent = fallback
    }

    public var body: some View {
        Group {
            if loadFailed || url == nil {
                fallbackContent()
            } else {
                WebImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } placeholder: {
                    placeholderContent()
                }
                .onFailure { _ in
                    loadFailed = true
                }
            }
        }
        .applyIfLet(size) { view, s in
            view.frame(width: s.width, height: s.height)
        }
        .onChange(of: url) { _ in
            loadFailed = false
        }
    }
}

// MARK: - View helper interne
private extension View {
    @ViewBuilder
    func applyIfLet<T>(_ value: T?, transform: (Self, T) -> some View) -> some View {
        if let value {
            transform(self, value)
        } else {
            self
        }
    }
}

// MARK: - Convenience inits
public extension RemoteImage {

    // Init avec URL
    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        size: CGSize? = nil
    ) where PlaceholderView == Color, FallbackView == Image {
        self.init(
            url: url,
            contentMode: contentMode,
            size: size,
            placeholder: { Color.gray.opacity(0.15) },
            fallback: { Image(systemName: "photo") }
        )
    }

    // Init avec String
    init(
        urlString: String?,
        contentMode: ContentMode = .fill,
        size: CGSize? = nil,
        @ViewBuilder placeholder: @escaping () -> PlaceholderView,
        @ViewBuilder fallback: @escaping () -> FallbackView
    ) {
        self.init(
            url: urlString.flatMap(URL.init),
            contentMode: contentMode,
            size: size,
            placeholder: placeholder,
            fallback: fallback
        )
    }
}
