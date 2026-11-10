//
//  ChannelInviteLinkSheet.swift
//  FeatureChat
//
//  Sheet for channel owners to manage their channel invite link
//  (generate, view, share, revoke)
//

import SwiftUI
import WaanguSharedUI

struct ChannelInviteLinkSheet: View {
    
    @StateObject var viewModel: ChannelInviteLinkViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()
                
                if viewModel.isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if let link = viewModel.inviteLink, viewModel.hasActiveLink {
                                activeLinkSection(link)
                            } else if viewModel.inviteLink != nil {
                                inactiveLinkSection()
                            } else {
                                noLinkSection()
                            }
                            
                            if let errorMessage = viewModel.errorMessage {
                                errorSection(errorMessage)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Invite Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                viewModel.loadInviteLink()
            }
            .sheet(isPresented: $viewModel.showShareSheet) {
                if let link = viewModel.inviteLink {
                    ShareSheet(items: [link.inviteUrl])
                }
            }
            .confirmationDialog(
                "Revoke Invite Link?",
                isPresented: $viewModel.showRevokeConfirmation,
                titleVisibility: .visible
            ) {
                Button("Revoke Link", role: .destructive) {
                    viewModel.revokeInviteLink()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will immediately invalidate the current link. Anyone trying to use it will no longer be able to join the channel.")
            }
        }
    }
    
    // MARK: - Active Link Section
    
    private func activeLinkSection(_ link: ChannelInviteLink) -> some View {
        VStack(spacing: 16) {
            // Status Badge
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Active Link")
                    .font(.headline)
                    .foregroundColor(.green)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(Color.green.opacity(0.1))
            .cornerRadius(12)
            
            // Link URL Display
            VStack(alignment: .leading, spacing: 8) {
                Text("Invite Link")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Text(link.inviteUrl)
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2)
                        .truncationMode(.middle)
                    
                    Spacer()
                    
                    Button {
                        viewModel.copyInviteLinkToClipboard()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .foregroundColor(AppColors.primary)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            
            // Link Stats
            VStack(alignment: .leading, spacing: 12) {
                if let usageText = viewModel.linkUsageText {
                    statsRow(icon: "person.2.fill", text: usageText)
                }
                
                if let expirationText = viewModel.linkExpirationText {
                    statsRow(icon: "clock.fill", text: expirationText)
                }
                
                statsRow(
                    icon: "calendar",
                    text: "Created \(formattedDate(link.createdAt))"
                )
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            
            // Actions
            VStack(spacing: 12) {
                Button {
                    viewModel.shareInviteLink()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Share Link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(AppColors.primary)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                Button {
                    viewModel.regenerateInviteLink()
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Regenerate Link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
                }
                
                Button {
                    viewModel.confirmRevoke()
                } label: {
                    HStack {
                        Image(systemName: "xmark.circle")
                        Text("Revoke Link")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(.systemGray5))
                    .foregroundColor(.red)
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // MARK: - Inactive Link Section
    
    private func inactiveLinkSection() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.orange)
            
            Text("Link Inactive")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Your previous invite link is no longer active. Generate a new one to invite people to your channel.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button {
                viewModel.generateInviteLink()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Generate New Link")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primary)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 40)
    }
    
    // MARK: - No Link Section
    
    private func noLinkSection() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "link.badge.plus")
                .font(.system(size: 60))
                .foregroundColor(AppColors.primary)
            
            Text("No Invite Link")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create a shareable invite link to let people join your channel from outside the app.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "link", text: "Shareable link")
                featureRow(icon: "square.and.arrow.up", text: "Share via WhatsApp, SMS, etc.")
                featureRow(icon: "person.badge.plus", text: "Easy channel discovery")
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            
            Button {
                viewModel.generateInviteLink()
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                    Text("Generate Invite Link")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(AppColors.primary)
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
    }
    
    // MARK: - Helper Views
    
    private func statsRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppColors.primary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
            Spacer()
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(AppColors.primary)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
