//
//  CircularProfileImageView.swift
//  AppModules
//
//  Created by Don divin on 5/6/26.
//


//
//  CircularProfileImageView.swift
//  AppModules
//
//  Created by Don divin on 5/5/26.
//


import SwiftUI
import SDWebImageSwiftUI
import WaanguSharedUI

public struct CircularProfileImageView: View {
    public  let profileImageUrl: String?
    public  let size: Size
    public  let fallbackImage: FallbackImage
    public  var onClick: (() -> Void)?
    /// When set and there is no photo, the placeholder shows this name's initials
    /// on the app blue instead of a grey silhouette.
    public  let name: String?
    
    // Timeout configuration
    private let loadingTimeout: TimeInterval = 10.0 // 10 seconds timeout
    @State private var hasTimedOut = false
    @State private var isLoading = true
    
    public init(_ profileImageUrl: String? = nil, size: Size, name: String? = nil, onClick: (() -> Void)? = nil) {
        self.profileImageUrl = profileImageUrl
        self.size = size
        self.fallbackImage = .singleUserIcon
        self.name = name
        self.onClick = onClick
    }
   
    
    public  var body: some View{
        // An empty string is "no photo": `URL(string: "")` is not nil on recent
        // iOS, and loading it ended on the grey silhouette instead of initials.
        if let urlString = profileImageUrl, !urlString.isEmpty, let url = URL(string: urlString) {
            WebImage(url: url) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .onAppear {
                        isLoading = false
                    }
            } placeholder: {
                if hasTimedOut {
                    // Show placeholder if timeout occurred
                    placeholderImageView()
                } else {
                    // Show loading indicator
                    ProgressView()
                        .onAppear {
                            startTimeout()
                        }
                }
            }
            .onSuccess { _, _, _ in
                isLoading = false
                hasTimedOut = false
            }
            .onFailure { _ in
                hasTimedOut = true
                isLoading = false
            }
            .indicator(.activity)
            .transition(.opacity)
            .frame(width: size.dimension, height: size.dimension)
            .clipShape(Circle())
            .onTapGesture {
                onClick?()
            }
        } else {
            placeholderImageView()
                .onTapGesture {
                    onClick?()
                }
        }
    }
    
    private func startTimeout() {
        guard isLoading else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + loadingTimeout) {
            if isLoading {
                hasTimedOut = true
            }
        }
    }
    
    @ViewBuilder
    private func placeholderImageView() -> some View {
        if let initials = name.flatMap(ProfileEditView.initials(of:)) {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.centerGradientStart, AppColors.primary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay {
                    Text(initials)
                        .font(.system(size: size.dimension * 0.38, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                        .minimumScaleFactor(0.6)
                }
                .frame(width: size.dimension, height: size.dimension)
        } else {
            silhouette()
        }
    }

    private func silhouette() -> some View {
        Image(systemName: fallbackImage.rawValue)
            .resizable()
            .scaledToFill()
            .imageScale(.large)
            .foregroundColor(Color("placeholderImageColor", bundle: .module))
            .frame(width: size.dimension, height: size.dimension)
            .background(Color(.systemBackground))
            .clipShape(Circle())
    }
}

// MARK: - Size & FallbackImage Enums

public extension CircularProfileImageView {
       enum Size {
        case mini, xSmall, small, medium, large, xLarge
        case custom(CGFloat)
        
        var dimension: CGFloat {
            switch self {
            case .mini: return 30
            case .xSmall: return 40
            case .small: return 50
            case .medium: return 60
            case .large: return 80
            case .xLarge: return 120
            case .custom(let value): return value
            }
        }
    }
    
    enum FallbackImage: String {
        case singleUserIcon = "person.circle.fill"
        case multiUserIcon = "person.2.circle.fill"
        
        init(for membersCount: Int) {
            switch membersCount {
            case 2:
                self = .singleUserIcon
            default:
                self = .multiUserIcon
            }
        }
    }
}

// MARK: - Convenience Initializer

extension CircularProfileImageView {
    init(_ channel: ChannelItem, size: Size) {
        self.profileImageUrl = channel.coverImageUrl
        self.size = size
        self.fallbackImage = FallbackImage(for: channel.membersCount)
        self.name = nil
    }
}

