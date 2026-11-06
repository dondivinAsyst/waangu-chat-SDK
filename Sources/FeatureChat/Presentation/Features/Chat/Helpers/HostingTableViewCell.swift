//
//  HostingTableViewCell.swift
//  Pods
//
//  Created by Asyst on 7/7/25.
//

import UIKit
import SwiftUI

final class TypedHostingCell<Content: View>: UITableViewCell {
    private var hostingController: UIHostingController<Content>?

    func setRootView(_ view: Content) {
        if let controller = hostingController {
            controller.rootView = view
            controller.view.invalidateIntrinsicContentSize()
        } else {
            let controller = UIHostingController(rootView: view)

            controller.view.backgroundColor = .clear // clear UIKit bg
            controller.view.isOpaque = false
            contentView.backgroundColor = .clear     // clear contentView
            backgroundColor = .clear                 // clear cell bg
            controller.view.translatesAutoresizingMaskIntoConstraints = false

            contentView.addSubview(controller.view)

            NSLayoutConstraint.activate([
                controller.view.topAnchor.constraint(equalTo: contentView.topAnchor),
                controller.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                controller.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                controller.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
            ])

            controller.view.setContentHuggingPriority(.required, for: .vertical)
            controller.view.setContentCompressionResistancePriority(.required, for: .vertical)

            hostingController = controller
        }
        
        self.selectionStyle = .none //Prevent UITableView default selection color
        self.backgroundColor = .clear // Optional: ensures no white background
        self.contentView.backgroundColor = .clear
    }
}

