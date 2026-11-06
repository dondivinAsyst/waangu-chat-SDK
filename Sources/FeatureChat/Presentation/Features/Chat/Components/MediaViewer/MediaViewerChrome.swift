import UIKit

/// Header and footer overlay for the media viewer.
///
/// Pass-through hit testing: taps that miss a control reach the page underneath,
/// so single-tap-to-toggle still works anywhere on screen.
final class MediaViewerChrome: UIView {

    private let header = UIView()
    private let footer = UIView()

    private let closeButton = UIButton(type: .system)
    private let counterLabel = UILabel()
    private let senderLabel = UILabel()
    private let timeLabel = UILabel()
    private let captionLabel = UILabel()
    private let shareButton = UIButton(type: .system)
    private let deleteButton = UIButton(type: .system)

    var onClose: (() -> Void)?
    var onShare: (() -> Void)?
    var onDelete: (() -> Void)?

    /// Read by the viewer to keep a video's scrubber clear of these controls.
    /// Measured rather than assumed, because a caption grows the footer by up to
    /// three lines.
    var footerHeight: CGFloat {
        // The caller runs in the controller's layout pass, which has not
        // necessarily reached this view's own subviews yet.
        layoutIfNeeded()
        return footer.bounds.height
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaViewerChrome is created in code only")
    }

    /// Returning nil for hits on the chrome's own background lets taps fall
    /// through to the page, which owns the tap-to-toggle gesture.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === header || hit === footer { return nil }
        return hit
    }

    private func setUpViews() {
        backgroundColor = .clear

        header.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(footer)

        configureCircleButton(closeButton, systemName: "xmark", action: #selector(handleClose))
        configureCircleButton(shareButton, systemName: "square.and.arrow.up", action: #selector(handleShare))
        configureCircleButton(deleteButton, systemName: "trash", action: #selector(handleDelete))

        counterLabel.textColor = .white
        counterLabel.font = .systemFont(ofSize: 14, weight: .medium)
        counterLabel.textAlignment = .center
        counterLabel.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        counterLabel.layer.cornerRadius = 12
        counterLabel.layer.masksToBounds = true
        counterLabel.translatesAutoresizingMaskIntoConstraints = false

        senderLabel.textColor = .white
        senderLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        senderLabel.textAlignment = .center
        senderLabel.translatesAutoresizingMaskIntoConstraints = false

        timeLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        timeLabel.font = .systemFont(ofSize: 12)
        timeLabel.textAlignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false

        captionLabel.textColor = .white
        captionLabel.font = .systemFont(ofSize: 15)
        captionLabel.numberOfLines = 3
        captionLabel.translatesAutoresizingMaskIntoConstraints = false

        header.addSubview(closeButton)
        header.addSubview(counterLabel)
        footer.addSubview(captionLabel)
        footer.addSubview(shareButton)
        footer.addSubview(senderLabel)
        footer.addSubview(timeLabel)
        footer.addSubview(deleteButton)

        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: leadingAnchor),
            header.trailingAnchor.constraint(equalTo: trailingAnchor),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor),
            header.heightAnchor.constraint(equalToConstant: 56),

            closeButton.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 16),
            closeButton.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            counterLabel.centerXAnchor.constraint(equalTo: header.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            counterLabel.heightAnchor.constraint(equalToConstant: 24),
            counterLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 56),

            footer.leadingAnchor.constraint(equalTo: leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),

            captionLabel.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            captionLabel.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            captionLabel.topAnchor.constraint(equalTo: footer.topAnchor, constant: 12),

            shareButton.leadingAnchor.constraint(equalTo: footer.leadingAnchor, constant: 16),
            shareButton.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 12),
            shareButton.bottomAnchor.constraint(equalTo: footer.bottomAnchor, constant: -12),

            deleteButton.trailingAnchor.constraint(equalTo: footer.trailingAnchor, constant: -16),
            deleteButton.centerYAnchor.constraint(equalTo: shareButton.centerYAnchor),

            senderLabel.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            senderLabel.topAnchor.constraint(equalTo: captionLabel.bottomAnchor, constant: 12),

            timeLabel.centerXAnchor.constraint(equalTo: footer.centerXAnchor),
            timeLabel.topAnchor.constraint(equalTo: senderLabel.bottomAnchor, constant: 2)
        ])
    }

    private func configureCircleButton(_ button: UIButton, systemName: String, action: Selector) {
        button.setImage(UIImage(systemName: systemName), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        button.layer.cornerRadius = 20
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 40).isActive = true
        button.heightAnchor.constraint(equalToConstant: 40).isActive = true
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    /// Sender and time come from the item. The previous carousel kept these in
    /// `@State` vars it never assigned, so its footer always rendered blank.
    func configure(item: MediaViewerItem, index: Int, total: Int) {
        counterLabel.text = "  \(index + 1)/\(total)  "
        senderLabel.text = item.senderName
        timeLabel.text = item.displayTime
        captionLabel.text = item.caption
        captionLabel.isHidden = item.caption.isEmpty
    }

    func setVisible(_ visible: Bool, animated: Bool) {
        let apply = { self.alpha = visible ? 1 : 0 }
        guard animated else { return apply() }
        UIView.animate(withDuration: 0.2, animations: apply)
    }

    @objc private func handleClose() { onClose?() }
    @objc private func handleShare() { onShare?() }
    @objc private func handleDelete() { onDelete?() }
}
