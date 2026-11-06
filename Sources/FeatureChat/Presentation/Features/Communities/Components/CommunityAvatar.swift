//
//  CommunityAvatar.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import SDWebImageSwiftUI

/// A community's picture: a rounded square, not a circle.
///
/// The shape is what tells a community apart from a group or a person at a
/// glance — every other avatar in the app is round, so this one must not be.
@available(iOS 16.0, *)
struct CommunityAvatar: View {

    let imageUrl: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let imageUrl, let url = URL(string: imageUrl), !imageUrl.isEmpty {
                WebImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    placeholder
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }

    private var placeholder: some View {
        ZStack {
            AppColors.primary.opacity(0.12)
            Image(systemName: "person.3.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(AppColors.primary)
        }
    }
}
