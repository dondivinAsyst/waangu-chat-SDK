//
//  MapBottomSheet.swift
//  Pods
//
//  Created by Asyst on 9/22/25.
//

import UIKit

class MapBottomSheet: UIView {

    private let stack = UIStackView()
    
    init(items: [UIView] = []) {
        super.init(frame: .zero)
        setupAppearance()
        setupStack(items: items)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupAppearance() {
        backgroundColor = .systemBackground
        overrideUserInterfaceStyle = ChatAppearanceStore.shared.defaultAppearance.userInterfaceStyle
        layer.cornerRadius = 16
        layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -5)
        
        stack.axis = .vertical
        stack.spacing = 12
        stack.alignment = .fill
        
        addSubview(stack)
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -80)
        ])
    }
    
    func updateItems(_ items: [UIView]) {
        stack.arrangedSubviews.forEach { subview in
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }
        
        for item in items {
            stack.addArrangedSubview(item)
        }
    }

    
    func prependItems(_ items: [UIView]) {
        for (index, item) in items.enumerated() {
            stack.insertArrangedSubview(item, at: index)
        }
    }

    func setupStack(items: [UIView]) {
        for item in items {
            stack.addArrangedSubview(item)
        }
    }
    
  
    func animateAppearance(from offsetY: CGFloat = 120, duration: TimeInterval = 0.3) {
        transform = CGAffineTransform(translationX: 0, y: offsetY)
        UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
            self.transform = .identity
        }
    }
}



