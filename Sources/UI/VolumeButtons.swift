#if os(iOS)
import AVFoundation
import MediaPlayer
import SwiftUI

/// Turns the phone's volume buttons into the TV's while `isEnabled`.
///
/// iOS doesn't hand apps volume-button presses, so this watches the system volume, turns each
/// change into a TV key, and puts the volume back. The (invisible) MPVolumeView in the hierarchy
/// stops iOS from drawing its volume HUD, and its slider is how the volume gets put back.
struct VolumeButtons: UIViewRepresentable {
    var isEnabled: Bool
    var onPress: (RemoteKey) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        container.isUserInteractionEnabled = false
        container.clipsToBounds = true
        let volumeView = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        volumeView.alpha = 0.0001
        container.addSubview(volumeView)
        context.coordinator.volumeView = volumeView
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPress = onPress
        if isEnabled { context.coordinator.start() } else { context.coordinator.stop() }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    @MainActor
    final class Coordinator {
        weak var volumeView: MPVolumeView?
        var onPress: ((RemoteKey) -> Void)?
        private var observation: NSKeyValueObservation?
        private var original: Float?
        /// Room to move both ways, so every press changes the volume and gets noticed.
        private static let resting: Float = 0.5

        func start() {
            guard observation == nil else { return }
            let session = AVAudioSession.sharedInstance()
            // Ambient mixes with other audio and follows the silent switch: this never plays anything.
            try? session.setCategory(.ambient, options: .mixWithOthers)
            guard (try? session.setActive(true)) != nil else { return }
            original = session.outputVolume
            observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
                guard let new = change.newValue, let old = change.oldValue else { return }
                Task { @MainActor in self?.volumeChanged(from: old, to: new) }
            }
            setVolume(Self.resting)
        }

        func stop() {
            guard let observation else { return }
            observation.invalidate()
            self.observation = nil
            if let original { setVolume(original) }
            original = nil
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }

        private func volumeChanged(from old: Float, to new: Float) {
            // Our own reset back to resting.
            guard abs(new - Self.resting) > 0.001 else { return }
            onPress?(new > old ? .volumeUp : .volumeDown)
            setVolume(Self.resting)
        }

        private func setVolume(_ value: Float) {
            guard let slider = volumeView?.subviews.compactMap({ $0 as? UISlider }).first else { return }
            // The slider only takes effect after the current run loop pass.
            DispatchQueue.main.async { slider.value = value }
        }
    }
}
#endif
