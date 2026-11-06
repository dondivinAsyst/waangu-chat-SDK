
import UIKit
import AVFoundation
import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

class AudioRecordButton: UIView {
    
    var onStartRecording : (() -> Void)?
    var onStopRecording : (() -> Void)?
    var onSendAudio : (() -> Void)?
    var onLockedAudio : (() -> Void)?
    var onOnceRead : (() -> Void)?
    var onPauseOrResume : ((Bool) -> Void)?
    /// Off where nothing handles it — channels — so the button is not offered
    /// for a choice that would be ignored.
    var showsViewOnce = true
    var viewOnceAccessibilityLabel: String? {
        didSet {
            readOnceBtn.accessibilityLabel = viewOnceAccessibilityLabel
        }
    }

    /// Spoken name of the mic control; the host supplies it already localized.
    var micAccessibilityLabel: String? {
        didSet { micButton.accessibilityLabel = micAccessibilityLabel }
    }
    var buttonColor : UIColor = UIColor(AppColors.primary) {
        didSet {
            micButton.backgroundColor = buttonColor
            sendButton.backgroundColor = buttonColor
            
        }
    }
    
    // MARK: - UI Components
    private let micButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.backgroundColor = UIColor(AppColors.primary)
        btn.layer.cornerRadius = 18
        btn.tintColor = .white
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "mic.fill", withConfiguration: config), for: .normal)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let slideToCancel: UILabel = {
        let lbl = UILabel()
        lbl.text = "← Slide to cancel"
        lbl.textColor = .systemGray
        lbl.font = UIFont.systemFont(ofSize: 14)
        lbl.alpha = 0
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let recordingContainer: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
        view.layer.cornerRadius = 25
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
        return view
    }()
    private let recordingContainerLocked: UIView = {
        let view = UIView()
        view.backgroundColor = .systemBackground
//        view.layer.cornerRadius = 25
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
//        view.isHidden = true
        return view
    }()
    private let recordingContainerLockedActions: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
//        view.layer.cornerRadius = 25
//        view.alpha = 1
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
//        view.isHidden = true
        return view
    }()
    private let recordingContainerLockedMeter: UIView = {
        let view = UIView()
        view.backgroundColor = .systemGray6
//        view.layer.cornerRadius = 25
//        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        view.clipsToBounds = true
//        view.isHidden = true
        return view
    }()
    
    private let redMic: UIImageView = {
        let img = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 8,weight: .medium)
        img.image = UIImage(systemName: "mic",withConfiguration: config)
        img.tintColor = .systemRed
        img.translatesAutoresizingMaskIntoConstraints = false
        return img
    }()
//    private let redMicContinue: UIImageView = {
//        let img = UIImageView()
//        let config = UIImage.SymbolConfiguration(pointSize: 12,weight: .medium)
//        img.image = UIImage(systemName: "mic",withConfiguration: config)
//        img.tintColor = .red
//        img.alpha = 0
//        img.translatesAutoresizingMaskIntoConstraints = false
//        return img
//    }()
    private let redMicContinue: UIButton = {
        let btn = UIButton(type: .system)
//        btn.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 0.42, alpha: 1.0)
        btn.layer.cornerRadius = 25
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        btn.setImage(UIImage(systemName: "mic.fill", withConfiguration: config), for: .normal)
        btn.tintColor = .systemRed
        btn.alpha = 0
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let redPause: UIButton = {
        let btn = UIButton(type: .system)
//        btn.backgroundColor = UIColor(red: 0.0, green: 0.48, blue: 0.42, alpha: 1.0)
        btn.layer.cornerRadius = 25
        let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        btn.setImage(UIImage(systemName: "pause.fill", withConfiguration: config), for: .normal)
        // Pausing is not destructive: red stays for the trash and the recording dot.
        btn.tintColor = UIColor(AppColors.primary)
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
//    private let : UIImageView = {
//        let img = UIImageView()
//        let config = UIImage.SymbolConfiguration(pointSize: 12,weight: .medium)
//        img.image = UIImage(systemName: "pause.fill",withConfiguration: config)
//        img.tintColor = .red
//        img.translatesAutoresizingMaskIntoConstraints = false
//        return img
//    }()
        
    private let timeLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "0:00"
        lbl.textColor = UIColor.label
//        lbl.backgroundColor = .systemGray
        lbl.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    private let timeLabelLocked: UILabel = {
        let lbl = UILabel()
        lbl.text = "0:00"
        lbl.textColor = UIColor.label
//        lbl.backgroundColor = .red
        lbl.font = UIFont.monospacedDigitSystemFont(ofSize: 16, weight: .regular)
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let readOnceBtn : UIButton = {
        let btn = UIButton()
        let config = UIImage.SymbolConfiguration(pointSize:24,weight: .medium)
        btn.setImage(UIImage(systemName: "timer",withConfiguration: config),for:.normal)
        btn.tintColor = .systemGray
        btn.layer.cornerRadius = 22
//        btn.backgroundColor = .red
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let timeContainer : UIView = {
        let Tview = UIView()
        Tview.backgroundColor =  UIColor.systemBackground
        Tview.layer.cornerRadius = 6
        Tview.translatesAutoresizingMaskIntoConstraints = false
        return Tview
    }()
    
    private let lockContainer: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemGray6
        view.layer.cornerRadius = 20
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    private let lockIcon: UIImageView = {
        let img = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        img.image = UIImage(systemName: "lock.fill", withConfiguration: config)
        img.tintColor = .systemGray
        img.translatesAutoresizingMaskIntoConstraints = false
        return img
    }()
    
    private let lockArrow: UIImageView = {
        let img = UIImageView()
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        img.image = UIImage(systemName: "chevron.up", withConfiguration: config)
        img.tintColor = .systemGray
        img.translatesAutoresizingMaskIntoConstraints = false
        return img
    }()
    
    private let deleteButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 16, weight: .medium)
        btn.setImage(UIImage(systemName: "trash.fill", withConfiguration: config), for: .normal)
        btn.tintColor = .systemRed
        btn.alpha = 0
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    private let slideDeleteButton: UIButton = {
        let btn = UIButton(type: .system)
        let config = UIImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        btn.setImage(UIImage(systemName: "trash.fill", withConfiguration: config), for: .normal)
        btn.tintColor = UIColor.systemRed
        btn.alpha = 0
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
//    private let sendButton: UIButton = {
//        var config = UIButton.Configuration.filled()
//
//        // Set image with size and weight
//        let imageConfig = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
//        config.image = UIImage(systemName: "paperplane.fill", withConfiguration: imageConfig)
//
//        // Padding around the image
//        config.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 16, bottom: 10, trailing: 16)
//
//        // Colors
//        config.baseBackgroundColor = UIColor(red: 0.0, green: 0.48, blue: 0.42, alpha: 1.0)
//        config.baseForegroundColor = .white // tint color (for image)
//
//        // Rounded corners (equivalent to cornerRadius = 25)
//        config.cornerStyle = .capsule // You can use `.medium` or `.large` as alternatives
//
//        // Create the button with this configuration
//        let btn = UIButton(configuration: config)
//        btn.alpha = 1
//        btn.translatesAutoresizingMaskIntoConstraints = false
//
//        return btn
//    }()
    
    private let sendButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.backgroundColor = UIColor(AppColors.primary)
        btn.layer.cornerRadius = 18
       
        let config = UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
        btn.setImage(UIImage(systemName: "arrow.up", withConfiguration: config), for: .normal)
        btn.tintColor = .white
        btn.alpha = 1
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private var waveformViews: [UIView] = []
    
    // MARK: - Properties
    private var isRecording = false
    private var isLocked = false
    private var startLocation: CGPoint = .zero
    private var timer: Timer?
    private var recordingTime: TimeInterval = 0
    private var audioRecorder: AVAudioRecorder?
    // REMOVED: private var waveformTimer: Timer? - Now using real audio levels
    
    // NEW: Audio levels from VoiceRecordingViewModel
    var audioLevels: [Float] = Array(repeating: 0, count: 60) { // 60 bars for full width
        didSet {
            updateWaveform(with: audioLevels)
        }
    }
    
    // NEW: Recording state from VoiceRecordingViewModel
    var recordingState: RecordingState = .idle {
        didSet {
            updateUIForState(recordingState)
        }
    }
    
    private var recordingContainerLeading: NSLayoutConstraint?
    private var recordingContainerTrailing: NSLayoutConstraint?
    private var micButtonTrailing: NSLayoutConstraint?
    private var micButtonTop : NSLayoutConstraint?
    private var lockContainerBottom: NSLayoutConstraint?
    private var isSlidingTop = false
    private var isSlidingLeft = false
    private var isPaused = false
    private var isReadOncePressed = false
    
    // MARK: - Initialization
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        setupGestures()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        setupGestures()
    }
    
    // MARK: - Setup
    private func setupUI() {
       
//              backgroundColor = UIColor
        
 
        
        
        
        addSubview(recordingContainerLocked)
        
        addSubview(recordingContainer)
     
        addSubview(micButton)
//        addSubview(timeContainer)
        addSubview(lockContainer)
        recordingContainer.addSubview(slideToCancel)
        recordingContainer.addSubview(timeContainer)
        
        timeContainer.addSubview(redMic)
        timeContainer.addSubview(slideDeleteButton)
        timeContainer.addSubview(timeLabel)
        
     
        recordingContainerLocked.addSubview(recordingContainerLockedMeter)
        recordingContainerLocked.addSubview(recordingContainerLockedActions)
        
        recordingContainerLockedActions.addSubview(deleteButton)
        recordingContainerLockedActions.addSubview(redMicContinue)
        recordingContainerLockedActions.addSubview(redPause)
        recordingContainerLockedActions.addSubview(sendButton)
        
        recordingContainerLockedMeter.addSubview(timeLabelLocked)
//        recordingContainerLockedMeter.addSubview(waveformTimer)
        recordingContainerLockedMeter.addSubview(readOnceBtn)
        
      
        
        lockContainer.addSubview(lockIcon)
        lockContainer.addSubview(lockArrow)
        
//        addSubview(deleteButton)
//        addSubview(sendButton)
        
        
        // Setup waveform
        setupWaveform()
        
        // Constraints
        NSLayoutConstraint.activate([
            
          
            
//            micButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
//            micButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            micButton.widthAnchor.constraint(equalToConstant: 36),
            micButton.heightAnchor.constraint(equalToConstant: 36),
            
            
            recordingContainer.centerYAnchor.constraint(equalTo: bottomAnchor,constant: -10),
            recordingContainer.heightAnchor.constraint(equalToConstant: 50),
            
            recordingContainerLocked.leadingAnchor.constraint(equalTo: leadingAnchor),
            recordingContainerLocked.trailingAnchor.constraint(equalTo: trailingAnchor),
            recordingContainerLocked.bottomAnchor.constraint(equalTo: bottomAnchor),
            recordingContainerLocked.heightAnchor.constraint(equalToConstant: 140),
            
           
            recordingContainerLockedMeter.leadingAnchor.constraint(equalTo: recordingContainerLocked.leadingAnchor),
            recordingContainerLockedMeter.trailingAnchor.constraint(equalTo: recordingContainerLocked.trailingAnchor),
            recordingContainerLockedMeter.topAnchor.constraint(equalTo: recordingContainerLocked.topAnchor),
            recordingContainerLockedMeter.heightAnchor.constraint(equalToConstant: 70),
            
            
            recordingContainerLockedActions.leadingAnchor.constraint(equalTo: recordingContainerLocked.leadingAnchor),
            recordingContainerLockedActions.trailingAnchor.constraint(equalTo: recordingContainerLocked.trailingAnchor),
            recordingContainerLockedActions.topAnchor.constraint(equalTo: recordingContainerLockedMeter.bottomAnchor),
            recordingContainerLockedActions.heightAnchor.constraint(equalToConstant: 70),
            
            timeLabelLocked.leadingAnchor.constraint(equalTo: recordingContainerLockedMeter.leadingAnchor,constant: 15),
            timeLabelLocked.centerYAnchor.constraint(equalTo: recordingContainerLockedMeter.centerYAnchor),
            timeLabelLocked.widthAnchor.constraint(equalToConstant: 40),
            
            readOnceBtn.trailingAnchor.constraint(equalTo: recordingContainerLockedMeter.trailingAnchor, constant: -15),
            readOnceBtn.centerYAnchor.constraint(equalTo: recordingContainerLockedMeter.centerYAnchor),
            readOnceBtn.widthAnchor.constraint(equalToConstant: 44),
            readOnceBtn.heightAnchor.constraint(equalToConstant: 44),
            
            
            
            
//            recordingContainer.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -8),
            
//            slideToCancel.trailingAnchor.constraint(equalTo:trailingAnchor ),
            slideToCancel.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
            slideToCancel.centerXAnchor.constraint(equalTo: recordingContainer.centerXAnchor,constant: 25),
            
            redMic.leadingAnchor.constraint(equalTo: recordingContainer.leadingAnchor, constant: 15),
            redMic.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
            redMic.widthAnchor.constraint(equalToConstant: 28),
            redMic.heightAnchor.constraint(equalToConstant: 28),
            
//
            
            
            timeLabel.leadingAnchor.constraint(equalTo: redMic.trailingAnchor, constant: 8),
            timeLabel.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
//            timeLabel.trailingAnchor.constraint(equalTo: recordingCon, constant: -15),
            timeContainer.heightAnchor.constraint(equalToConstant: 50),
            timeContainer.leadingAnchor.constraint(equalTo: recordingContainer.leadingAnchor),
//            timeContainer.trailingAnchor.constraint(equalTo: recordingContainer.centerXAnchor,constant: -50),
            timeContainer.widthAnchor.constraint(equalToConstant: 90),
            timeContainer.centerYAnchor.constraint(equalTo: recordingContainer.centerYAnchor),
            slideDeleteButton.leadingAnchor.constraint(equalTo: timeContainer.leadingAnchor,constant: 15),
            slideDeleteButton.centerYAnchor.constraint(equalTo: timeContainer.centerYAnchor),
          

            
            lockContainer.centerXAnchor.constraint(equalTo: micButton.centerXAnchor),
            lockContainer.widthAnchor.constraint(equalToConstant: 40),
            lockContainer.heightAnchor.constraint(equalToConstant: 80),
            
            lockIcon.topAnchor.constraint(equalTo: lockContainer.topAnchor, constant: 8),
            lockIcon.centerXAnchor.constraint(equalTo: lockContainer.centerXAnchor),
            
            lockArrow.topAnchor.constraint(equalTo: lockIcon.bottomAnchor, constant: 12),
            lockArrow.centerXAnchor.constraint(equalTo: lockContainer.centerXAnchor),
            
            deleteButton.leadingAnchor.constraint(equalTo: recordingContainerLockedActions.leadingAnchor, constant: 16),
            deleteButton.centerYAnchor.constraint(equalTo: recordingContainerLockedActions.centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 44),
            deleteButton.heightAnchor.constraint(equalToConstant: 44),
            
            sendButton.trailingAnchor.constraint(equalTo: recordingContainerLockedActions.trailingAnchor, constant: -16),
            sendButton.centerYAnchor.constraint(equalTo: recordingContainerLockedActions.centerYAnchor),
            sendButton.widthAnchor.constraint(equalToConstant: 36),
            sendButton.heightAnchor.constraint(equalToConstant: 36),
            
            redMicContinue.centerXAnchor.constraint(equalTo: recordingContainerLockedActions.centerXAnchor),
            redMicContinue.centerYAnchor.constraint(equalTo: recordingContainerLockedActions.centerYAnchor),
            redMicContinue.widthAnchor.constraint(equalToConstant: 36),
            redMicContinue.heightAnchor.constraint(equalToConstant: 36),
            
//            redPause.leadingAnchor.constraint(equalTo: recordingContainerLockedActions.leadingAnchor),
                    redPause.centerYAnchor.constraint(equalTo: recordingContainerLockedActions.centerYAnchor),
                    redPause.centerXAnchor.constraint(equalTo: recordingContainerLockedActions.centerXAnchor),
                    redPause.widthAnchor.constraint(equalToConstant: 44),
                    redPause.heightAnchor.constraint(equalToConstant: 44),
           
        ])
        
        recordingContainerLeading = recordingContainer.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        recordingContainerTrailing = recordingContainer.trailingAnchor.constraint(equalTo: micButton.leadingAnchor, constant: -16)
        recordingContainerTrailing?.isActive = true
        recordingContainerLeading?.isActive = true
        
    
        
        lockContainerBottom = lockContainer.bottomAnchor.constraint(equalTo: micButton.topAnchor, constant: -16)
        lockContainerBottom?.isActive = true
        micButtonTop =  micButton.centerYAnchor.constraint(equalTo: bottomAnchor,constant: -10)
            micButtonTop?.isActive = true
        
        micButtonTrailing =    micButton.trailingAnchor.constraint(equalTo: trailingAnchor,constant: -12)
//        micButton.backgroundColor = buttonColor
        micButtonTrailing?.isActive = true
        deleteButton.addTarget(self, action: #selector(deleteRecording), for: .touchUpInside)
        sendButton.addTarget(self, action: #selector(sendRecording), for: .touchUpInside)
        redPause.addTarget(self, action: #selector(pauseRecording), for: .touchUpInside)
        redMicContinue.addTarget(self, action: #selector(pauseRecording), for: .touchUpInside)
        readOnceBtn.addTarget(self, action: #selector(readOncePressed), for: .touchUpInside)
    }
    
    private func setupWaveform() {
        let waveformStack = UIStackView()
        waveformStack.axis = .horizontal
        waveformStack.spacing = 2
        waveformStack.distribution = .fillEqually
        waveformStack.alignment = .center
        waveformStack.translatesAutoresizingMaskIntoConstraints = false
        
        recordingContainerLockedMeter.addSubview(waveformStack)
        
        // Create more bars for full-width waveform (WhatsApp style)
        // Approximately 60 bars to fill the width
        for i in 0..<60 {
            let bar = UIView()
            bar.backgroundColor = UIColor(AppColors.primary)
            bar.layer.cornerRadius = 1
            bar.translatesAutoresizingMaskIntoConstraints = false
            bar.alpha = 0.0 // Start hidden - will show as audio is recorded
            bar.tag = 100 + i
            waveformStack.addArrangedSubview(bar)
            waveformViews.append(bar)
            
            NSLayoutConstraint.activate([
                bar.widthAnchor.constraint(equalToConstant: 2),
                bar.heightAnchor.constraint(equalToConstant: 4) // Will be animated based on audio levels
            ])
        }
        
        debugLog("🌊 AudioRecordButton: Setup \(waveformViews.count) waveform bars")
        
        NSLayoutConstraint.activate([
            // Full width: from time label to read once button
            waveformStack.leadingAnchor.constraint(equalTo: timeLabelLocked.trailingAnchor, constant: 8),
            waveformStack.trailingAnchor.constraint(equalTo: readOnceBtn.leadingAnchor, constant: -8),
            waveformStack.centerYAnchor.constraint(equalTo: recordingContainerLockedMeter.centerYAnchor),
            waveformStack.heightAnchor.constraint(equalToConstant: 30)
        ])
    }
    
    private func setupGestures() {
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        micButton.addGestureRecognizer(longPress)
    }
    
    @objc private func readOncePressed() {
        isReadOncePressed.toggle() // cleaner Swift syntax
        applyReadOnceAppearance(animated: true)

        debugLog("pressed read")
        onOnceRead?()
    }

    /// Whether the recording in progress will be sent as view once.
    var isViewOnceSelected: Bool { isReadOncePressed }

    /// Turns view once back off, so the next recording does not start with it on.
    func resetViewOnce() {
        guard isReadOncePressed else { return }
        isReadOncePressed = false
        applyReadOnceAppearance(animated: false)
    }

    /// Off: a grey timer. On: a white timer on a filled primary circle.
    private func applyReadOnceAppearance(animated: Bool) {
        let isOn = isReadOncePressed
        let config = UIImage.SymbolConfiguration(pointSize: isOn ? 20 : 24, weight: isOn ? .semibold : .medium)
        let apply = {
            self.readOnceBtn.setImage(UIImage(systemName: "timer", withConfiguration: config), for: .normal)
            self.readOnceBtn.tintColor = isOn ? .white : .systemGray
            self.readOnceBtn.backgroundColor = isOn ? self.buttonColor : .clear
        }
        readOnceBtn.accessibilityTraits = isOn ? [.button, .selected] : .button
        if animated {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
        if animated {
            UIView.transition(with: readOnceBtn, duration: 0.2, options: .transitionCrossDissolve, animations: apply)
        } else {
            apply()
        }
    }
    
    // MARK: - Gesture Handling
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        let location = gesture.location(in: self)
        
        switch gesture.state {
        case .began:
            startLocation = location
            startRecording()
            
        case .changed:
            if !isLocked {
                handleDrag(location: location)
            }
            
        case .ended, .cancelled:
            if !isLocked {
                handleRelease(location: location)
            }
        
            
        default:
            break
        }
    }
    
    private func handleDrag(location: CGPoint) {
        let deltaX =  startLocation.x - location.x
        let deltaY = startLocation.y - location.y
        
        debugLog("start loaciton was \(startLocation.x) \(location.x)")
        // Vertical drag for lock
        if deltaY > 0 && !isSlidingLeft {
            isSlidingTop = true
            let progress = min(deltaY / 100, 1.0)
            lockContainerBottom?.constant = -16 - (deltaY * 0.5)
            micButtonTop?.constant = -10 - (deltaY * 0.5)
            micButton.transform = CGAffineTransform(scaleX: 1.5 - progress, y: 1.5 - progress)
            
            if progress > 0.9 && !isLocked {
                lockRecording()
                return
                
            }
        }else{
            isSlidingTop = false
//            print("DeltaY has hit \(deltaY)")
        }

        
        // Horizontal drag for cancel
        if deltaX > 0 && !isSlidingTop {
            isSlidingLeft = true
            let offset = min(deltaX, 150)
//            recordingContainerTrailing?.constant = -8 - offset
            micButtonTrailing?.constant = -8 - offset
            slideToCancel.alpha = 8 - (offset / 150)
            lockContainer.isHidden = true
            
            if offset > 70 {
                UIView.animate(withDuration: 1, animations: {
                    self.slideDeleteButton.alpha = 1
                    self.redMic.alpha = 0
                })
               
            }else{
                UIView.animate(withDuration: 1, animations: {
                    self.slideDeleteButton.alpha = 0
                    self.redMic.alpha = 1
                })

            }
            
            if offset > 120 {
                cancelRecording()
//                onStopRecording?()
            }
        }else{
            isSlidingLeft = false
            lockContainer.isHidden = false

            debugLog("DeltaX has hit \(deltaX)")
            
        }
    }
    
    private func handleRelease(location: CGPoint) {
        let deltaX = startLocation.x - location.x
        
        if deltaX < 120 {
            sendRecording()
        } else {
            cancelRecording()
        }
    }
    
    
    // MARK: - Recording Actions
    private func startRecording() {
        isRecording = true
        recordingTime = 0
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseOut) {
            self.recordingContainer.alpha = 1
            self.slideToCancel.alpha = 1
            self.lockContainer.alpha = 1
            self.micButton.transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        }

        
        // REMOVED: animateWaveform() - Now using real audio levels from VoiceRecordingViewModel
        
        // Pulse red dot
        pulseRedDot()
        onStartRecording?()
    }
    
    private func lockRecording() {
        isLocked = true
        self.onLockedAudio?()
        
        debugLog("🔒 Recording locked - showing unlock/send buttons and waveform")
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        
        // WhatsApp-style locked UI: show unlock button, send button, timer, and waveform
        UIView.animate(withDuration: 0.3, animations: {
            // Hide unlocked state UI
            self.lockContainer.alpha = 0
            self.slideToCancel.alpha = 0
            self.recordingContainer.alpha = 0
            self.micButton.alpha = 0
            
            // Show locked state UI
            self.recordingContainerLocked.alpha = 1
            self.deleteButton.alpha = 1
            self.sendButton.alpha = 1
            self.redPause.alpha = 1
            self.timeLabelLocked.alpha = 1
            self.readOnceBtn.alpha = self.showsViewOnce ? 1 : 0
            
            // Waveform bars will show progressively as audio is recorded (handled by updateWaveformBars)
            
            self.lockIcon.transform = CGAffineTransform(translationX: 0, y: 10)
        })
    }
    
    private func cancelRecording() {
        stopRecording(send: false)
        onStopRecording?()
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.warning)
    }
    
    
    @objc private func deleteRecording() {
      
        cancelRecording()
    }
    
    @objc private func sendRecording() {
        stopRecording(send: true)
        onSendAudio?()
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    @objc private func pauseRecording() {
//        isPaused.toggle()
        debugLog("\(isPaused) state")
        if !isPaused {
            redPause.alpha = 0
            redMicContinue.alpha = 1
            isPaused = !isPaused
            
        }else{
            
            redMicContinue.alpha = 0
            redPause.alpha = 1
            isPaused = !isPaused
        }
        onPauseOrResume?(!isPaused)

//        UIView.animate(withDuration: 0.15, animations: {
//            let activeButton = self.isPaused ? self.redMicContinue : self.redPause
//            activeButton.transform = CGAffineTransform(scaleX: 0.8, y: 0.8)
//        }) { _ in
//            UIView.animate(withDuration: 0.15) {
//                self.redMicContinue.alpha = self.isPaused ? 1 : 0
//                self.redPause.alpha = self.isPaused ? 0 : 1
//                self.redMicContinue.transform = .identity
//                self.redPause.transform = .identity
//            }
//        }
    }
    


    
    private func stopRecording(send: Bool) {
        isPaused = false
        isRecording = false
        isLocked = false
        timer?.invalidate()
        micButtonTop?.constant = -10
        micButtonTrailing?.constant = -12
        recordingContainerTrailing?.constant = -16
        redMicContinue.alpha = 0
        redPause.alpha = 1
    
        // Smooth transition back to idle state
        UIView.animate(withDuration: 0.3, animations: {
            self.recordingContainer.alpha = 0
            self.slideToCancel.alpha = 0
            self.lockContainer.alpha = 0
            self.deleteButton.alpha = 0
            self.sendButton.alpha = 0
            self.recordingContainerLocked.alpha = 0
            self.micButton.alpha = 1
            self.micButton.transform = .identity
            self.timeLabelLocked.alpha = 0
            self.readOnceBtn.alpha = 0
        }) { _ in
            self.recordingContainerLeading?.constant = 16
            self.lockContainerBottom?.constant = -16
            self.lockIcon.transform = .identity
        }
        
        // Reset waveform to default state (hidden)
        for view in waveformViews {
            view.layer.removeAllAnimations()
            view.alpha = 0.0 // Hide all bars
            view.constraints.first { $0.firstAttribute == .height }?.constant = 4
        }
        audioLevels = Array(repeating: 0, count: 60)
    }
    
    // MARK: - Helpers
    private func updateRecordingTime() {
        recordingTime += 1
        debugLog("time is now: \(recordingTime)")
        let minutes = Int(recordingTime) / 60
        let seconds = Int(recordingTime) % 60
        timeLabel.text = String(format: "%d:%02d", minutes, seconds)
        timeLabelLocked.text = String(format: "%d:%02d", minutes, seconds)
    }
    
    /// Public method to update time labels from SwiftUI
    public func updateTimeLabels(with timeString: String) {
        timeLabel.text = timeString
        timeLabelLocked.text = timeString
    }
    
    private func pulseRedDot() {
        UIView.animate(withDuration: 0.6, delay: 0, options: [.repeat, .autoreverse]) {
            self.redMic.alpha = 0.1
        }
    }
    
    // MARK: - NEW: Real Audio Level Updates
    
    /// Update waveform with real audio levels from VoiceRecordingViewModel
    private func updateWaveform(with levels: [Float]) {
        // Handle array size mismatch gracefully
        if levels.count != waveformViews.count {
            debugLog("⚠️ Waveform level count mismatch - levels: \(levels.count), views: \(waveformViews.count)")
            
            // Pad or truncate to match
            var adjustedLevels = levels
            if adjustedLevels.count < waveformViews.count {
                // Pad with zeros
                adjustedLevels.append(contentsOf: Array(repeating: 0, count: waveformViews.count - adjustedLevels.count))
            } else if adjustedLevels.count > waveformViews.count {
                // Truncate
                adjustedLevels = Array(adjustedLevels.prefix(waveformViews.count))
            }
            
            // Use adjusted levels
            updateWaveformBars(with: adjustedLevels)
            return
        }
        
        updateWaveformBars(with: levels)
    }
    
    private func updateWaveformBars(with levels: [Float]) {
        // In WhatsApp, new bars appear from the RIGHT (trailing edge)
        // We need to show bars from right to left based on how many levels we have
        
        // Count how many non-zero levels we have
        let nonZeroCount = levels.filter { $0 > 0.001 }.count
        
        for (index, view) in waveformViews.enumerated() {
            guard index < levels.count else { break }
            
            let level = levels[index]
            
            // Show bars from the RIGHT side only
            // The rightmost bar is at index (waveformViews.count - 1)
            // We want to show the last 'nonZeroCount' bars
            let shouldShow = index >= (waveformViews.count - nonZeroCount)
            
            // Map audio level (0.0-1.0) to height (4-18px) to match BubbleVoiceView
            let minHeight: CGFloat = 4
            let maxHeight: CGFloat = 18 // 60% of 30px container height
            let height = minHeight + (CGFloat(level) * (maxHeight - minHeight))
            
            // Smooth animation for real-time waveform
            UIView.animate(withDuration: 0.15, delay: 0, options: [.curveEaseInOut, .allowUserInteraction]) {
                view.alpha = shouldShow ? 1.0 : 0.0 // Fade in from right
                view.constraints.first { $0.firstAttribute == .height }?.constant = height
                view.superview?.layoutIfNeeded()
            }
        }
    }
    
    /// Update UI based on recording state
    private func updateUIForState(_ state: RecordingState) {
        switch state {
        case .idle:
            // UI is already reset in stopRecording
            break
            
        case .recording:
            // UI is already set in startRecording
            break
            
        case .locked:
            // Ensure locked UI persists
            if !isLocked {
                lockRecording()
            }
            
        case .paused:
            // Show paused state
            isPaused = true
            redPause.alpha = 0
            redMicContinue.alpha = 1
        }
    }
    
    // REMOVED: animateWaveform() - No longer needed, using real audio levels from VoiceRecordingViewModel
}

// MARK: - Recording State Enum

// MARK: - Usage Example
class ViewController: UIViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .systemBackground
        
        let audioRecorder = AudioRecordButton()
        audioRecorder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(audioRecorder)
        
        NSLayoutConstraint.activate([
            audioRecorder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            audioRecorder.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            audioRecorder.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),
//            audioRecorder.heightAnchor.constraint(equalToConstant: 66)
        ])
    }
}

struct AudioRecordButtonView: UIViewRepresentable {
    // Callbacks
    var onStartRecording : (() -> Void)?
    var onStopRecording : (() -> Void)?
    var onSendAudio : (() -> Void)?
    var onOnceRead : (() -> Void)?
    var onPauseOrResume : ((Bool) -> Void)?
    var onLockRecording : (() -> Void)?
    
    // Bindings from VoiceRecordingViewModel
    var audioLevels: [Float] = Array(repeating: 0, count: 60) // 60 bars for full width
    var recordingState: RecordingState = .idle
    var elapsedTime: TimeInterval = 0
    
    func makeUIView(context: Context) -> AudioRecordButton {
        let button = AudioRecordButton()
        button.onOnceRead = {
            onOnceRead?()
        }
        button.onSendAudio = {
            onSendAudio?()
        }
        button.onStartRecording = {
            onStartRecording?()
        }
        button.onStopRecording = {
            onStopRecording?()
        }
        button.onPauseOrResume = { state in
            onPauseOrResume?(state)
        }
        button.onLockedAudio = {
            onLockRecording?()
        }
        return button
    }

    func updateUIView(_ uiView: AudioRecordButton, context: Context) {
        // Update audio levels for real-time waveform
        uiView.audioLevels = audioLevels
        
        // Update recording state
        uiView.recordingState = recordingState
        
        // Update time display
        let minutes = Int(elapsedTime) / 60
        let seconds = Int(elapsedTime) % 60
        let timeString = String(format: "%d:%02d", minutes, seconds)
        
        // Update both time labels (regular and locked)
        DispatchQueue.main.async {
            uiView.updateTimeLabels(with: timeString)
        }
    }
}


struct RecordViewer : View {
    @State private var isRecording : Bool = false
    let translationService: (any TranslationServiceProtocol)? = nil
    var body: some View {
        VStack{
            Spacer()
            Text(t(ChatTranslationKeys.STORIES_RECORDING_STATE, args: ["\(isRecording)"])).foregroundStyle(.white)
//            Spacer()
            AudioRecordButtonView(onStartRecording: {
                debugLog("on start recording")
            },onStopRecording: {
                debugLog("on stop recording")
            },
                                  onSendAudio: {
                debugLog("on send recording")
            },onOnceRead: {
                debugLog("on onceRead recording")
            },onPauseOrResume: { state in
                debugLog("audio recording state \(state)  ")
            }) .frame(height: 140)
        }.background(.black)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

