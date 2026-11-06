////
////  MessageCell.swift
////  Pods
////
////  Created by Asyst on 8/22/25.
////
//
//
//import UIKit
//import SwiftUI
//
//final class MessageCell: UICollectionViewCell {
//    
//    private var hostingController: UIHostingController<BubbleView>?
//    private let checkboxButton = UIButton(type: .custom)
//    private var bubbleLeadingConstraint: NSLayoutConstraint!
//    private var bubbleTrailingConstraint: NSLayoutConstraint!
//    private let bubbleContainer = UIView()
//   
//    private var willApplyOffset = true
//    
//    var isSelectionMode: Bool = false {
//        didSet { updateSelectionMode(animated: true) }
//    }
//    
//    var isMessageSelected: Bool = false {
//        didSet { updateCheckboxState() }
//    }
//    
//    var onSelectMessage: ((Bool) -> Void)?
//    
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        backgroundColor = .clear
//        contentView.backgroundColor = .clear
//        setupCheckbox()
//    }
//    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    
//    // MARK: - Checkbox setup
//    
//    private func setupCheckbox() {
//        checkboxButton.translatesAutoresizingMaskIntoConstraints = false
//        checkboxButton.backgroundColor = .clear
//        checkboxButton.alpha = 0
//        checkboxButton.addTarget(self, action: #selector(didTapCheckbox), for: .touchUpInside)
//
//        let symbolConfig = UIImage.SymbolConfiguration(pointSize: 24, weight: .regular)
//        let normalImage = UIImage(systemName: "circle", withConfiguration: symbolConfig)?.withRenderingMode(.alwaysTemplate)
//        let selectedImage = UIImage(systemName: "checkmark.circle.fill", withConfiguration: symbolConfig)?.withRenderingMode(.alwaysTemplate)
//
//        checkboxButton.setImage(normalImage, for: .normal)
//        checkboxButton.setImage(selectedImage, for: .selected)
//        checkboxButton.tintColor = .systemGray2
//
//        contentView.addSubview(checkboxButton)
//
//        let verticalOffset: CGFloat = -8
//
//        NSLayoutConstraint.activate([
//            checkboxButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
//            checkboxButton.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: verticalOffset),
//            checkboxButton.widthAnchor.constraint(equalToConstant: 24),
//            checkboxButton.heightAnchor.constraint(equalToConstant: 24)
//        ])
//
//        checkboxButton.imageView?.contentMode = .scaleAspectFit
//    }
//
//    @objc private func didTapCheckbox() {
//        checkboxButton.isSelected.toggle()
//        checkboxButton.tintColor = checkboxButton.isSelected ? .systemGreen : .systemGray2
//        onSelectMessage?(checkboxButton.isSelected)
//    }
//    
//    private func updateCheckboxState() {
//        checkboxButton.isSelected = isMessageSelected
//        checkboxButton.tintColor = isMessageSelected ? .systemGreen : .systemGray2
//    }
//    
//    func setCheckboxSelected(_ selected: Bool) {
//        checkboxButton.isSelected = selected
//        checkboxButton.tintColor = selected ? .systemGreen : .systemGray2
//    }
//    
//    private func updateSelectionMode(animated: Bool) {
//        let show = isSelectionMode
//        let alpha: CGFloat = show ? 1 : 0
//        
//
//        let shift: CGFloat = show ?  40 : 0
//        
//        if animated {
//            UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut]) {
//                self.checkboxButton.alpha = alpha
//               
//                if self.willApplyOffset {
//                    self.hostingController?.view.transform = CGAffineTransform(translationX: shift , y: 0)
//                    self.contentView.layoutIfNeeded()
//                  
//                }else{
//                    self.bubbleLeadingConstraint.constant = shift
//                }
//                
//            }
//        } else {
//            checkboxButton.alpha = alpha
//            hostingController?.view.transform = CGAffineTransform(translationX: shift, y: 0)
//            contentView.layoutIfNeeded()
//        }
//    }
//
//
//
//    
//    // MARK: - Configure
//    
//    func configure(
//        with message: MessageDataItem,
//        channel: ChannelItem,
//        showSenderName: Bool,
//        uploadVM: UploadViewModel,
//        chatVM: ChatRoomViewModel,
//        imageTransitionNamespace: Namespace.ID
//    ) {
//        let bubbleView = BubbleView(
//            imageTransitionNamespace: imageTransitionNamespace,
//            message: message,
//            channel: channel,
//            showSenderName: showSenderName,
//            uploadVM: uploadVM,
//            chatVM: chatVM
//        )
//        
//        self.willApplyOffset = !message.isSentByMe
//        
//        if let hostingController = hostingController {
//            hostingController.rootView = bubbleView
//        } else {
//            let hc = UIHostingController(rootView: bubbleView)
//            hc.view.backgroundColor = .clear
//            hc.view.translatesAutoresizingMaskIntoConstraints = false
//            contentView.addSubview(hc.view)
//            
//            // Créer les contraintes avec une priorité haute pour la largeur
//            bubbleLeadingConstraint = hc.view.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
//            bubbleTrailingConstraint = hc.view.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)
//            
//            NSLayoutConstraint.activate([
//                hc.view.topAnchor.constraint(equalTo: contentView.topAnchor),
//                hc.view.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
//                bubbleLeadingConstraint,
//                bubbleTrailingConstraint
//            ])
//            
//            // Important: S'assurer que la vue garde sa taille intrinsèque
//            hc.view.setContentCompressionResistancePriority(.required, for: .horizontal)
//            hc.view.setContentHuggingPriority(.required, for: .horizontal)
//            
//            hostingController = hc
//        }
//        
//        hostingController?.view.invalidateIntrinsicContentSize()
//        setNeedsLayout()
//        layoutIfNeeded()
//    }
//    override func prepareForReuse() {
//        super.prepareForReuse()
//        isMessageSelected = false
//        isSelectionMode = false
//        hostingController?.view.transform = .identity
//        bubbleLeadingConstraint.constant = 0
//    }
//
//    
//    override func layoutSubviews() {
//        super.layoutSubviews()
//        hostingController?.view.setNeedsLayout()
//        hostingController?.view.layoutIfNeeded()
//    }
//}
