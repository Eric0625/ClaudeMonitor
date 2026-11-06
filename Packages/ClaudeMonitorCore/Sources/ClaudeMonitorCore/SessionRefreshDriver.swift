import Foundation

/// Calls `onTick` every second and at once when the sessions folder changes.
///
/// The timer is the source of truth because a process can stop without a file change.
@MainActor
public final class SessionRefreshDriver {
    private let directory: URL
    private let interval: TimeInterval
    private let onTick: @MainActor () -> Void
    private var timer: Timer?
    private var source: DispatchSourceFileSystemObject?

    public init(directory: URL, interval: TimeInterval = 1, onTick: @escaping @MainActor () -> Void) {
        self.directory = directory
        self.interval = interval
        self.onTick = onTick
    }

    public func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        watchDirectory()
        onTick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
        source?.cancel()
        source = nil
    }

    private func tick() {
        if source == nil {
            watchDirectory()
        }
        onTick()
    }

    private func watchDirectory() {
        let descriptor = open(directory.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let source = self.source else { return }
                if !source.data.isDisjoint(with: [.delete, .rename]) {
                    source.cancel()
                    self.source = nil
                }
                self.onTick()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        self.source = source
    }
}
