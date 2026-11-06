import UIKit
import AVFoundation
import WaanguCoreKit

// MARK: - Camera Delegate Protocol
protocol CameraViewControllerDelegate: AnyObject {
    func didCaptureMedia(_ media: MediaType, caption: String)
    func didDismissCamera()
}

class CameraViewController: UIViewController {
    
    // MARK: - Properties
    weak var delegate: CameraViewControllerDelegate?
    /// Changing this is a **UI-only** change: both outputs are already attached
    /// to the session, so photo↔video costs no session reconfiguration.
    var cameraMode: CameraMode = .both {
        didSet {
            guard oldValue != cameraMode, isViewLoaded else { return }
            applyMode()
        }
    }

    /// All session configuration and start/stop happens here. `AVCaptureSession`
    /// calls block, and `startRunning()` in particular can take seconds.
    private let sessionQueue = DispatchQueue(label: "com.waangu.stories.camera.session")
    private var isSessionConfigured = false

    private var captureSession: AVCaptureSession?
    private var videoPreviewLayer: AVCaptureVideoPreviewLayer?
    private var photoOutput: AVCapturePhotoOutput?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var currentCameraPosition: AVCaptureDevice.Position = .back
    private var isRecording = false
    private var recordingTimer: Timer?
    private var recordingDuration: TimeInterval = 0
    
    // MARK: - UI Elements
    private let closeButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let flashButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let captureButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 35
        btn.layer.borderWidth = 4
        btn.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    /// The red record button inside the shutter.
    ///
    /// Idle in video mode it very nearly fills the shutter, leaving only the
    /// white rim visible; while recording it shrinks to a rounded square. This
    /// is the only thing that tells photo mode and video mode apart, so it is
    /// never white-on-white and never small enough to miss.
    private let videoModeIndicator: UIView = {
        let view = UIView()
        view.backgroundColor = .systemRed
        view.layer.cornerRadius = Layout.recordIdleSize / 2
        view.alpha = 0
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private enum Layout {
        static let shutterSize: CGFloat = 70
        /// Leaves just the shutter's 4pt rim showing.
        static let recordIdleSize: CGFloat = 60
        static let recordingSize: CGFloat = 28
        static let recordingCornerRadius: CGFloat = 6
    }

    private var indicatorWidth: NSLayoutConstraint?
    private var indicatorHeight: NSLayoutConstraint?
    
    private let switchCameraButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.setImage(UIImage(systemName: "arrow.triangle.2.circlepath.camera"), for: .normal)
        btn.tintColor = .white
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let galleryButton: UIButton = {
        let btn = UIButton(type: .system)
        btn.backgroundColor = .white
        btn.layer.cornerRadius = 8
        btn.layer.borderWidth = 2
        btn.layer.borderColor = UIColor.white.cgColor
        btn.translatesAutoresizingMaskIntoConstraints = false
        return btn
    }()
    
    private let recordingTimeLabel: UILabel = {
        let lbl = UILabel()
        lbl.text = "0:00"
        lbl.textColor = .white
        lbl.font = .systemFont(ofSize: 14, weight: .medium)
        lbl.isHidden = true
        lbl.translatesAutoresizingMaskIntoConstraints = false
        return lbl
    }()
    
    private let recordingDot: UIView = {
        let view = UIView()
        view.backgroundColor = .red
        view.layer.cornerRadius = 4
        view.isHidden = true
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()
    
    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupCamera()
        setupActions()
        applyMode(animated: false)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // The preview layer does not auto-resize; without this it keeps the
        // bounds it was given before the first layout pass.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        videoPreviewLayer?.frame = view.bounds
        CATransaction.commit()
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, !session.isRunning else { return }
            session.startRunning()
        }
    }

    private func stopSession() {
        sessionQueue.async { [weak self] in
            guard let session = self?.captureSession, session.isRunning else { return }
            session.stopRunning()
        }
    }
    
    // MARK: - Setup
    private func setupUI() {
        view.backgroundColor = .black
        
        view.addSubview(closeButton)
        view.addSubview(flashButton)
        view.addSubview(captureButton)
        view.addSubview(videoModeIndicator)
        view.addSubview(switchCameraButton)
        view.addSubview(galleryButton)
        view.addSubview(recordingTimeLabel)
        view.addSubview(recordingDot)
        
        NSLayoutConstraint.activate([
            // Close button
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Flash button
            flashButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            flashButton.widthAnchor.constraint(equalToConstant: 44),
            flashButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Recording dot
            recordingDot.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            recordingDot.centerXAnchor.constraint(equalTo: view.centerXAnchor, constant: -30),
            recordingDot.widthAnchor.constraint(equalToConstant: 8),
            recordingDot.heightAnchor.constraint(equalToConstant: 8),
            
            // Recording time
            recordingTimeLabel.centerYAnchor.constraint(equalTo: recordingDot.centerYAnchor),
            recordingTimeLabel.leadingAnchor.constraint(equalTo: recordingDot.trailingAnchor, constant: 8),
            
            // Capture button
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.widthAnchor.constraint(equalToConstant: Layout.shutterSize),
            captureButton.heightAnchor.constraint(equalToConstant: Layout.shutterSize),
            
            // Video mode indicator
            videoModeIndicator.centerXAnchor.constraint(equalTo: captureButton.centerXAnchor),
            videoModeIndicator.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            
            // Switch camera
            switchCameraButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            switchCameraButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -30),
            switchCameraButton.widthAnchor.constraint(equalToConstant: 44),
            switchCameraButton.heightAnchor.constraint(equalToConstant: 44),
            
            // Gallery button
            galleryButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor),
            galleryButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 30),
            galleryButton.widthAnchor.constraint(equalToConstant: 44),
            galleryButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let width = videoModeIndicator.widthAnchor.constraint(equalToConstant: Layout.recordIdleSize)
        let height = videoModeIndicator.heightAnchor.constraint(equalToConstant: Layout.recordIdleSize)
        NSLayoutConstraint.activate([width, height])
        indicatorWidth = width
        indicatorHeight = height
    }
    
    private func setupCamera() {
        guard !isSessionConfigured else { return }

        let session = AVCaptureSession()
        session.sessionPreset = .photo
        captureSession = session

        // The preview layer is a UI object: main thread, before the session starts.
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        videoPreviewLayer = previewLayer

        sessionQueue.async { [weak self] in
            guard let self else { return }

            guard let backCamera = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: .back
                  ),
                  let input = try? AVCaptureDeviceInput(device: backCamera) else {
                return
            }

            session.beginConfiguration()

            if session.canAddInput(input) {
                session.addInput(input)
            }

            let photo = AVCapturePhotoOutput()
            if session.canAddOutput(photo) {
                session.addOutput(photo)
                self.photoOutput = photo
            }

            let movie = AVCaptureMovieFileOutput()
            if session.canAddOutput(movie) {
                session.addOutput(movie)
                self.movieOutput = movie
            }

            session.commitConfiguration()

            self.isSessionConfigured = true
            session.startRunning()
        }
    }

    /// Mode affects only the shutter's appearance and behaviour — never the session.
    ///
    /// `animated` is false for the initial pass in `viewDidLoad`, where there is
    /// nothing to animate from.
    private func applyMode(animated: Bool = true) {
        let showsRecordButton = cameraMode != .photo

        // Leaving video mode mid-recording would otherwise strand the button in
        // its recording shape.
        if !isRecording {
            setIndicator(recording: false, animated: false)
        }

        let changes = {
            self.videoModeIndicator.alpha = showsRecordButton ? 1 : 0
            self.videoModeIndicator.transform = showsRecordButton
                ? .identity
                : CGAffineTransform(scaleX: 0.4, y: 0.4)
        }

        guard animated else { return changes() }

        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.72,
            initialSpringVelocity: 0.4,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }

    /// Circle when idle, rounded square while recording.
    private func setIndicator(recording: Bool, animated: Bool) {
        let size = recording ? Layout.recordingSize : Layout.recordIdleSize
        let radius = recording ? Layout.recordingCornerRadius : Layout.recordIdleSize / 2

        indicatorWidth?.constant = size
        indicatorHeight?.constant = size

        let changes = {
            self.videoModeIndicator.layer.cornerRadius = radius
            self.view.layoutIfNeeded()
        }

        guard animated else { return changes() }

        UIView.animate(
            withDuration: 0.24,
            delay: 0,
            usingSpringWithDamping: 0.75,
            initialSpringVelocity: 0.3,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: changes
        )
    }
    
    private func setupActions() {
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
        switchCameraButton.addTarget(self, action: #selector(switchCamera), for: .touchUpInside)
        
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(captureButtonLongPressed))
        longPress.minimumPressDuration = 0.5
        captureButton.addGestureRecognizer(longPress)
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(captureButtonTapped))
        captureButton.addGestureRecognizer(tap)
    }
    
    // MARK: - Actions
//    @objc private func closeTapped() {
//        dismiss(animated: true)
//        print("cloes camera triggered")
//
//    }
    @objc private func closeTapped() {
        dismiss(animated: true) { [weak self] in
            self?.delegate?.didDismissCamera()
        }
        debugLog("close camera triggered")
    }
    
    @objc private func flashTapped() {
        // Toggle flash mode
        let currentImage = flashButton.currentImage
        if currentImage == UIImage(systemName: "bolt.slash.fill") {
            flashButton.setImage(UIImage(systemName: "bolt.fill"), for: .normal)
        } else {
            flashButton.setImage(UIImage(systemName: "bolt.slash.fill"), for: .normal)
        }
    }
    
    @objc private func switchCamera() {
        sessionQueue.async { [weak self] in
            guard let self, let session = self.captureSession else { return }

            let newPosition: AVCaptureDevice.Position =
                self.currentCameraPosition == .back ? .front : .back

            guard let newCamera = AVCaptureDevice.default(
                    .builtInWideAngleCamera, for: .video, position: newPosition
                  ),
                  let newInput = try? AVCaptureDeviceInput(device: newCamera) else {
                return
            }

            session.beginConfiguration()

            if let currentInput = session.inputs.first as? AVCaptureDeviceInput {
                session.removeInput(currentInput)
            }

            if session.canAddInput(newInput) {
                session.addInput(newInput)
                self.currentCameraPosition = newPosition
            } else if let restored = session.inputs.first as? AVCaptureDeviceInput {
                // Adding failed — leave the session in a usable state.
                session.addInput(restored)
            }

            session.commitConfiguration()
        }
    }
    
    @objc private func captureButtonTapped() {
        // In video mode a tap is not a shutter press.
        guard cameraMode != .video else { return }
        guard let photoOutput = photoOutput else { return }
        
        let settings = AVCapturePhotoSettings()
//        photoOutput.capturePhoto(with: settings, delegate: self)
        
        // Animate capture
        UIView.animate(withDuration: 0.1, animations: {
            self.captureButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }) { _ in
            UIView.animate(withDuration: 0.1) {
                self.captureButton.transform = .identity
            }
        }
    }
    
    @objc private func captureButtonLongPressed(_ gesture: UILongPressGestureRecognizer) {
        // Holding the shutter in photo mode must not start a recording.
        guard cameraMode != .photo else { return }

        switch gesture.state {
        case .began:
            startVideoRecording()
        case .ended, .cancelled:
            stopVideoRecording()
        default:
            break
        }
    }
    
    private func startVideoRecording() {
        guard let movieOutput = movieOutput, !isRecording else { return }
        
        isRecording = true
        recordingDuration = 0
        recordingDot.isHidden = false
        recordingTimeLabel.isHidden = false
        
        // Big red circle -> small rounded square: the standard "recording, tap
        // to stop" cue. The shutter itself stays put.
        setIndicator(recording: true, animated: true)
        
        // Start recording
        let outputPath = NSTemporaryDirectory() + "video.mov"
        let outputURL = URL(fileURLWithPath: outputPath)
        
        if FileManager.default.fileExists(atPath: outputPath) {
            try? FileManager.default.removeItem(atPath: outputPath)
        }
        
//        movieOutput.startRecording(to: outputURL, recordingDelegate: self)
        
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.recordingDuration += 1
            self?.updateRecordingTime()
        }
    }
    
    private func stopVideoRecording() {
        guard isRecording else { return }
        
        isRecording = false
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDot.isHidden = true
        recordingTimeLabel.isHidden = true
        
        setIndicator(recording: false, animated: true)
        
        movieOutput?.stopRecording()
    }
    
    private func updateRecordingTime() {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        recordingTimeLabel.text = String(format: "%d:%02d", minutes, seconds)
    }
}

//// MARK: - AVCapturePhotoCaptureDelegate
//extension CameraViewController: AVCapturePhotoCaptureDelegate {
//    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
//        guard let imageData = photo.fileDataRepresentation(),
//              let image = UIImage(data: imageData) else { return }
//        
//        // Navigate to preview controller
//        let previewVC = MediaPreviewViewController(media: .photo(image))
//        previewVC.modalPresentationStyle = .fullScreen
//        present(previewVC, animated: true)
//    }
//}
//
//// MARK: - AVCaptureFileOutputRecordingDelegate
//extension CameraViewController: AVCaptureFileOutputRecordingDelegate {
//    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
//        if error == nil {
//            let previewVC = MediaPreviewViewController(media: .video(outputFileURL))
//            previewVC.modalPresentationStyle = .fullScreen
//            present(previewVC, animated: true)
//        }
//    }
//}
