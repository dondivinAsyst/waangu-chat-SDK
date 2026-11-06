//
//  RemoteImageView.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  RemoteImageView.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  RemoteImageView.swift
//  Pods
//
//  Created by Asyst on 6/13/25.
//
import SwiftUI
import SDWebImageSwiftUI
import Foundation

public struct RemoteImageView: View {
    let urlString: String
    let fallBack: String
    var size: CGFloat = 48
    public init(urlString: String, fallBack: String, size: CGFloat = 48) {
        self.urlString = urlString
        self.fallBack = fallBack
        self.size = size
    }
   public var body: some View {
        if let url = URL(string: urlString) {
            WebImage(url: url)
                .resizable()
                .overlay {
                    AsyncImage(url: URL(string: fallBack)) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } else {
                            Color.gray
                        }
                    }
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                }
                .transition(.fade(duration: 0.3))
                .aspectRatio(contentMode: .fill)
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            CircularProfileImageView(nil, size: .xSmall)
                .frame(width: size, height: size)
        }
    }
}

