//
//  DateField.swift
//  Assurance
//
//  Created by Don divin on 3/27/26.
//
import SwiftUI

struct DateField: View {
    let label: String
    var errorMessage: String? = nil
    @Binding var date: Date
    @Binding var isSet: Bool

    private var hasError: Bool { errorMessage != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            Text(label)
                .font(.appInputLabel)
                .foregroundStyle(hasError ? Color.appError : Color.brandPrimary)
                .padding(.leading, 10)

            DatePicker(
                "",
                selection: Binding(
                    get: { date },
                    set: { newValue in
                        date = newValue
                        isSet = true
                    }
                ),
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .padding(.horizontal, AppSpacing.sm)
            .frame(height: 48)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: AppCornerRadius.md)
                    .stroke(hasError ? Color.appError : Color.appBorder, lineWidth: hasError ? 1.5 : 1)
            )

            if let errorMessage {
                Text(errorMessage)
                    .font(.appInputError)
                    .foregroundStyle(Color.appError)
            }
        }
    }
}
