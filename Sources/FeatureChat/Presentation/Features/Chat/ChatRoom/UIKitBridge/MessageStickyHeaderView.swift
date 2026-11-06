//
//  MessageStickyHeaderView.swift
//  Pods
//
//  Created by Asyst on 7/25/25.
//

import UIKit

final class MessageStickyHeaderView: UICollectionReusableView {
    static let reuseIdentifier = "MessageStickyHeaderView"
    
    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.9)
        view.layer.cornerRadius = 12
        view.layer.masksToBounds = true
        view.layer.borderWidth = 0.5
        view.layer.borderColor = UIColor.separator.cgColor
        return view
    }()
    
    private let label: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        return label
    }()
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupViews()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupViews() {
        // 1. Configuration essentielle pour le sticky header
        layer.zPosition = 0  // Garde le header au-dessus du contenu
        backgroundColor = .clear
        
        // 2. Ajout des sous-vues
        addSubview(containerView)
        containerView.addSubview(label)
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        
        // 3. Contraintes
        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: centerXAnchor),
            containerView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            containerView.heightAnchor.constraint(equalToConstant: 28),
            
            label.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: containerView.centerYAnchor)
        ])
    }
    
    func configure(with text: String) {
        label.text = text.uppercased()
    }
}
