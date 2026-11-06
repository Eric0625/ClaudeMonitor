import Foundation

/// Cancels a scheduled action.
public struct HoverCancellation {
    private let action: @MainActor () -> Void

    public init(_ action: @escaping @MainActor () -> Void) {
        self.action = action
    }

    @MainActor
    func cancel() {
        action()
    }
}

@MainActor
public protocol HoverScheduling: AnyObject {
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> HoverCancellation
}

/// Runs actions on the main actor after a delay.
@MainActor
public final class TaskHoverScheduler: HoverScheduling {
    public init() {}

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> HoverCancellation {
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            action()
        }
        return HoverCancellation { task.cancel() }
    }
}

/// Decides when the panel opens and closes from pointer and click events.
///
/// The panel opens when the pointer stays on the icon for 150 ms, or at once on a click.
/// It closes 300 ms after the pointer leaves both the icon and the panel.
@MainActor
public final class HoverPresenter {
    public enum Region: Hashable, Sendable {
        case icon
        case panel
    }

    public static let openDelay: TimeInterval = 0.15
    public static let closeDelay: TimeInterval = 0.3

    public private(set) var isPanelVisible = false

    private let scheduler: HoverScheduling
    private let onVisibilityChange: @MainActor (Bool) -> Void
    private var pointerRegions: Set<Region> = []
    private var pendingOpen: HoverCancellation?
    private var pendingClose: HoverCancellation?

    public init(scheduler: HoverScheduling, onVisibilityChange: @escaping @MainActor (Bool) -> Void) {
        self.scheduler = scheduler
        self.onVisibilityChange = onVisibilityChange
    }

    public func pointerEntered(_ region: Region) {
        pointerRegions.insert(region)
        cancelClose()
        guard region == .icon, !isPanelVisible, pendingOpen == nil else { return }
        pendingOpen = scheduler.schedule(after: Self.openDelay) { [weak self] in
            self?.pendingOpen = nil
            self?.setVisible(true)
        }
    }

    public func pointerExited(_ region: Region) {
        pointerRegions.remove(region)
        if region == .icon {
            cancelOpen()
        }
        guard isPanelVisible, pointerRegions.isEmpty, pendingClose == nil else { return }
        pendingClose = scheduler.schedule(after: Self.closeDelay) { [weak self] in
            guard let self else { return }
            pendingClose = nil
            if pointerRegions.isEmpty {
                setVisible(false)
            }
        }
    }

    /// Opens the panel at once. A click never closes it.
    public func iconClicked() {
        cancelOpen()
        setVisible(true)
    }

    /// Closes the panel at once, for example after the user opens a session.
    public func dismiss() {
        cancelOpen()
        cancelClose()
        setVisible(false)
    }

    private func setVisible(_ visible: Bool) {
        if !visible {
            pointerRegions.remove(.panel)
        }
        guard visible != isPanelVisible else { return }
        isPanelVisible = visible
        onVisibilityChange(visible)
    }

    private func cancelOpen() {
        pendingOpen?.cancel()
        pendingOpen = nil
    }

    private func cancelClose() {
        pendingClose?.cancel()
        pendingClose = nil
    }
}
