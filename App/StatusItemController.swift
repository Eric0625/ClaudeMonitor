import AppKit
import ClaudeMonitorCore

/// Owns the menu bar icon, its hover tracking, its menu, and the session panel.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let launchAtLogin: LaunchAtLogin
    private let panelController: SessionPanelController
    private var presenter: HoverPresenter?
    private var iconTracking: PointerTrackingTarget?
    private let menu = NSMenu()
    private let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    private var renderedIcon: StatusIconState?

    init(monitor: SessionMonitor, launchAtLogin: LaunchAtLogin, openSession: @escaping (SessionOpenTarget) -> Void) {
        self.launchAtLogin = launchAtLogin
        var dismissPanel: () -> Void = {}
        panelController = SessionPanelController(
            monitor: monitor,
            launchAtLogin: launchAtLogin,
            openSession: { target in
                dismissPanel()
                openSession(target)
            }
        )
        super.init()

        let presenter = HoverPresenter(scheduler: TaskHoverScheduler()) { [weak self] visible in
            self?.setPanelVisible(visible)
        }
        self.presenter = presenter
        dismissPanel = { [weak presenter] in presenter?.dismiss() }
        panelController.onPointerChange = { [weak presenter] inside in
            if inside {
                presenter?.pointerEntered(.panel)
            } else {
                presenter?.pointerExited(.panel)
            }
        }
        panelController.anchorFrame = { [weak self] in
            self?.statusItem.button?.window?.frame
        }

        configureButton(presenter: presenter)
        configureMenu()
        render(monitor.panelState)
    }

    func render(_ state: PanelState) {
        guard state.icon != renderedIcon, let button = statusItem.button else { return }
        renderedIcon = state.icon

        let symbolName: String
        let count: Int?
        let label: String
        switch state.icon {
        case .noSessions:
            symbolName = "sparkle"
            count = nil
            label = "No running Claude Code sessions"
        case .running(let running):
            symbolName = "sparkle"
            count = running
            label = running == 1 ? "1 running Claude Code session" : "\(running) running Claude Code sessions"
        case .waiting(let running):
            symbolName = "hand.raised.fill"
            count = running
            label = "A Claude Code session waits for you"
        case .unsupported:
            symbolName = "exclamationmark.triangle"
            count = nil
            label = "Unsupported Claude Code session format"
        }

        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)
        image?.isTemplate = true
        button.image = image
        button.imagePosition = count == nil ? .imageOnly : .imageLeading
        button.title = count.map { " \($0)" } ?? ""
        button.appearsDisabled = state.icon == .noSessions
        button.setAccessibilityLabel(label)
        button.toolTip = nil
    }

    private func configureButton(presenter: HoverPresenter) {
        guard let button = statusItem.button else { return }
        button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(buttonClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let tracking = PointerTrackingTarget(
            onEnter: { [weak presenter] in presenter?.pointerEntered(.icon) },
            onExit: { [weak presenter] in presenter?.pointerExited(.icon) }
        )
        iconTracking = tracking
        button.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: tracking,
            userInfo: nil
        ))
    }

    private func configureMenu() {
        menu.delegate = self
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit Claude Monitor", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func buttonClicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if wantsMenu {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            presenter?.iconClicked()
        }
    }

    private func setPanelVisible(_ visible: Bool) {
        if visible {
            panelController.show()
        } else {
            panelController.hide()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        presenter?.suspend()
        launchAtLogin.refresh()
        launchAtLoginItem.state = launchAtLogin.isEnabled ? .on : .off
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
        presenter?.resume()
    }

    @objc private func toggleLaunchAtLogin() {
        launchAtLogin.setEnabled(!launchAtLogin.isEnabled)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

/// Tracking area owner, kept by the caller because `NSTrackingArea` does not retain it.
final class PointerTrackingTarget: NSResponder {
    private let onEnter: () -> Void
    private let onExit: () -> Void

    init(onEnter: @escaping () -> Void, onExit: @escaping () -> Void) {
        self.onEnter = onEnter
        self.onExit = onExit
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter()
    }

    override func mouseExited(with event: NSEvent) {
        onExit()
    }
}
