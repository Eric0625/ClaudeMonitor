import AppKit
import ClaudeMonitorCore
import SwiftUI

/// A borderless panel that never takes focus from the active app.
final class SessionPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: SessionPanelView.width, height: 120),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        isFloatingPanel = true
        level = .statusBar
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovable = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Lets the first click on a row act at once, because the panel is never key.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class SessionPanelController {
    var onPointerChange: ((Bool) -> Void)?
    var anchorFrame: () -> NSRect? = { nil }

    private let panel = SessionPanel()
    private let layout = PanelLayout()
    private let hostingView: FirstMouseHostingView<SessionPanelView>
    private var contentSize = CGSize(width: SessionPanelView.width, height: 120)
    private var pointerTracking: PointerTrackingTarget?

    init(monitor: SessionMonitor, launchAtLogin: LaunchAtLogin, openSession: @escaping (SessionID, SessionOpenTarget) -> Void) {
        let effectView = NSVisualEffectView()
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.maskImage = Self.roundedMask(radius: 10)

        var sizeChanged: (CGSize) -> Void = { _ in }
        let rootView = SessionPanelView(
            monitor: monitor,
            launchAtLogin: launchAtLogin,
            layout: layout,
            actions: PanelActions(
                openSession: openSession,
                quit: { NSApp.terminate(nil) },
                sizeChanged: { sizeChanged($0) }
            )
        )
        let hostingView = FirstMouseHostingView(rootView: rootView)
        hostingView.sizingOptions = [.intrinsicContentSize]
        hostingView.autoresizingMask = [.width, .height]
        hostingView.frame = effectView.bounds
        effectView.addSubview(hostingView)
        panel.contentView = effectView
        self.hostingView = hostingView

        sizeChanged = { [weak self] size in
            self?.contentSize = size
            self?.placePanel()
        }

        let tracking = PointerTrackingTarget(
            onEnter: { [weak self] in self?.onPointerChange?(true) },
            onExit: { [weak self] in self?.onPointerChange?(false) }
        )
        pointerTracking = tracking
        effectView.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracking,
            userInfo: nil
        ))
    }

    func show() {
        layout.maxListHeight = maxListHeight()
        layout.isVisible = true
        hostingView.layoutSubtreeIfNeeded()
        let measured = hostingView.fittingSize
        if measured.width > 0, measured.height > 0 {
            contentSize = measured
        }
        placePanel()
        panel.orderFrontRegardless()
    }

    func hide() {
        layout.isVisible = false
        panel.orderOut(nil)
    }

    private func placePanel() {
        guard let anchor = anchorFrame() else { return }
        let screen = NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? anchor
        let size = NSSize(width: ceil(contentSize.width), height: ceil(contentSize.height))
        let margin: CGFloat = 8
        let x = min(max(anchor.midX - size.width / 2, visible.minX + margin), visible.maxX - size.width - margin)
        let y = anchor.minY - size.height - 2
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }

    private func maxListHeight() -> CGFloat {
        let anchor = anchorFrame()
        let screen = NSScreen.screens.first { anchor.map($0.frame.intersects) ?? false } ?? NSScreen.main
        let available = screen?.visibleFrame.height ?? 800
        return max(200, available - 140)
    }

    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}
