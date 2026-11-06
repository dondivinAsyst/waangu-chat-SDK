//
//  AlbumItem.swift
//  Pods
//
//  Created by Asyst on 8/11/25.
//
import SwiftUI
import WaanguCoreKit
 

struct AlbumMenuItem: View {
    let title: String
    let count: Int
    let image: UIImage?
    let translationService: (any TranslationServiceProtocol)?
    
    init(title: String, count: Int, image: UIImage?, translationService: (any TranslationServiceProtocol)? = nil) {
        self.title = title
        self.count = count
        self.image = image
        self.translationService = translationService
    }
    
    var body: some View {
        HStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 30, height: 30)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Image(systemName: "photo.fill.on.rectangle.fill")
                    .frame(width: 30, height: 30)
            }
            
            VStack(alignment: .leading) {
                Text(title)
                Text(t(ChatTranslationKeys.GALLERY_PHOTOS_COUNT, args: ["\(count)", count > 1 ? "s" : ""]))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
