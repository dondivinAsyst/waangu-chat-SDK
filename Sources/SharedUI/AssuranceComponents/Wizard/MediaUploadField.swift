//
//  MediaUploadField.swift
//  AppModules
//
//  Created by Antigravity on 4/13/26.
//

import SwiftUI
import WaanguSharedUI

struct MediaUploadField: View {
    let label: String
    let maxCount: Int
    let errorMessage: String?
    @Binding var paths: [String]
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(.appSubheadline)
                .foregroundStyle(Color.appText)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppSpacing.md) {
                    // Add Button
                    if paths.count < maxCount {
                        addButton
                    }
                    
                    // Pictures
                    ForEach(paths, id: \.self) { path in
                        pictureCard(path)
                    }
                }
                .padding(.vertical, AppSpacing.xs)
            }
            
            if let errorMessage {
                Text(errorMessage)
                    .font(.appInputError)
                    .foregroundStyle(Color.appError)
            }
        }
    }
    
    private var addButton: some View {
        Button {
            // Simulation of adding a photo
            let id = UUID().uuidString.prefix(6)
            paths.append("photo_\(id).jpg")
        } label: {
            VStack(spacing: 4) {
                Image(systemName: "camera.fill")
                    .font(.title3)
                Text("Ajouter")
                    .font(.appCaption2)
            }
            .foregroundStyle(Color.brandPrimary)
            .frame(width: 80, height: 80)
            .background(Color.brandPrimary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppCornerRadius.md)
                    .stroke(Color.brandPrimary.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [4]))
            )
        }
    }
    
    private func pictureCard(_ path: String) -> some View {
        ZStack(alignment: .topTrailing) {
            VStack {
                Image(systemName: "doc.text.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Color.appSecondaryText)
                Text(path)
                    .font(.system(size: 8))
                    .lineLimit(1)
            }
            .frame(width: 80, height: 80)
            .background(Color.appSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.md))
            
            Button {
                paths.removeAll { $0 == path }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .background(Circle().fill(.white))
            }
            .offset(x: 8, y: -8)
        }
    }
}
