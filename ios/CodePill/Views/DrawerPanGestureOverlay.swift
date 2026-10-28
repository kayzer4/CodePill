import SwiftUI
import UIKit

/// Window-level gesture helper for the side drawer.
/// Attaches a UIPanGestureRecognizer directly to the UIWindow so that:
/// 1. It NEVER blocks hit testing or touches for underlying views (chat scroll, buttons, links).
/// 2. It strictly checks gesture angle:
///    - Vertical movement -> fails immediately, letting chat scroll smoothly with zero conflict.
///    - Horizontal movement from left ~60% of screen -> captures exclusively, moving drawer smoothly.
public struct WindowDrawerPanHelper: UIViewRepresentable {
    public var isOpen: Bool
    public var drawerWidth: CGFloat
    public var onPanChanged: (CGFloat) -> Void
    public var onPanEnded: (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void

    public init(
        isOpen: Bool,
        drawerWidth: CGFloat = 300,
        onPanChanged: @escaping (CGFloat) -> Void,
        onPanEnded: @escaping (_ translationX: CGFloat, _ velocityX: CGFloat) -> Void
    ) {
        self.isOpen = isOpen
        self.drawerWidth = drawerWidth
        self.onPanChanged = onPanChanged
        self.onPanEnded = onPanEnded
    }

    public func makeUIView(context: Context) -> WindowPanView {
        let view = WindowPanView()
        view.isOpen = isOpen
        view.drawerWidth = drawerWidth
        view.onPanChanged = onPanChanged
        view.onPanEnded = onPanEnded
        return view
    }

    public func updateUIView(_ uiView: WindowPanView, context: Context) {
        uiView.isOpen = isOpen
        uiView.drawerWidth = drawerWidth
        uiView.onPanChanged = onPanChanged
        uiView.onPanEnded = onPanEnded
    }

    public final class WindowPanView: UIView, UIGestureRecognizerDelegate {
        var isOpen: Bool = false
        var drawerWidth: CGFloat = 300
        var onPanChanged: ((CGFloat) -> Void)?
        var onPanEnded: ((CGFloat, CGFloat) -> Void)?

        private var panRecognizer: UIPanGestureRecognizer?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false // Pass all touches to views below
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        public override func didMoveToWindow() {
            super.didMoveToWindow()
            if let window = self.window {
                if panRecognizer == nil {
                    let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
                    pan.delegate = self
                    pan.cancelsTouchesInView = true
                    window.addGestureRecognizer(pan)
                    self.panRecognizer = pan
                }
            } else {
                if let pan = panRecognizer {
                    pan.view?.removeGestureRecognizer(pan)
                    panRecognizer = nil
                }
            }
        }

        deinit {
            if let pan = panRecognizer {
                pan.view?.removeGestureRecognizer(pan)
            }
        }

        public override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let window = self.window else { return false }

            let translation = pan.translation(in: window)
            let velocity = pan.velocity(in: window)

            if isOpen {
                // When drawer is open: swipe left from anywhere on the entire screen to close
                let isMovingLeft = velocity.x < -10 || translation.x < -5
                let isHorizontal = abs(velocity.x) > abs(velocity.y) * 1.05 || abs(translation.x) > abs(translation.y) * 1.05
                return isMovingLeft && isHorizontal
            } else {
                // When drawer is closed: swipe right from anywhere on screen (left ~85%) to open
                let location = pan.location(in: window)
                let screenWidth = window.bounds.width
                if location.x > screenWidth * 0.85 { return false }

                let isMovingRight = velocity.x > 10 || translation.x > 5
                let isHorizontal = abs(velocity.x) > abs(velocity.y) * 1.05 || abs(translation.x) > abs(translation.y) * 1.05
                return isMovingRight && isHorizontal
            }
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // Allow simultaneous evaluation with other recognizers (e.g. UIScrollView) so both receive touch vectors
            return true
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // When our drawer pan recognizer claims the horizontal gesture, require other pan recognizers (like UIScrollView) to fail
            if otherGestureRecognizer is UIPanGestureRecognizer && otherGestureRecognizer != gestureRecognizer {
                return true
            }
            return false
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return false
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard let window = self.window else { return }
            let translation = recognizer.translation(in: window)
            let velocity = recognizer.velocity(in: window)

            switch recognizer.state {
            case .began:
                window.endEditing(true)
            case .changed:
                onPanChanged?(translation.x)
            case .ended, .cancelled:
                onPanEnded?(translation.x, velocity.x)
            default:
                break
            }
        }
    }
}
