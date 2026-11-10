//
//  QRScannerView.swift
//  FeatureChat
//
//  Scan et paiement par QR — Bloc 3, chapitre 22.
//

import SwiftUI
import WaanguSharedUI
import AVFoundation
import AudioToolbox
import WaanguCoreKit

/// Scanne un QR financier et le fait résoudre par le backend.
///
/// > **Aucun QR n'est exécutable sans résolution serveur.**
///
/// Cette vue ne lit jamais le contenu du QR. Elle décode la charge, produit un
/// nonce, envoie les deux, et n'affiche **rien** avant la réponse. Interpréter
/// localement reviendrait à faire confiance à ce qu'on cherche à vérifier : un
/// QR est un support qu'on imprime et qu'on colle par-dessus celui d'un marchand.
///
/// Trois gardes accompagnent le scan, dans le même écran :
/// anti-rejeu par nonce, résolution obligatoire avant tout montant affiché,
/// quarantaine visuelle des charges d'origine externe.
struct QRScannerView: View {

    let resolver: any QRResolving
    /// Un QR de lien de paiement (`waangu://chat/pay-link?…`) : il désigne une
    /// demande d'argent, pas un point d'acceptation marchand. `nil` ⇒ il est
    /// traité comme n'importe quelle charge, donc refusé par `/qr/parse`.
    var onPaymentLink: ((String, String) -> Void)?
    /// Le serveur rend un devis au prepare (§5.2, Q15) : le code part tel quel à
    /// `/qr/prepare`, qui le résout. `nil` ⇒ l'ancien parcours par `/qr/parse`.
    var onPayload: ((String) -> Void)? = nil
    let onConfirm: (ResolvedQR) -> Void
    let onDismiss: () -> Void

    @State private var phase: Phase = .checkingPermission
    @State private var torchIsOn = false

    private enum Phase: Equatable {
        case checkingPermission
        case permissionDenied
        case scanning
        case resolving
        case resolved(ResolvedQR)
        case rejected(String)
    }

    private var flowIsBusy: Bool {
        false
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .checkingPermission: progress(FinanceStrings.hubLoading)
                case .permissionDenied:   permissionState
                case .scanning:           scanner
                case .resolving:          progress(FinanceStrings.qrResolving)
                case .resolved(let qr):   confirmation(qr)
                case .rejected(let m):
                    FinancePage {
                        FinanceMessage(icon: "xmark.shield", text: m)
                    } actions: {
                        CustomButton(title: FinanceStrings.flowScanAgain) { phase = .scanning }
                    }
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.qrTitle)
            .navigationBarTitleDisplayMode(.inline)
            // Barre en thème sombre **pendant le scan seulement**.
            //
            // Le flux caméra monte désormais jusque sous la barre. En thème
            // clair, le titre y est dessiné en sombre : noir sur noir, il avait
            // disparu. Les autres étapes — permission, confirmation — gardent un
            // fond normal et donc la barre du système.
            //
            // `toolbarColorScheme` plutôt que `preferredColorScheme` : le second
            // s'appliquerait à toute la feuille, y compris aux écrans clairs qui
            // suivent le scan.
            .toolbarColorScheme(phase == .scanning ? .dark : nil, for: .navigationBar)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack,
                                 // Le flux caméra occupe tout l'écran : la
                                 // pastille grise du système s'y perd.
                                 onDarkSurface: phase == .scanning,
                                 onClose: onDismiss)
        }
        .financeLoadOnce { await requestPermission() }
    }

    // MARK: - Étapes

    private func requestPermission() async {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            phase = granted ? .scanning : .permissionDenied
        default:
            phase = .permissionDenied
        }
    }

    /// La charge décodée part au backend **telle quelle**.
    private func resolve(_ payload: String) async {
        // Le passage à `.resolving` sert aussi de garde de réentrance : la
        // caméra continue de produire des trames pendant l'appel réseau, et sans
        // cela un même QR déclencherait plusieurs résolutions concurrentes.
        guard phase == .scanning else { return }
        phase = .resolving

        // Lien de paiement Waangu : rien à demander au backend QR. Le lien
        // s'inspecte (`/payment-link/inspect`) et se paie par la demande.
        if let link = PaymentLinkURL.read(payload) {
            onPaymentLink?(link.token, link.nonce)
            if onPaymentLink == nil { phase = .scanning }
            return
        }

        // Le serveur résout et chiffre au prepare : le code part, sans lecture préalable.
        if let onPayload {
            onPayload(payload)
            phase = .scanning
            return
        }

        // Un nonce neuf par tentative. Le backend refuse un nonce déjà vu :
        // c'est ce qui transforme un rejeu en refus explicite plutôt qu'en
        // second débit.
        let nonce = QRNonce.fresh()

        switch await resolver.resolve(payload: payload, nonce: nonce.value) {
        case .success(let qr):
            phase = .resolved(qr)
        case .failure(let error):
            phase = .rejected(FinanceStrings.errorMessage(error))
        }
    }

    // MARK: - Vues

    private func progress(_ label: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func message(_ icon: String, _ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(text).font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var permissionState: some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill").font(.system(size: 40)).foregroundStyle(.tertiary)
            Text(FinanceStrings.qrCameraDenied)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
            Button(FinanceStrings.qrOpenSettings) {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var scanner: some View {
        ZStack {
            QRCameraPreview { payload in
                Task { await resolve(payload) }
            }
            .ignoresSafeArea()

            QRScanReticle()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                Text(FinanceStrings.qrAimHint)
                    .font(.system(size: 15, weight: .medium))
                    // Blanc plein sur voile sombre : la capsule translucide
                    // précédente reprenait la couleur de la scène filmée, et le
                    // texte devenait illisible sur un fond clair.
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .shadow(color: .black.opacity(0.6), radius: 4)

                torchButton
                    .padding(.top, 28)
                    .padding(.bottom, 44)
            }
        }
        .background(Color.black)
        // La consigne est déjà lue par VoiceOver sur son propre texte ; la
        // reprendre ici la ferait annoncer deux fois.
        .accessibilityElement(children: .contain)
        .onDisappear { setTorch(false) }
    }

    /// Torche, parce que le voile assombrit délibérément la scène.
    ///
    /// Un code imprimé se lit mal en intérieur, et le viseur réduit encore la
    /// lumière perçue. Sans cette commande, la seule issue est de renoncer.
    ///
    /// Absente quand l'appareil n'a pas de torche — un simulateur, un iPad —
    /// plutôt que présente et sans effet.
    @ViewBuilder
    private var torchButton: some View {
        if Self.hasTorch {
            Button {
                torchIsOn.toggle()
                setTorch(torchIsOn)
            } label: {
                Image(systemName: torchIsOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(torchIsOn ? AppColors.primary : Color.white)
                    .frame(width: 52, height: 52)
                    .background(torchIsOn ? Color.white : AppColors.primary, in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.4), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FinanceStrings.qrTorch)
            .accessibilityValue(torchIsOn ? FinanceStrings.qrTorchOn : FinanceStrings.qrTorchOff)
        }
    }

    private static var hasTorch: Bool {
        AVCaptureDevice.default(for: .video)?.hasTorch ?? false
    }

    /// Échec silencieux **volontaire** : l'appareil peut refuser le verrou —
    /// caméra saisie par un autre processus, surchauffe. Le scan reste possible,
    /// et une alerte pour une lampe interromprait un paiement pour rien.
    private func setTorch(_ on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        guard (try? device.lockForConfiguration()) != nil else { return }
        device.torchMode = on ? .on : .off
        device.unlockForConfiguration()
    }

    /// L'écran de confirmation — **rien n'y est affiché avant la résolution**.
    private func confirmation(_ qr: ResolvedQR) -> some View {
        Form {
            // La quarantaine passe en premier : c'est ce que l'utilisateur doit
            // lire avant de regarder le montant.
            if qr.requiresQuarantineWarning {
                Section {
                    Label(FinanceStrings.qrQuarantine, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                HStack(spacing: 12) {
                    Image(systemName: qr.kind == .merchant ? "storefront" : "person.crop.circle")
                        .font(.system(size: 34)).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Text(qr.counterparty.displayName).font(.body.weight(.medium))
                            if qr.counterparty.verification.showsTrustBadge {
                                Image(systemName: "checkmark.seal.fill")
                                    .font(.caption).foregroundStyle(AppColors.primary)
                            }
                        }
                        if qr.counterparty.verification.warrantsWarning {
                            Text(FinanceStrings.recipientUnverified)
                                .font(.caption).foregroundStyle(AppColors.statusWarning)
                        }
                    }
                }
                .accessibilityElement(children: .combine)
            }

            // Le montant vient du backend, ou n'existe pas — un QR statique
            // laisse le payeur saisir. Jamais lu dans la charge.
            if let amount = qr.amount, let currency = qr.currency {
                Section(FinanceStrings.amount) {
                    Text(AmountEntry.format(amount, currency)).font(.title3.weight(.semibold))
                }
            }

            if qr.isExpired() {
                Section {
                    Label(FinanceStrings.qrExpired, systemImage: "clock.badge.xmark")
                        .font(.caption).foregroundStyle(AppColors.statusWarning)
                }
            }

            Section {
                CustomButton(title: FinanceStrings.qrContinue) {
                    onConfirm(qr)
                }
                // Périmé, révoqué, ou sans action de paiement rendue par le
                // backend : les trois ferment le bouton ensemble.
                .disabled(!qr.allowsPayment())
                .financeActionRow()
            } footer: {
                if !qr.allowsPayment() {
                    Text(FinanceStrings.qrNotPayable).font(.caption)
                }
            }
        }
    }
}

// MARK: - Aperçu caméra

/// Enveloppe `AVCaptureSession` et ne remonte que la charge décodée.
///
/// La vue SwiftUI ne voit jamais la session : lui donner accès inviterait à
/// interroger la caméra depuis le rendu, et à manipuler une session sur le fil
/// principal.
/// Partagé avec Waangu Copilot, qui scanne dans le fil.
struct QRCameraPreview: UIViewControllerRepresentable {

    let onPayload: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerController {
        let controller = QRScannerController()
        controller.onPayload = onPayload
        return controller
    }

    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onPayload: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?

    /// Empêche qu'une même charge parte deux fois pendant que la résolution est
    /// en vol : la caméra continue de produire des trames.
    private var hasEmitted = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasEmitted = false
        startSession()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // La caméra s'arrête dès que l'écran part. Une session laissée active
        // filme en arrière-plan de l'application et vide la batterie.
        if session.isRunning {
            Task.detached { [session] in session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }

        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        output.setMetadataObjectsDelegate(self, queue: .main)
        // QR seulement. Accepter les codes-barres linéaires ouvrirait la porte à
        // des charges qu'aucun contrat financier ne décrit.
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        preview = layer
    }

    private func startSession() {
        guard !session.isRunning else { return }
        // `startRunning` bloque : jamais sur le fil principal.
        Task.detached { [session] in session.startRunning() }
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasEmitted,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let payload = object.stringValue,
              !payload.isEmpty else { return }

        hasEmitted = true
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onPayload?(payload)
    }
}
