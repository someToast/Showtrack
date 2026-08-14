import SwiftUI
import UIKit

/// Presents the system camera for a single still capture (falls back to the
/// photo library where no camera exists, e.g. the simulator). Flash off.
///
/// A translucent instruction banner is laid over the preview, hugging the top of
/// the viewfinder with a fixed 12pt margin. It rotates and re-sizes with the
/// device orientation so the text stays upright and uses the wider viewport in
/// landscape.
///
/// The first camera launch per app session has a brief system cold-start pause;
/// subsequent scans are instant.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        if picker.sourceType == .camera {
            picker.cameraFlashMode = .off
            picker.cameraOverlayView = context.coordinator.makeOverlay()
            context.coordinator.startObserving()
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleUIViewController(_ uiViewController: UIImagePickerController, coordinator: Coordinator) {
        coordinator.stopObserving()
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        private weak var overlay: UIView?
        private weak var banner: UIView?
        private weak var label: UILabel?
        private var isLayingOut = false

        // Banner metrics.
        private let hInset: CGFloat = 14
        private let vInset: CGFloat = 10
        /// Fixed gap between the banner and the viewfinder edges (all sides).
        private let margin: CGFloat = 12
        /// Height of the camera's top control strip (status bar / island + the
        /// flash control) above the live viewfinder, below the safe-area top.
        private let topControlStrip: CGFloat = 96

        init(_ parent: CameraPicker) { self.parent = parent }

        // MARK: Overlay

        /// A non-interactive instruction banner over the live preview. Sits above
        /// the preview but below the system shutter/cancel controls.
        func makeOverlay() -> UIView {
            let overlay = UIView(frame: Self.screenBounds())
            overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            overlay.isUserInteractionEnabled = false
            overlay.backgroundColor = .clear

            let banner = UIView()
            banner.backgroundColor = UIColor.black.withAlphaComponent(0.55)
            banner.layer.cornerRadius = 14
            banner.layer.cornerCurve = .continuous

            let label = UILabel()
            label.text = "Take a photo of the show’s info screen that contains its title"
            label.textColor = .white
            label.font = .preferredFont(forTextStyle: .subheadline)
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false

            banner.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: banner.leadingAnchor, constant: hInset),
                label.trailingAnchor.constraint(equalTo: banner.trailingAnchor, constant: -hInset),
                label.topAnchor.constraint(equalTo: banner.topAnchor, constant: vInset),
                label.bottomAnchor.constraint(equalTo: banner.bottomAnchor, constant: -vInset),
            ])
            overlay.addSubview(banner)

            self.overlay = overlay
            self.banner = banner
            self.label = label
            layoutBanner(animated: false)
            return overlay
        }

        // MARK: Observation

        func startObserving() {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            NotificationCenter.default.addObserver(
                self, selector: #selector(orientationChanged),
                name: UIDevice.orientationDidChangeNotification, object: nil)
            // Re-run once the overlay is in the window so the real safe-area inset
            // is available (the first pass runs before it's attached).
            for delay in [0.2, 0.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.layoutBanner(animated: false)
                }
            }
        }

        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        @objc private func orientationChanged() { layoutBanner(animated: true) }

        // MARK: Layout

        /// Rotates, re-sizes, and repositions the banner so it hugs the top of the
        /// viewfinder in the current orientation. The picker itself is portrait-
        /// locked, so we rotate the banner manually to stay upright for the reader.
        private func layoutBanner(animated: Bool) {
            guard !isLayingOut, let overlay, let banner, let label else { return }
            let W = overlay.bounds.width, H = overlay.bounds.height
            guard W > 0, H > 0 else { return }
            isLayingOut = true
            defer { isLayingOut = false }

            // Viewfinder (live preview) rect: full-width 4:3, below the camera's
            // top control strip. Computed rather than read from the preview layer,
            // which deadlocks the capture pipeline during start-up.
            let safeTop = overlay.window?.safeAreaInsets.top ?? 59
            let previewTop = safeTop + topControlStrip
            let previewHeight = W * 4 / 3
            let preview = CGRect(x: 0, y: previewTop, width: W, height: previewHeight)

            let orientation = UIDevice.current.orientation
            let isLandscape = orientation.isLandscape

            // Reader-horizontal length available within the viewfinder.
            let availLength = isLandscape ? preview.height : preview.width
            let maxContent = max(120, availLength - 2 * margin)
            label.preferredMaxLayoutWidth = maxContent - hInset * 2
            let size = banner.systemLayoutSizeFitting(
                CGSize(width: maxContent, height: 0),
                withHorizontalFittingPriority: .fittingSizeLevel,
                verticalFittingPriority: .fittingSizeLevel)

            let angle: CGFloat
            let center: CGPoint
            switch orientation {
            case .landscapeLeft:   // reader-top = right edge of the viewfinder
                angle = .pi / 2
                center = CGPoint(x: preview.maxX - margin - size.height / 2, y: preview.midY)
            case .landscapeRight:  // reader-top = left edge of the viewfinder
                angle = -.pi / 2
                center = CGPoint(x: preview.minX + margin + size.height / 2, y: preview.midY)
            default:               // portrait: reader-top = top edge of the viewfinder
                angle = 0
                center = CGPoint(x: preview.midX, y: preview.minY + margin + size.height / 2)
            }

            let apply = {
                banner.bounds = CGRect(origin: .zero, size: size)
                banner.transform = CGAffineTransform(rotationAngle: angle)
                banner.center = center
            }
            if animated {
                UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState], animations: apply)
            } else {
                apply()
            }
        }

        private static func screenBounds() -> CGRect {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }?
                .screen.bounds ?? CGRect(x: 0, y: 0, width: 430, height: 932)
        }

        // MARK: Delegate

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
