//import UIKit
//import AVFoundation
//import AVKit
//
//enum MediaType {
//    case photo(UIImage)
//    case video(URL)
//}
//
//protocol MediaPreviewDelegate: AnyObject {
//    func didSendMedia(_ media: MediaType, caption: String)
//}
//
//class MediaPreviewViewController: UIViewController {
//    
//    // MARK: - Properties
//    weak var delegate: MediaPreviewDelegate?
//    private let media: MediaType
//    private var player: AVPlayer?
//    private var playerLayer: AVPlayerLayer?
//    
//    // MARK: - UI Elements
//    private let scrollView: UIScrollView = {
//        let sv = UIScrollView()
//        sv.backgroundColor = .black
//        sv.minimumZoomScale = 1.0
//        sv.maximumZoomScale = 3.0
//        sv.translatesAutoresizingMaskIntoConstraints = false
//        return sv
//    }()
//    
//    private let imageView: UIImageView = {
//        let iv = UIImageView()
//        iv.contentMode = .scaleAspectFit
//        iv.translatesAutoresizingMaskIntoConstraints = false
//        return iv
//    }()
//    
//    private let videoContainerView: UIView = {
//        let view = UIView()
//        view.backgroundColor = .black
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let playButton: UIButton = {
//        let btn = UIButton(type: .system)
//        let config = UIImage.SymbolConfiguration(pointSize: 50, weight: .regular)
//        btn.setImage(UIImage(systemName: "play.circle.fill", withConfiguration: config), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let topBarView: UIView = {
//        let view = UIView()
//        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let closeButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.setImage(UIImage(systemName: "xmark"), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let cropButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.setImage(UIImage(systemName: "crop"), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let emojiButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.setImage(UIImage(systemName: "face.smiling"), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let textButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.setImage(UIImage(systemName: "textformat"), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let penButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.setImage(UIImage(systemName: "pencil.tip"), for: .normal)
//        btn.tintColor = .white
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    private let bottomBarView: UIView = {
//        let view = UIView()
//        view.backgroundColor = UIColor.black.withAlphaComponent(0.5)
//        view.translatesAutoresizingMaskIntoConstraints = false
//        return view
//    }()
//    
//    private let captionTextField: UITextField = {
//        let tf = UITextField()
//        tf.placeholder = "Add a caption..."
//        tf.textColor = .white
//        tf.attributedPlaceholder = NSAttributedString(
//            string: "Add a caption...",
//            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.6)]
//        )
//        tf.font = .systemFont(ofSize: 16)
//        tf.translatesAutoresizingMaskIntoConstraints = false
//        return tf
//    }()
//    
//    private let sendButton: UIButton = {
//        let btn = UIButton(type: .system)
//        btn.backgroundColor = UIColor(red: 0.15, green: 0.78, blue: 0.45, alpha: 1.0) // WhatsApp green
//        btn.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
//        btn.tintColor = .white
//        btn.layer.cornerRadius = 25
//        btn.translatesAutoresizingMaskIntoConstraints = false
//        return btn
//    }()
//    
//    // MARK: - Init
//    init(media: MediaType) {
//        self.media = media
//        super.init(nibName: nil, bundle: nil)
//    }
//    
//    required init?(coder: NSCoder) {
//        fatalError("init(coder:) has not been implemented")
//    }
//    
//    // MARK: - Lifecycle
//    override func viewDidLoad() {
//        super.viewDidLoad()
//        setupUI()
//        setupActions()
//        configureMedia()
//    }
//    
//    override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        player?.pause()
//    }
//    
//    // MARK: - Setup
//    private func setupUI() {
//        view.backgroundColor = .black
//        
//        view.addSubview(scrollView)
//        scrollView.addSubview(imageView)
//        view.addSubview(videoContainerView)
//        view.addSubview(playButton)
//        view.addSubview(topBarView)
//        view.addSubview(bottomBarView)
//        
//        topBarView.addSubview(closeButton)
//        topBarView.addSubview(cropButton)
//        topBarView.addSubview(emojiButton)
//        topBarView.addSubview(textButton)
//        topBarView.addSubview(penButton)
//        
//        bottomBarView.addSubview(captionTextField)
//        bottomBarView.addSubview(sendButton)
//        
//        scrollView.delegate = self
//        
//        NSLayoutConstraint.activate([
//            // Scroll view
//            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
//            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            
//            // Image view
//            imageView.topAnchor.constraint(equalTo: scrollView.topAnchor),
//            imageView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
//            imageView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
//            imageView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
//            imageView.widthAnchor.constraint(equalTo: scrollView.widthAnchor),
//            imageView.heightAnchor.constraint(equalTo: scrollView.heightAnchor),
//            
//            // Video container
//            videoContainerView.topAnchor.constraint(equalTo: view.topAnchor),
//            videoContainerView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            videoContainerView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            videoContainerView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            
//            // Play button
//            playButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
//            playButton.centerYAnchor.constraint(equalTo: view.centerYAnchor),
//            playButton.widthAnchor.constraint(equalToConstant: 70),
//            playButton.heightAnchor.constraint(equalToConstant: 70),
//            
//            // Top bar
//            topBarView.topAnchor.constraint(equalTo: view.topAnchor),
//            topBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            topBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            topBarView.heightAnchor.constraint(equalToConstant: 100),
//            
//            // Close button
//            closeButton.leadingAnchor.constraint(equalTo: topBarView.leadingAnchor, constant: 16),
//            closeButton.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -16),
//            closeButton.widthAnchor.constraint(equalToConstant: 44),
//            closeButton.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Crop button
//            cropButton.trailingAnchor.constraint(equalTo: topBarView.trailingAnchor, constant: -16),
//            cropButton.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -16),
//            cropButton.widthAnchor.constraint(equalToConstant: 44),
//            cropButton.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Emoji button
//            emojiButton.trailingAnchor.constraint(equalTo: cropButton.leadingAnchor, constant: -12),
//            emojiButton.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -16),
//            emojiButton.widthAnchor.constraint(equalToConstant: 44),
//            emojiButton.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Text button
//            textButton.trailingAnchor.constraint(equalTo: emojiButton.leadingAnchor, constant: -12),
//            textButton.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -16),
//            textButton.widthAnchor.constraint(equalToConstant: 44),
//            textButton.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Pen button
//            penButton.trailingAnchor.constraint(equalTo: textButton.leadingAnchor, constant: -12),
//            penButton.bottomAnchor.constraint(equalTo: topBarView.bottomAnchor, constant: -16),
//            penButton.widthAnchor.constraint(equalToConstant: 44),
//            penButton.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Bottom bar
//            bottomBarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
//            bottomBarView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
//            bottomBarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
//            bottomBarView.heightAnchor.constraint(equalToConstant: 100),
//            
//            // Caption text field
//            captionTextField.leadingAnchor.constraint(equalTo: bottomBarView.leadingAnchor, constant: 16),
//            captionTextField.trailingAnchor.constraint(equalTo: sendButton.leadingAnchor, constant: -12),
//            captionTextField.topAnchor.constraint(equalTo: bottomBarView.topAnchor, constant: 16),
//            captionTextField.heightAnchor.constraint(equalToConstant: 44),
//            
//            // Send button
//            sendButton.trailingAnchor.constraint(equalTo: bottomBarView.trailingAnchor, constant: -16),
//            sendButton.centerYAnchor.constraint(equalTo: captionTextField.centerYAnchor),
//            sendButton.widthAnchor.constraint(equalToConstant: 50),
//            sendButton.heightAnchor.constraint(equalToConstant: 50),
//        ])
//    }
//    
//    private func setupActions() {
//        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
//        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)
//        playButton.addTarget(self, action: #selector(playVideo), for: .touchUpInside)
//        cropButton.addTarget(self, action: #selector(cropTapped), for: .touchUpInside)
//        emojiButton.addTarget(self, action: #selector(emojiTapped), for: .touchUpInside)
//        textButton.addTarget(self, action: #selector(textTapped), for: .touchUpInside)
//        penButton.addTarget(self, action: #selector(penTapped), for: .touchUpInside)
//        
//        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
//        doubleTap.numberOfTapsRequired = 2
//        scrollView.addGestureRecognizer(doubleTap)
//    }
//    
//    private func configureMedia() {
//        switch media {
//        case .photo(let image):
//            imageView.image = image
//            scrollView.isHidden = false
//            videoContainerView.isHidden = true
//            playButton.isHidden = true
//            
//        case .video(let url):
//            scrollView.isHidden = true
//            videoContainerView.isHidden = false
//            playButton.isHidden = false
//            setupVideoPlayer(with: url)
//        }
//    }
//    
//    private func setupVideoPlayer(with url: URL) {
//        player = AVPlayer(url: url)
//        playerLayer = AVPlayerLayer(player: player)
//        playerLayer?.frame = videoContainerView.bounds
//        playerLayer?.videoGravity = .resizeAspect
//        
//        if let playerLayer = playerLayer {
//            videoContainerView.layer.addSublayer(playerLayer)
//        }
//        
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(videoDidEnd),
//            name: .AVPlayerItemDidPlayToEndTime,
//            object: player?.currentItem
//        )
//    }
//    
//    override func viewDidLayoutSubviews() {
//        super.viewDidLayoutSubviews()
//        playerLayer?.frame = videoContainerView.bounds
//    }
//    
//    // MARK: - Actions
//    @objc private func closeTapped() {
//        dismiss(animated: true)
//    }
//    
//    @objc private func sendTapped() {
//        // Handle send action
//        let caption = captionTextField.text ?? ""
//        print("Sending media with caption: \(caption)")
//        
//        // Animate send button
//        UIView.animate(withDuration: 0.1, animations: {
//            self.sendButton.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
//        }) { _ in
//            UIView.animate(withDuration: 0.1) {
//                self.sendButton.transform = .identity
//            } completion: { _ in
//                // Dismiss both this view and the camera view
//                self.view.window?.rootViewController?.dismiss(animated: true)
//            }
//        }
//    }
//    
//    @objc private func playVideo() {
//        player?.play()
//        playButton.isHidden = true
//    }
//    
//    @objc private func videoDidEnd() {
//        player?.seek(to: .zero)
//        playButton.isHidden = false
//    }
//    
//    @objc private func cropTapped() {
//        print("Crop tapped")
//        // Implement crop functionality
//    }
//    
//    @objc private func emojiTapped() {
//        print("Emoji tapped")
//        // Implement emoji/sticker functionality
//    }
//    
//    @objc private func textTapped() {
//        print("Text tapped")
//        // Implement text overlay functionality
//    }
//    
//    @objc private func penTapped() {
//        print("Pen tapped")
//        // Implement drawing functionality
//    }
//    
//    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
//        if scrollView.zoomScale == 1 {
//            let location = gesture.location(in: imageView)
//            let rect = CGRect(x: location.x - 50, y: location.y - 50, width: 100, height: 100)
//            scrollView.zoom(to: rect, animated: true)
//        } else {
//            scrollView.setZoomScale(1, animated: true)
//        }
//    }
//    
//    deinit {
//        NotificationCenter.default.removeObserver(self)
//    }
//}
//
//// MARK: - UIScrollViewDelegate
//extension MediaPreviewViewController: UIScrollViewDelegate {
//    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
//        return imageView
//    }
//    
//    func scrollViewDidZoom(_ scrollView: UIScrollView) {
//        let offsetX = max((scrollView.bounds.width - scrollView.contentSize.width) * 0.5, 0)
//        let offsetY = max((scrollView.bounds.height - scrollView.contentSize.height) * 0.5, 0)
//        scrollView.contentInset = UIEdgeInsets(top: offsetY, left: offsetX, bottom: offsetY, right: offsetX)
//    }
//}
