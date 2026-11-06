//
//  ReactionLottieStickerView.swift
//
//  Telegram-style reaction sticker: looping Lottie emoji sticker per reaction.
//

import SwiftUI
import Lottie
import WaanguSharedUI

private enum ReactionLottieAssets {
    static func animation(named assetName: String) -> LottieAnimation? {
        if let animation = LottieAnimation.named(assetName, bundle: .module) {
            return animation
        }
        return LottieAnimation.named(assetName, bundle: .module, subdirectory: "Reactions")
    }
}

/// Loops a bundled Lottie sticker, constrained to the picker cell size.
private struct ReactionLottiePlaybackView: UIViewRepresentable {
    let assetName: String
    var burstTrigger: Int = 0

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 36, height: 36)))
        container.clipsToBounds = true
        container.backgroundColor = .clear
        container.isUserInteractionEnabled = false

        let lottieView = LottieAnimationView(animation: ReactionLottieAssets.animation(named: assetName))
        lottieView.translatesAutoresizingMaskIntoConstraints = false
        lottieView.contentMode = .scaleAspectFit
        lottieView.backgroundBehavior = .pauseAndRestore
        lottieView.loopMode = .loop
        lottieView.isUserInteractionEnabled = false
        container.addSubview(lottieView)

        NSLayoutConstraint.activate([
            lottieView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            lottieView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            lottieView.topAnchor.constraint(equalTo: container.topAnchor),
            lottieView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        lottieView.play()
        context.coordinator.lottieView = lottieView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard burstTrigger != context.coordinator.lastBurstTrigger,
              let lottieView = context.coordinator.lottieView else { return }
        context.coordinator.lastBurstTrigger = burstTrigger

        lottieView.loopMode = .playOnce
        lottieView.animationSpeed = 1.35
        lottieView.play(fromProgress: 0, toProgress: 1) { finished in
            guard finished else { return }
            lottieView.loopMode = .loop
            lottieView.animationSpeed = 1.0
            lottieView.play()
        }
    }

    @available(iOS 16.0, *)
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UIView, context: Context) -> CGSize? {
        CGSize(width: 36, height: 36)
    }

    final class Coordinator {
        var lottieView: LottieAnimationView?
        var lastBurstTrigger = 0
    }
}

/// One reaction cell: animated Lottie emoji sticker, staggered entrance, tap burst.
struct ReactionLottieStickerView: View {
    static let stickerSize: CGFloat = 36

    let reaction: Reaction
    let entranceIndex: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var appeared = false
    @State private var burstTrigger = 0

    private var entranceAnimation: Animation {
        .spring(response: 0.38, dampingFraction: 0.62)
            .delay(0.035 * Double(entranceIndex))
    }

    var body: some View {
        Button {
            Haptic.impact(.medium)
            burstTrigger += 1
            onTap()
        } label: {
            Group {
                if let asset = reaction.lottieAssetName {
                    ReactionLottiePlaybackView(assetName: asset, burstTrigger: burstTrigger)
                }
            }
            .frame(width: Self.stickerSize, height: Self.stickerSize)
            .clipped()
            .background {
                if isSelected {
                    Circle()
                        .fill(Color(.systemGray5))
                        .overlay {
                            Circle()
                                .stroke(AppColors.primary.opacity(0.55), lineWidth: 2)
                        }
                }
            }
            .scaleEffect(appeared ? 1 : 0.01)
            .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(.plain)
        .frame(width: Self.stickerSize, height: Self.stickerSize)
        .onAppear {
            withAnimation(entranceAnimation) {
                appeared = true
            }
        }
    }
}

/// Static + button — no Lottie, no idle motion.
struct ReactionMoreButton: View {
    let entranceIndex: Int
    let onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        Button {
            Haptic.impact(.medium)
            onTap()
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .background(Color(.systemGray5))
                .clipShape(Circle())
                .scaleEffect(appeared ? 1 : 0.01)
                .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.72).delay(0.035 * Double(entranceIndex))) {
                appeared = true
            }
        }
    }
}
