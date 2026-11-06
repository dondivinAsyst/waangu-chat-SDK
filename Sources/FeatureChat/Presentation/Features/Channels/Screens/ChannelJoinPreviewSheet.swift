//
//  ChannelJoinPreviewSheet.swift
//  FeatureChat
//
//  Preview sheet shown when users open a channel invite link.
//  Shows channel details and allows them to join.
//

import SwiftUI

struct ChannelJoinPreviewSheet: View {
    
    @StateObject var viewModel: ChannelJoinViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoadingChannel {
                    loadingView()
                } else if let channel = viewModel.channel {
                    channelPreviewContent(channel)
                } else if viewModel.errorMessage != nil {
                    errorView()
                } else {
                    // Should not reach here - loading should be true initially
                    EmptyView()
                }
            }
            .navigationTitle("Channel Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadChannelPreview()
            }
        }
    }
    
    // MARK: - Loading View
    
    private func loadingView() -> some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading channel...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Channel Preview Content
    
    private func channelPreviewContent(_ channel: Channel) -> some View {
        ScrollView {
            VStack(spacing: 24) {
                // Channel Header
                VStack(spacing: 16) {
                    // Channel Avatar
                    ZStack {
                        if let imageUrl = channel.image, !imageUrl.isEmpty {
                            // Async image would go here
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "number")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                )
                        } else {
                            Circle()
                                .fill(Color.blue.opacity(0.2))
                                .frame(width: 100, height: 100)
                                .overlay(
                                    Image(systemName: "number")
                                        .font(.system(size: 40))
                                        .foregroundColor(.blue)
                                )
                        }
                        
                        // Verified badge removed - ChannelType doesn't have .verified case yet
                    }
                    
                    // Channel Name
                    HStack(spacing: 6) {
                        Text(channel.name)
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        // Verified badge removed - ChannelType doesn't have .verified case yet
                    }
                    
                    // Subscriber Count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption)
                        Text("\(formattedCount(channel.subscriberCount)) subscribers")
                            .font(.subheadline)
                    }
                    .foregroundColor(.secondary)
                }
                .padding(.top, 32)
                
                // Channel Description
                if let description = channel.description, !description.isEmpty {
                    Text(description)
                        .font(.body)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(Color(.systemBackground))
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                
                // Join Status or Join Button
                if viewModel.joinSuccessful {
                    successSection()
                } else {
                    joinSection(channel)
                }
                
                // Error Message
                if let errorMessage = viewModel.errorMessage {
                    errorSection(errorMessage)
                }
            }
            .padding(.bottom, 32)
        }
    }
    
    // MARK: - Join Section
    
    private func joinSection(_ channel: Channel) -> some View {
        VStack(spacing: 16) {
            // Info Box
            VStack(alignment: .leading, spacing: 12) {
                infoRow(
                    icon: "bell.fill",
                    title: "Get Notified",
                    description: "Receive updates when new posts are published"
                )
                
                infoRow(
                    icon: "eye.fill",
                    title: "View Content",
                    description: "Access all channel posts and media"
                )
                
                // hasAdmins property removed - Channel doesn't have this property yet
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            
            // Join Button
            Button {
                viewModel.joinChannel()
            } label: {
                HStack {
                    if viewModel.isJoining {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    }
                    Text(viewModel.joinButtonText)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(viewModel.canJoin ? Color.blue : Color.gray)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(!viewModel.canJoin)
            .padding(.horizontal)
        }
    }
    
    // MARK: - Success Section
    
    private func successSection() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)
            
            Text(viewModel.wasAlreadySubscribed ? "You're Already a Member" : "Welcome to the Channel!")
                .font(.title2)
                .fontWeight(.bold)
            
            Text(viewModel.wasAlreadySubscribed
                 ? "You were already subscribed to this channel."
                 : "You'll now receive updates and can view all content.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Error View
    
    private func errorView() -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text(ChatErrorStrings.channelLoadFailedTitle)
                .font(.title2)
                .fontWeight(.bold)
            
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Button {
                viewModel.loadChannelPreview()
            } label: {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Try Again")
                }
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - Error Section
    
    private func errorSection(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
        .padding(.horizontal)
    }
    
    // MARK: - Helper Views
    
    private func infoRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formattedCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000.0)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000.0)
        } else {
            return "\(count)"
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ChannelJoinPreviewSheet_Previews: PreviewProvider {
    static var previews: some View {
        // Mock preview - would need actual dependencies
        Text("Preview placeholder")
    }
}
#endif
