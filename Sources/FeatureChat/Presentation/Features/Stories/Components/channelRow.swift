import SwiftUI
import WaanguSharedUI

struct ChannelRow: View {
    let logo: String
    let name: String
    let message: String
    let time: String
    let unreadCount: Int
    
    var body: some View {
        HStack(spacing: 12) {
            // Channel Logo
            AsyncImage(url: URL(string: logo) ){phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
//                        .overlay(Circle().stroke(Color.green, lineWidth: 2))
                } else if phase.error != nil {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 60, height: 60)
                        .overlay(
                            Text(String(name.prefix(2)))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(AppColors.primary)
                        )
                } else {
//                    ProgressView()
//                        .frame(width: 50, height: 50)
                    AnimatedSpinner(StrokeColor: .white,lineWidth: 2,size: 60)
                }
            }
          
            
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(Color.primary)
                
                HStack(spacing: 4) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 12))
                        .foregroundColor(AppColors.background.opacity(0.3))
                    
                    Text(message)
                        .font(.system(size: 15))
                        .foregroundColor(AppColors.background.opacity(0.3))
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 6) {
                Text(time)
                    .font(.system(size: 14))
                    .foregroundColor(AppColors.primary)
                
                if unreadCount > 0 {
                    Text("\(unreadCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppColors.primary)
                        .frame(width: 24, height: 24)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
