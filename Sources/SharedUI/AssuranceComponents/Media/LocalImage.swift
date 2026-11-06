import SwiftUI

struct LocalImage: View {
    let name: String
    var contentMode: ContentMode = .fill
    var width: CGFloat? = nil
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 0
    var fallbackSystemName: String = AppIcons.photoFill

    var body: some View {
        if let uiImage = UIImage(named: name) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            fallbackView
        }
    }

    private var fallbackView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(Color(.systemGray5))
            Image(systemName: fallbackSystemName)
                .font(.system(size: min(width ?? 24, height ?? 24) * 0.4))
                .foregroundStyle(.secondary)
        }
        .frame(width: width, height: height)
    }
}

#Preview("LocalImage") {
    VStack(spacing: 16) {
        LocalImage(name: "obr", width: 200, height: 150, cornerRadius: 12)
        LocalImage(name: "nonexistent_asset", width: 120, height: 120, cornerRadius: 60)
    }
    .padding()
}
