//
//  DeviceContactPickerView.swift
//  FeatureChat
//

import SwiftUI
import ContactsUI

/// System picker for choosing one of the user's device contacts.
///
/// Used by "Add to existing contact": the caller gets the chosen `CNContact`
/// back and decides what to attach to it.
struct DeviceContactPickerView: UIViewControllerRepresentable {
    let onSelect: (CNContact) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        private let parent: DeviceContactPickerView

        init(_ parent: DeviceContactPickerView) {
            self.parent = parent
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            parent.onSelect(contact)
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.onCancel()
        }
    }
}
