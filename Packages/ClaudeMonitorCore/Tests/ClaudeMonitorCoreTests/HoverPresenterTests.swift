import Foundation
import Testing
@testable import ClaudeMonitorCore

@MainActor
final class ManualScheduler: HoverScheduling {
    private struct Job {
        let id: Int
        let fireAt: TimeInterval
        let action: () -> Void
    }

    private var jobs: [Job] = []
    private var nextID = 0
    private(set) var now: TimeInterval = 0

    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) -> HoverCancellation {
        nextID += 1
        let id = nextID
        jobs.append(Job(id: id, fireAt: now + delay, action: action))
        return HoverCancellation { [weak self] in
            self?.jobs.removeAll { $0.id == id }
        }
    }

    func advance(by seconds: TimeInterval) {
        let target = now + seconds
        while let job = jobs.filter({ $0.fireAt <= target }).min(by: { $0.fireAt < $1.fireAt }) {
            jobs.removeAll { $0.id == job.id }
            now = job.fireAt
            job.action()
        }
        now = target
    }
}

@MainActor
struct HoverPresenterTests {
    private let scheduler = ManualScheduler()
    private let presenter: HoverPresenter
    private let visibility: VisibilityLog

    init() {
        let log = VisibilityLog()
        visibility = log
        presenter = HoverPresenter(scheduler: scheduler) { visible in
            log.changes.append(visible)
        }
    }

    @Test func opensAfterPointerStaysOnIconFor150ms() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.149)
        #expect(visibility.changes.isEmpty)

        scheduler.advance(by: 0.001)
        #expect(visibility.changes == [true])
        #expect(presenter.isPanelVisible)
    }

    @Test func doesNotOpenWhenPointerLeavesIconEarly() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.1)
        presenter.pointerExited(.icon)
        scheduler.advance(by: 1)

        #expect(visibility.changes.isEmpty)
    }

    @Test func staysOpenWhenPointerMovesFromIconToPanel() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.15)
        presenter.pointerExited(.icon)
        scheduler.advance(by: 0.2)
        presenter.pointerEntered(.panel)
        scheduler.advance(by: 5)

        #expect(visibility.changes == [true])
    }

    @Test func closes300msAfterPointerLeavesBoth() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.15)
        presenter.pointerExited(.icon)
        presenter.pointerEntered(.panel)
        presenter.pointerExited(.panel)
        scheduler.advance(by: 0.299)
        #expect(visibility.changes == [true])

        scheduler.advance(by: 0.001)
        #expect(visibility.changes == [true, false])
        #expect(!presenter.isPanelVisible)
    }

    @Test func returningToIconCancelsClose() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.15)
        presenter.pointerExited(.icon)
        scheduler.advance(by: 0.2)
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 1)

        #expect(visibility.changes == [true])
    }

    @Test func clickOpensAtOnceAndDoesNotClose() {
        presenter.pointerEntered(.icon)
        presenter.iconClicked()
        #expect(visibility.changes == [true])

        presenter.iconClicked()
        scheduler.advance(by: 1)
        #expect(visibility.changes == [true])
    }

    @Test func leavingPanelWhileOnIconKeepsPanelOpen() {
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.15)
        presenter.pointerEntered(.panel)
        presenter.pointerExited(.panel)
        scheduler.advance(by: 1)

        #expect(visibility.changes == [true])
    }

    @Test func suspendedPresenterIgnoresHover() {
        presenter.suspend()
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 1)

        #expect(visibility.changes.isEmpty)
    }

    @Test func suspendHidesOpenPanelAndCancelsPendingOpen() {
        presenter.iconClicked()
        presenter.pointerEntered(.icon)
        presenter.pointerExited(.icon)
        presenter.pointerEntered(.icon)
        presenter.suspend()
        scheduler.advance(by: 1)

        #expect(visibility.changes == [true, false])
    }

    @Test func resumeAllowsHoverAgain() {
        presenter.suspend()
        presenter.pointerEntered(.icon)
        presenter.resume()
        scheduler.advance(by: 1)
        #expect(visibility.changes.isEmpty)

        presenter.pointerExited(.icon)
        presenter.pointerEntered(.icon)
        scheduler.advance(by: 0.15)
        #expect(visibility.changes == [true])
    }

    @Test func dismissHidesAtOnce() {
        presenter.iconClicked()
        presenter.dismiss()

        #expect(visibility.changes == [true, false])
    }
}

@MainActor
final class VisibilityLog {
    var changes: [Bool] = []
}
