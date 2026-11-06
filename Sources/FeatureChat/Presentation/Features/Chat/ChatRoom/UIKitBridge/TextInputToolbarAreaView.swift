//
//  TextInputToolbarAreaView.swift
//  WhatsAppClone
//
//  Created by Asyst on 7/21/25.
//


import UIKit
import SwiftUI
import WaanguSharedUI
import Combine
import WaanguCoreKit

class TextInputToolbarAreaView: UIView {
    private var audioRecordButton = AudioRecordButton()
    var bottomConstraint: NSLayoutConstraint?
    private var audioRecordButtonHeightConstraint: NSLayoutConstraint!
    private var cancellables = Set<AnyCancellable>()

    
    // MARK: - UI Components
    let paymentButton = UIButton(type: .system)
    private var paymentWidth: NSLayoutConstraint!
    private var onOpenPayments: (() -> Void)?
    let cameraButton = UIButton(type: .system)
    /// Collapses the camera while there is text, when send takes the mic's place.
    private var cameraWidth: NSLayoutConstraint?
    private let cameraLongPress = UILongPressGestureRecognizer()
    private var onOpenVideoNote: (() -> Void)?
    let textField = UITextView()
    let plusButton = UIButton(type: .system)
    let actionButton = UIButton(type: .system)
    
    var isSheetVisible = false
    var onPresentSheet: (() -> Void)? = nil
    var onOpenCamera: (() -> Void)? = nil
    var onSendMessage: ((String) -> Void)? = nil
    var onRecordAudio: (() -> Void)? = nil
    var onHeightChange: (() -> Void)? = nil
    /// A locked recording draws two rows, 110 pt. The bar has to grow to hold
    /// them: drawn past its bounds, the top row — time, waveform, view once —
    /// showed but could not be tapped.
    var onRecorderLockChange: ((Bool) -> Void)? = nil
    
    var onSendAudio: (() -> Void)? = nil
       var onStartRecording: (() -> Void)? = nil
       var onStopRecording: (() -> Void)? = nil
       /// The view-once choice for the recording in progress, each time it changes.
       var onReadOnce: ((Bool) -> Void)? = nil {
           didSet { audioRecordButton.showsViewOnce = onReadOnce != nil }
       }
       var onPauseOrResumeRecording: ((Bool) -> Void)? = nil
    
    
    var onTextChanged: ((String) -> Void)?
    
    private var placeholderLabel = UILabel()
    private var isRecording : Bool = false
    var currentReply: MessageDataItem? {
            didSet { updateReplyView() }
        }
    
    func updateReplyView(){
        
    }
    func clearReply(){
        
    }
    // MARK: - Init
    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false
        setupView()
        setupConstraints()
        registerKeyboardNotifications()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        cancellables.removeAll()
    }
    
    // MARK: - Configure with VoiceRecordingViewModel
    
    func configure(with viewModel: VoiceRecordingViewModel) {
        // Subscribe to audio levels
        viewModel.$audioLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in
                self?.audioRecordButton.audioLevels = levels
            }
            .store(in: &cancellables)
        
        // Subscribe to recording state
        viewModel.$recordingState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.audioRecordButton.recordingState = state
            }
            .store(in: &cancellables)
        
        // Subscribe to elapsed time
        viewModel.$elapsedTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                let minutes = Int(time) / 60
                let seconds = Int(time) % 60
                let timeString = String(format: "%d:%02d", minutes, seconds)
                self?.audioRecordButton.updateTimeLabels(with: timeString)
            }
            .store(in: &cancellables)
    }

    // MARK: - View Setup
    private func setupView() {
  
        self.setContentHuggingPriority(.required, for: .vertical)
        self.setContentCompressionResistancePriority(.required, for: .vertical)
        audioRecordButton.translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .clear
//        audioRecordButton.backgroundColor = .systemRed
        addSubview(audioRecordButton)
//        heightAnchor.constraint(equalToConstant:  60).isActive = true

        // TextField Setup
        textField.font = UIFont.systemFont(ofSize: 16)
        textField.isScrollEnabled = false
        textField.layer.cornerRadius = 15
        textField.layer.borderWidth = 1
        textField.layer.borderColor = UIColor.systemGray5.cgColor
        textField.backgroundColor = .systemBackground
        textField.textContainerInset = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        textField.delegate = self
        addSubview(textField)
        
        // Placeholder — set via updatePlaceholder(text:) from SwiftUI wrapper
        placeholderLabel.textColor = .placeholderText
        placeholderLabel.font = textField.font
        textField.addSubview(placeholderLabel)
        
        // Camera Button
        cameraButton.setImage(UIImage(systemName: "camera.fill"), for: .normal)
        cameraButton.tintColor = .label
        cameraButton.addTarget(self, action: #selector(openCamera), for: .touchUpInside)
        // A long press records a video note instead. Recognising it cancels the
        // button's touch, so the tap does not open the camera as well.
        cameraLongPress.minimumPressDuration = 0.35
        cameraLongPress.addTarget(self, action: #selector(cameraLongPressed(_:)))
        cameraLongPress.isEnabled = false
        cameraButton.addGestureRecognizer(cameraLongPress)
        addSubview(cameraButton)

        paymentButton.setImage(UIImage(systemName: "creditcard"), for: .normal)
        paymentButton.tintColor = UIColor(AppColors.primary)
        paymentButton.accessibilityIdentifier = "chat.payments"
        paymentButton.addTarget(self, action: #selector(openPayments), for: .touchUpInside)
        addSubview(paymentButton)

        // Plus Button
        plusButton.setImage(UIImage(systemName: "plus"), for: .normal)
        plusButton.tintColor = .label
        plusButton.addTarget(self, action: #selector(showActionSheet), for: .touchUpInside)
        addSubview(plusButton)
        
        // Action Button (Mic or Send)
        actionButton.tintColor = .label
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
        addSubview(actionButton)
        
        // add record button
        
        updateActionButton()
    }

    func updatePlaceholder(_ text: String) {
        placeholderLabel.text = text
        // The placeholder is a loose label on top of the text view: VoiceOver would read an
        // empty field. The field takes its text as its name and the label stays silent.
        textField.accessibilityLabel = text
        placeholderLabel.isAccessibilityElement = false
    }

    /// Names for the icon-only controls, already localized by the SwiftUI wrapper.
    func configureAccessibility(camera: String, attach: String, send: String, voice: String) {
        cameraButton.accessibilityLabel = camera
        plusButton.accessibilityLabel = attach
        actionButton.accessibilityLabel = send
        audioRecordButton.micAccessibilityLabel = voice
    }

    func configurePayments(action: (() -> Void)?, label: String) {
        onOpenPayments = action
        paymentButton.accessibilityLabel = label
        paymentButton.isHidden = action == nil
        paymentWidth.constant = action == nil ? 0 : 44
        // Changer la constante ne marque pas la barre à remettre en page : un
        // `layoutIfNeeded()` immédiat — une animation, par exemple — gardait
        // l'ancien cadre, et le bouton masqué occupait encore 44 points.
        setNeedsLayout()
    }

    func configureViewOnce(label: String) {
        audioRecordButton.viewOnceAccessibilityLabel = label
    }

    /// Nil leaves the camera button tap-only.
    func configureVideoNote(action: (() -> Void)?, label: String) {
        onOpenVideoNote = action
        cameraLongPress.isEnabled = action != nil
        // VoiceOver cannot long-press a button, so the same action is offered
        // in its actions rotor.
        cameraButton.accessibilityCustomActions = action == nil ? nil : [
            UIAccessibilityCustomAction(name: label) { [weak self] _ in
                self?.openVideoNote()
                return true
            }
        ]
    }

    @objc private func cameraLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        openVideoNote()
    }

    private func openVideoNote() {
        guard !isRecording, let onOpenVideoNote else { return }
        textField.resignFirstResponder()
        onOpenVideoNote()
    }

    @objc private func openPayments() {
        guard !isRecording else { return }
        textField.resignFirstResponder()
        onOpenPayments?()
    }

    private func setupConstraints() {
        bottomConstraint = bottomAnchor.constraint(equalTo: superview?.bottomAnchor ?? safeAreaLayoutGuide.bottomAnchor)
        
        paymentButton.translatesAutoresizingMaskIntoConstraints = false
        paymentWidth = paymentButton.widthAnchor.constraint(equalToConstant: 0)
        paymentWidth.isActive = true
        cameraButton.translatesAutoresizingMaskIntoConstraints = false
        plusButton.translatesAutoresizingMaskIntoConstraints = false
        textField.translatesAutoresizingMaskIntoConstraints = false
        actionButton.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        audioRecordButton.translatesAutoresizingMaskIntoConstraints = false
        
        // The camera sits beside the mic: [+] [text] [card] [camera] [mic].
        let cameraWidth = cameraButton.widthAnchor.constraint(equalToConstant: textField.text.isEmpty ? 30 : 0)
        self.cameraWidth = cameraWidth

        NSLayoutConstraint.activate([
            // The wallet button is 44 wide around a smaller icon, so its visible
            // gap to the camera is wider than its constant. This one matches it.
            cameraButton.trailingAnchor.constraint(equalTo: actionButton.leadingAnchor, constant: -14),
            cameraButton.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            cameraWidth,
            cameraButton.heightAnchor.constraint(equalToConstant: 30),

            plusButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            plusButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            plusButton.widthAnchor.constraint(equalToConstant: 30),
            plusButton.heightAnchor.constraint(equalToConstant: 30),
            
            textField.leadingAnchor.constraint(equalTo: plusButton.trailingAnchor, constant: 10),
            textField.trailingAnchor.constraint(equalTo: paymentButton.leadingAnchor, constant: -4),
            paymentButton.trailingAnchor.constraint(equalTo: cameraButton.leadingAnchor, constant: -4),
            paymentButton.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
            paymentButton.heightAnchor.constraint(equalToConstant: 44),
//            textField.trailingAnchor.constraint(equalTo: audioRecordButton.leadingAnchor, constant: -10),
            textField.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            textField.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            
            placeholderLabel.leadingAnchor.constraint(equalTo: textField.leadingAnchor, constant: 12),
            placeholderLabel.topAnchor.constraint(equalTo: textField.topAnchor, constant: 7),
            
            actionButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            actionButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            actionButton.widthAnchor.constraint(equalToConstant: 36),
            actionButton.heightAnchor.constraint(equalToConstant: 36),
            
            audioRecordButton.leadingAnchor.constraint(equalTo: leadingAnchor,constant: 0),
            audioRecordButton.topAnchor.constraint(equalTo: topAnchor ,constant: 0),
            audioRecordButton.trailingAnchor.constraint(equalTo: trailingAnchor ,constant: 0),
            audioRecordButton.bottomAnchor.constraint(equalTo: bottomAnchor ,constant: -17),
           
//            bottomConstraint!
        ])
//        bringSubviewToFront(audioRecordButton)
        audioRecordButtonHeightConstraint = audioRecordButton.heightAnchor.constraint(equalToConstant: 44) // initial height
        audioRecordButtonHeightConstraint.isActive = true
        // 2️⃣ Forward callbacks if you want
          audioRecordButton.onSendAudio = { [weak self] in
              self?.onSendAudio?()
              self?.onRecorderLockChange?(false)
              // After the send has read the choice: the next recording starts off.
              self?.audioRecordButton.resetViewOnce()
              debugLog("send audio")
              UIView.animate(withDuration: 0.25) {
                  self?.audioRecordButtonHeightConstraint.constant = 44
                  self?.isRecording = false
                  self?.textField.alpha = 1
                  self?.plusButton.alpha = 1
                  self?.cameraButton.alpha = 1
                  self?.paymentButton.alpha = 1
                  
                  self?.layoutIfNeeded()

              }
          }
        audioRecordButton.onLockedAudio = { [weak self] in
            self?.onRecorderLockChange?(true)
//            UIView.animate(withDuration: 0.25) {
                self?.audioRecordButtonHeightConstraint.constant = 110
                self?.layoutIfNeeded()
//            }
        }
          
          audioRecordButton.onStartRecording = { [weak self] in
              self?.onStartRecording?()
              debugLog("start recording audio")
              UIView.animate(withDuration: 0.25) {

                  self?.isRecording = true
                  self?.textField.alpha = 0
                  self?.plusButton.alpha = 0
                  self?.cameraButton.alpha = 0
                  self?.paymentButton.alpha = 0
//                  self?.audioRecordButtonHeightConstraint.constant = 110
                  self?.layoutIfNeeded()

              }
        
          }
          
          audioRecordButton.onStopRecording = { [weak self] in
              self?.onStopRecording?()
              self?.onRecorderLockChange?(false)
              self?.audioRecordButton.resetViewOnce()
              debugLog("stop recording audio")
              UIView.animate(withDuration: 0.25) {
                  self?.audioRecordButtonHeightConstraint.constant = 44
                  self?.isRecording = false
                  self?.textField.alpha = 1
                  self?.plusButton.alpha = 1
                  self?.cameraButton.alpha = 1
                  self?.paymentButton.alpha = 1
                  self?.layoutIfNeeded()

              }
           
          }
        audioRecordButton.onOnceRead = { [weak self] in
            guard let self else { return }
            self.onReadOnce?(self.audioRecordButton.isViewOnceSelected)
            debugLog("on Read once recording audio")
        }
        audioRecordButton.onPauseOrResume = { [weak self] isPaused in
            self?.onPauseOrResumeRecording?(isPaused)
            debugLog("is Recording not stopped recording \(isPaused)")
        }
    }



    private func updateActionButton() {
        if textField.text.isEmpty {
            cameraWidth?.constant = 30
            UIView.animate(withDuration: 0.25) {
                self.audioRecordButton.alpha = 1
                self.audioRecordButton.buttonColor = UIColor(AppColors.primary)
                self.actionButton.alpha = 0
                self.cameraButton.alpha = 1
                self.layoutIfNeeded()
            }
//            actionButton.setImage(UIImage(systemName: "mic"), for: .normal)
//            actionButton.backgroundColor = .clear
//            actionButton.tintColor = .black
//            actionButton.layer.cornerRadius = 0
                
        } else {
            // Hidden while typing, as on WhatsApp: send takes the mic's place
            // and the text gets the room.
            cameraWidth?.constant = 0
            UIView.animate(withDuration: 0.25) {
                self.audioRecordButton.alpha = 0
                self.cameraButton.alpha = 0
                self.layoutIfNeeded()
                self.actionButton.alpha = 1
                self.actionButton.setImage(UIImage(systemName: "arrow.up"), for: .normal)
                self.actionButton.tintColor = .white
                self.actionButton.backgroundColor = UIColor(AppColors.primary)
                self.actionButton.layer.cornerRadius = 18
            }
        }
    }

    // MARK: - Actions
    @objc private func showActionSheet() {
        onPresentSheet?()
    }

    @objc private func openCamera() {
        onOpenCamera?()
    }

    @objc private func actionButtonTapped() {
        if textField.text.isEmpty {
            onRecordAudio?()
        } else {
            onSendMessage?(textField.text)
            textField.text = ""
            textViewDidChange(textField)
        }
    }

    // MARK: - Keyboard Observing
    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardDidChangeFrame),
                                               name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
    }
    
    @objc private func keyboardDidChangeFrame(notification: Notification) {
        // Handle layout updates if needed.
    }
}

// MARK: - UITextViewDelegate
extension TextInputToolbarAreaView: UITextViewDelegate {
   
    func textViewDidChange(_ textView: UITextView) {
        placeholderLabel.isHidden = !textView.text.isEmpty
        updateActionButton()
        onTextChanged?(textView.text ?? "")
    }
}


final class ReplyViewContainer: UIView {
    
    private let colorBar = UIView()
    private let senderLabel = UILabel()
    private let replyContentView = UIStackView()
    private let closeButton = UIButton(type: .system)
    
    var onCancel: (() -> Void)?
    
    init(msg: MessageDataItem) {
        super.init(frame: .zero)
        setupUI(msg: msg)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Build icon + label
    private func makeReplyContentView(_ msg: MessageDataItem) -> UIView {
        let container = UIStackView()
        container.axis = .horizontal
        container.alignment = .center
        container.spacing = 6
        
        let iconView = UIImageView()
        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .secondaryLabel
        iconView.widthAnchor.constraint(equalToConstant: 16).isActive = true
        iconView.heightAnchor.constraint(equalToConstant: 16).isActive = true
        
        let textLabel = UILabel()
        textLabel.font = .systemFont(ofSize: 14)
        textLabel.textColor = .secondaryLabel
        textLabel.numberOfLines = 2
        
        switch msg.typeMessage {
        case .AUDIO, .VOICE:
            iconView.image = UIImage(systemName: "waveform.circle.fill")
            textLabel.text = "Voice message"
            container.addArrangedSubview(iconView)
            
        case .IMAGE:
            iconView.image = UIImage(systemName: "photo.fill")
            textLabel.text = "Photo"
            container.addArrangedSubview(iconView)
            
        case .LOCATION:
            iconView.image = UIImage(systemName: "location")
            textLabel.text = "location"
            container.addArrangedSubview(iconView)
            
        case .VIDEO, .VIDEO_NOTE:
            iconView.image = UIImage(systemName: "video.fill")
            textLabel.text = "Video"
            container.addArrangedSubview(iconView)
            
        case .DOCUMENT:
            iconView.image = UIImage(systemName: "doc.fill")
            textLabel.text = "File"
            container.addArrangedSubview(iconView)
            
        case .TEXT:
            iconView.image = nil
            textLabel.text = msg.message.text
            
        default:
            iconView.image = nil
            textLabel.text = ""
        }
        
        
        container.addArrangedSubview(textLabel)
        return container
    }
    
    // MARK: - Setup UI
    private func setupUI(msg: MessageDataItem) {
        backgroundColor = UIColor.systemGray6.withAlphaComponent(0.7)
        layer.cornerRadius = 10
        clipsToBounds = true
        
        colorBar.backgroundColor = .systemBlue
        colorBar.layer.cornerRadius = 2
        
        senderLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        senderLabel.textColor = .systemBlue
        senderLabel.text = msg.isSentByMe ? "You" : msg.senderName
        
        let replyContent = makeReplyContentView(msg)
        
        closeButton.setImage(UIImage(systemName: "xmark.circle"), for: .normal)
        closeButton.tintColor = .gray
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        
        addSubview(colorBar)
        addSubview(senderLabel)
        addSubview(replyContent)
        addSubview(closeButton)
        
        colorBar.translatesAutoresizingMaskIntoConstraints = false
        senderLabel.translatesAutoresizingMaskIntoConstraints = false
        replyContent.translatesAutoresizingMaskIntoConstraints = false
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        
        NSLayoutConstraint.activate([
            colorBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            colorBar.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            colorBar.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            colorBar.widthAnchor.constraint(equalToConstant: 6),
            
            senderLabel.leadingAnchor.constraint(equalTo: colorBar.trailingAnchor, constant: 8),
            senderLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            
            replyContent.leadingAnchor.constraint(equalTo: senderLabel.leadingAnchor),
            replyContent.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -8),
            replyContent.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 2),
            replyContent.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -8),
            
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: 24),
            closeButton.heightAnchor.constraint(equalToConstant: 24)
        ])
    }
    
    @objc private func closeTapped() {
        onCancel?()
    }
}


