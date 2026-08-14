import AppKit
import AVFoundation
import SwiftUI

/// Rounded media slot for split onboarding pages. Plays a bundled looping mp4.
struct OnboardingMediaPlaceholder: View {
    var videoName: String? = nil
    var mediaLabel: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OnboardingStyle.mediaCornerRadius, style: .continuous)
                .fill(OnboardingStyle.mediaFill)

            if let videoName {
                LoopingVideoView(name: videoName, plays: !reduceMotion)
                    .clipShape(RoundedRectangle(cornerRadius: OnboardingStyle.mediaCornerRadius, style: .continuous))
            } else {
                placeholderContent
            }

            RoundedRectangle(cornerRadius: OnboardingStyle.mediaCornerRadius, style: .continuous)
                .strokeBorder(OnboardingStyle.mediaStroke, lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(mediaLabel ?? "Video coming soon")
        .accessibilityHidden(videoName == nil)
    }

    private var placeholderContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "play.circle")
                .font(.system(size: 36, weight: .ultraLight))
                .foregroundStyle(OnboardingStyle.accent.opacity(0.85))
            Text("Video coming soon")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(OnboardingStyle.body)
        }
        .allowsHitTesting(false)
    }
}

private struct LoopingVideoView: NSViewRepresentable {
    var name: String
    var plays: Bool

    func makeNSView(context: Context) -> OnboardingVideoHostView {
        let host = OnboardingVideoHostView()
        host.load(name: name, plays: plays)
        return host
    }

    func updateNSView(_ host: OnboardingVideoHostView, context: Context) {
        host.load(name: name, plays: plays)
    }
}

final class OnboardingVideoHostView: NSView {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var loadedName: String?
    private var shouldPlay = true

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }

    private var playerLayer: AVPlayerLayer {
        layer as! AVPlayerLayer
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    func load(name: String, plays: Bool) {
        shouldPlay = plays
        if loadedName != name {
            loadedName = name
            attachPlayer(named: name)
        }
        if shouldPlay {
            player?.play()
        } else {
            player?.pause()
            player?.seek(to: .zero)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            player?.pause()
        } else if shouldPlay {
            player?.play()
        }
    }

    private func attachPlayer(named name: String) {
        looper = nil
        player?.pause()
        player = nil
        playerLayer.player = nil

        guard let url = Self.url(named: name) else { return }
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.preventsDisplaySleepDuringVideoPlayback = false
        looper = AVPlayerLooper(player: queue, templateItem: AVPlayerItem(url: url))
        player = queue
        playerLayer.player = queue
    }

    private static func url(named name: String) -> URL? {
        let bundle = Bundle.main
        return bundle.url(forResource: name, withExtension: "mp4", subdirectory: "OnboardingMedia")
            ?? bundle.url(forResource: name, withExtension: "mp4")
    }
}
