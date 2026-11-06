//
//  PlaceRowKit.swift
//  Pods
//
//  Created by Asyst on 9/22/25.
//

import UIKit
import SwiftUI

final class PlaceRowKit: UIView {

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let locationLabel = UILabel()
    private let stack = UIStackView()
    private let textStack = UIStackView()
    private let separator = UIView()
    
    var onTap: (() -> Void)? // callback pour le clic

    init(icon: String, name: String, location: String, color: UIColor = .systemOrange, isBordered: Bool = true) {
        super.init(frame: .zero)
        setupUI(icon: icon, name: name, location: location, color:color, isBordered: isBordered)
        setupGesture()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func setupUI(icon: String, name: String, location: String, color: UIColor, isBordered: Bool = true) {
        backgroundColor = .systemBackground // support Dark Mode automatiquement

        // ---- Icon ----
        iconView.image = UIImage(systemName: icon)
        iconView.tintColor = .white
        iconView.backgroundColor = color
        iconView.contentMode = .center
        iconView.layer.masksToBounds = true
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 34),
            iconView.heightAnchor.constraint(equalToConstant: 34)
        ])
        iconView.layer.cornerRadius = 34/2


        // ---- Labels ----
        nameLabel.text = name
        nameLabel.font = .systemFont(ofSize: 16)
        nameLabel.textColor = .label
        nameLabel.numberOfLines = 1

        locationLabel.text = location
        locationLabel.font = .systemFont(ofSize: 14)
        locationLabel.textColor = .secondaryLabel
        locationLabel.numberOfLines = 1
        locationLabel.isHidden = location.isEmpty

        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.addArrangedSubview(nameLabel)
        if !location.isEmpty {
            textStack.addArrangedSubview(locationLabel)
        }

        // ---- HStack ----
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconView)
        stack.addArrangedSubview(textStack)

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16)
        ])

        // ---- Separator ----
        
        if isBordered {
            separator.backgroundColor = UIColor.separator
            separator.translatesAutoresizingMaskIntoConstraints = false
            addSubview(separator)
            NSLayoutConstraint.activate([
                separator.topAnchor.constraint(equalTo: stack.bottomAnchor, constant: 8),
                separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
                separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
                separator.heightAnchor.constraint(equalToConstant: 0.3),
                separator.bottomAnchor.constraint(equalTo: bottomAnchor) // définit la hauteur totale de la row
            ])
        }
     
    }

    private func setupGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(didTap))
        addGestureRecognizer(tap)
        isUserInteractionEnabled = true
    }

    @objc private func didTap() {
        onTap?()
    }
}


final class PlaceRowSkeletonView: UIView {
    
    // MARK: - UI Elements (même structure que précédemment)
    private let iconSkeleton = UIView()
    private let nameSkeleton = UIView()
    private let locationSkeleton = UIView()
    private let stack = UIStackView()
    private let textStack = UIStackView()
    private let separator = UIView()
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupSkeletonUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// MARK: - Private Methods
private extension PlaceRowSkeletonView {
    
    func setupSkeletonUI() {
        backgroundColor = .systemBackground
        
        // Icon Skeleton
        iconSkeleton.backgroundColor = .systemGray5
        iconSkeleton.layer.cornerRadius = 17
        iconSkeleton.translatesAutoresizingMaskIntoConstraints = false
        
        // Name Skeleton
        nameSkeleton.backgroundColor = .systemGray5
        nameSkeleton.layer.cornerRadius = 6
        nameSkeleton.translatesAutoresizingMaskIntoConstraints = false
        
        // Location Skeleton
        locationSkeleton.backgroundColor = .systemGray5
        locationSkeleton.layer.cornerRadius = 4
        locationSkeleton.translatesAutoresizingMaskIntoConstraints = false
        
        // Constraints
        NSLayoutConstraint.activate([
            iconSkeleton.widthAnchor.constraint(equalToConstant: 34),
            iconSkeleton.heightAnchor.constraint(equalToConstant: 34),
            nameSkeleton.heightAnchor.constraint(equalToConstant: 15),
            locationSkeleton.heightAnchor.constraint(equalToConstant: 12),
            nameSkeleton.widthAnchor.constraint(equalToConstant: 200),
            locationSkeleton.widthAnchor.constraint(equalToConstant: 300)
        ])
        
        // Stacks
        textStack.axis = .vertical
        textStack.spacing = 4
        textStack.alignment = .leading
        textStack.addArrangedSubview(nameSkeleton)
        textStack.addArrangedSubview(locationSkeleton)
        
        stack.axis = .horizontal
        stack.spacing = 12
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(iconSkeleton)
        stack.addArrangedSubview(textStack)
        
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])
        
        separator.backgroundColor = .systemGray4
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 0.5)
        ])
    }
    
    func createPulseAnimation() -> CABasicAnimation {
        let animation = CABasicAnimation(keyPath: "backgroundColor")
        animation.fromValue = UIColor.systemGray5.cgColor
        animation.toValue = UIColor.systemGray4.cgColor
        animation.duration = 1.0
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        return animation
    }
}

// MARK: - Public Methods
extension PlaceRowSkeletonView {
    
    func startAnimating() {
        let elements = [iconSkeleton, nameSkeleton, locationSkeleton]
        
        for (index, element) in elements.enumerated() {
            // Délai progressif pour un effet de vague
            let delay = Double(index) * 0.2
            
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                let animation = self.createPulseAnimation()
                element.layer.add(animation, forKey: "pulseAnimation")
            }
        }
    }
    
    func stopAnimating() {
        let elements = [iconSkeleton, nameSkeleton, locationSkeleton]
        elements.forEach { element in
            element.layer.removeAllAnimations()
            element.backgroundColor = .systemGray5
        }
    }
}

