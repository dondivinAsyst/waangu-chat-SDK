//import UIKit
//
//
//// MARK: -  Reply View
//class ReplyView: UIView {
//    
//    // MARK: - UI Components
//    private let containerView: UIView = {
//        let view = UIView()
////        view.layer.cornerRadius = 12
//        view.clipsToBounds = true
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let blurEffectView: UIVisualEffectView = {
//        let blurEffect = UIBlurEffect(style: .systemMaterial)
//        let view = UIVisualEffectView(effect: blurEffect)
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let leftAccentBar: UIView = {
//        let view = UIView()
//        view.backgroundColor = UIColor(red: 0.0, green: 0.73, blue: 0.53, alpha: 1.0)
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let senderLabel: UILabel = {
//        let label = UILabel()
//        label.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
//        label.textColor = UIColor(red: 0.0, green: 0.73, blue: 0.53, alpha: 1.0)
//        label.translatesAutoresizingMaskIntoConstraints = false
//        return label
//    }()
//    
//    private let messageContentLabel: UILabel = {
//        let label = UILabel()
//        label.font = UIFont.systemFont(ofSize: 14)
//        label.textColor = .darkGray
//        label.numberOfLines = 4
//        label.translatesAutoresizingMaskIntoConstraints = false
//        return label
//    }()
//    
//    private let thumbnailImageView: UIImageView = {
//        let imageView = UIImageView()
//        imageView.contentMode = .scaleAspectFill
//        imageView.clipsToBounds = true
//        imageView.layer.cornerRadius = 4
//        imageView.translatesAutoresizingMaskIntoConstraints = false
//        return imageView
//    }()
//    
//    private let closeButton: UIButton = {
//        let button = UIButton(type: .system)
//        button.setImage(UIImage(systemName: "xmark"), for: .normal)
//        button.tintColor = .gray
//        button.translatesAutoresizingMaskIntoConstraints = false
//        return button
//    }()
//    
//    private let iconImageView: UIImageView = {
//        let imageView = UIImageView()
//        imageView.contentMode = .scaleAspectFit
//        imageView.tintColor = .gray
//        imageView.translatesAutoresizingMaskIntoConstraints = false
//        return imageView
//    }()
//    
//    // MARK: - Properties
//    var onClose: (() -> Void)?
//    private var thumbnailWidthConstraint: NSLayoutConstraint?
//    
//    // MARK: - Initialization
//    override init(frame: CGRect) {
//        super.init(frame: frame)
//        setupUI()
//    }
//    
//    required init?(coder: NSCoder) {
//        super.init(coder: coder)
//        setupUI()
//    }
//    
//    // MARK: - Setup UI
//    private func setupUI() {
//        backgroundColor = .clear
//        
//        addSubview(containerView)
//        
//        // Apply iOS version-based background
//        setupBackgroundForIOSVersion()
//        
//        // Add content to either blur effect's contentView or containerView directly
//        let contentContainer: UIView
//        if #available(iOS 15.0, *) {
//            contentContainer = blurEffectView.contentView
//        } else {
//            contentContainer = containerView
//        }
//        
//        contentContainer.addSubview(leftAccentBar)
//        contentContainer.addSubview(senderLabel)
//        contentContainer.addSubview(messageContentLabel)
//        contentContainer.addSubview(thumbnailImageView)
//        contentContainer.addSubview(iconImageView)
//        contentContainer.addSubview(closeButton)
//        
//        setupConstraints()
//        
//        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
//    }
//    
//    private func setupBackgroundForIOSVersion() {
//        if #available(iOS 15.0, *) {
//            // iOS 15+: Glass/frosted glass effect
//            containerView.addSubview(blurEffectView)
//            
//            NSLayoutConstraint.activate([
//                blurEffectView.topAnchor.constraint(equalTo: containerView.topAnchor),
//                blurEffectView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
//                blurEffectView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
//                blurEffectView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
//            ])
//            
//            // Add subtle border for glass effect
//            containerView.layer.borderWidth = 0.5
//            containerView.layer.borderColor = UIColor.white.withAlphaComponent(0.2).cgColor
//        } else {
//            // iOS 14 and below: Solid background
//            containerView.backgroundColor = UIColor(red: 0.95, green: 0.95, blue: 0.97, alpha: 1.0)
//        }
//    }
//    
//    private func setupConstraints() {
//        thumbnailWidthConstraint = thumbnailImageView.widthAnchor.constraint(equalToConstant: 0)
//        
//        // Get the correct parent view based on iOS version
//        let parentView: UIView
//        if #available(iOS 15.0, *) {
//            parentView = blurEffectView.contentView
//        } else {
//            parentView = containerView
//        }
//        
//        NSLayoutConstraint.activate([
//            // Container
//            containerView.topAnchor.constraint(equalTo: topAnchor),
//            containerView.bottomAnchor.constraint(equalTo: bottomAnchor),
//            containerView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 0),
//            containerView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: 0),
//            containerView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
//            
//            // Left accent bar
//            leftAccentBar.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
//            leftAccentBar.topAnchor.constraint(equalTo: parentView.topAnchor, constant: 0),
//            leftAccentBar.bottomAnchor.constraint(equalTo: parentView.bottomAnchor, constant: 0),
//            leftAccentBar.widthAnchor.constraint(equalToConstant: 6),
//            
//            // Sender label
//            senderLabel.leadingAnchor.constraint(equalTo: leftAccentBar.trailingAnchor, constant: 12),
//            senderLabel.topAnchor.constraint(equalTo: parentView.topAnchor, constant: 8),
//            senderLabel.trailingAnchor.constraint(lessThanOrEqualTo: closeButton.leadingAnchor, constant: -8),
//            
//            // Message content
//            messageContentLabel.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
//            messageContentLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 4),
//            messageContentLabel.trailingAnchor.constraint(equalTo: thumbnailImageView.leadingAnchor, constant: -8),
//            messageContentLabel.bottomAnchor.constraint(lessThanOrEqualTo: parentView.bottomAnchor, constant: -8),
//            
//            // Thumbnail
//            thumbnailImageView.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
//            thumbnailImageView.centerYAnchor.constraint(equalTo: parentView.centerYAnchor),
//            thumbnailImageView.heightAnchor.constraint(equalToConstant: 44),
//            thumbnailWidthConstraint!,
//            
//            // Icon (overlays thumbnail for audio/video/call)
//            iconImageView.centerXAnchor.constraint(equalTo: thumbnailImageView.centerXAnchor),
//            iconImageView.centerYAnchor.constraint(equalTo: thumbnailImageView.centerYAnchor),
//            iconImageView.widthAnchor.constraint(equalToConstant: 24),
//            iconImageView.heightAnchor.constraint(equalToConstant: 24),
//            
//            // Close button
//            closeButton.trailingAnchor.constraint(equalTo: parentView.trailingAnchor, constant: -12),
//            closeButton.topAnchor.constraint(equalTo: parentView.topAnchor, constant: 8),
//            closeButton.widthAnchor.constraint(equalToConstant: 24),
//            closeButton.heightAnchor.constraint(equalToConstant: 24)
//        ])
//    }
//    
//    // MARK: - Configure
//    func configure(chatRoomVM:ChatRoomViewModel,uploadVM: UploadViewModel) {
//      guard let replyMessage = chatRoomVM.replyMessage else { return }
//        let isYou = replyMessage.senderId == CurrentUser.shared.currentUid
//        senderLabel.text = isYou ? "You" : replyMessage.senderName
//        
//        // Reset visibility
//        thumbnailImageView.isHidden = true
//        iconImageView.isHidden = true
//        thumbnailImageView.image = nil
//        iconImageView.image = nil
//        thumbnailWidthConstraint?.constant = 0
//        leftAccentBar.backgroundColor = isYou ? UIColor(red: 0.0, green: 0.53, blue: 0.73, alpha: 1.0) : UIColor(red: 0.0, green: 0.73, blue: 0.53, alpha: 1.0)
//        
//        let message = replyMessage
//        
//        switch replyMessage.typeMessage {
//
//        case .TEXT:
//            messageContentLabel.text = message.message.text
////            messageContentLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 100).isActive = true
//        case .IMAGE:
//            messageContentLabel.text = "📷 Photo"
//            if let image = uploadVM.getCachedImage(key: message.codeMessage) {
//                thumbnailImageView.image = image
//                thumbnailImageView.isHidden = false
//                thumbnailWidthConstraint?.constant = 44
//            }
//
//        case .VIDEO:
//            messageContentLabel.text = "🎥 Video"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "play.circle.fill")
//            iconImageView.tintColor = .white
//            iconImageView.isHidden = false
//
//        case .AUDIO:
//            let duration = 123
//            let minutes = duration / 60
//            let seconds = duration % 60
//            messageContentLabel.text = String(format: "🎤 Audio %d:%02d", minutes, seconds)
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "mic.fill")
//            iconImageView.isHidden = false
//
//        case .VOICE:
//            messageContentLabel.text = "🎙 Voice message"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "waveform")
//            iconImageView.isHidden = false
//
//        case .CALL_AUDIO:
//            messageContentLabel.text = "📞 Voice call"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "phone.fill")
//            iconImageView.isHidden = false
//
//        case .CALL_VIDEO:
//            messageContentLabel.text = "📹 Video call"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "video.fill")
//            iconImageView.isHidden = false
//
//        case .MISSING_CALL_AUDIO:
//            messageContentLabel.text = "❌ Missed voice call"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "phone.down.fill")
//            iconImageView.tintColor = .systemRed
//            iconImageView.isHidden = false
//
//        case .MISSING_CALL_VIDEO:
//            messageContentLabel.text = "❌ Missed video call"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "video.slash.fill")
//            iconImageView.tintColor = .systemRed
//            iconImageView.isHidden = false
//
//        case .DOCUMENT:
//            messageContentLabel.text = "📄 Document"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "doc.fill")
//            iconImageView.isHidden = false
//
//        case .CONTACT:
//            messageContentLabel.text = "👤 Contact"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "person.crop.circle.fill")
//            iconImageView.isHidden = false
//
//        case .LOCATION:
//            messageContentLabel.text = "📍 Location"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "location.fill")
//            iconImageView.isHidden = false
//
//        case .ISMONEY:
//            messageContentLabel.text = "💰 Payment"
//            thumbnailImageView.isHidden = false
//            thumbnailImageView.backgroundColor = UIColor(white: 0.9, alpha: 1.0)
//            thumbnailWidthConstraint?.constant = 44
//            iconImageView.image = UIImage(systemName: "banknote.fill")
//            iconImageView.tintColor = .systemGreen
//            iconImageView.isHidden = false
//        }
//
//    }
//    
//    @objc private func closeButtonTapped() {
//        print("this ws closed reply view +++++++")
//        onClose?()
//    }
//}
