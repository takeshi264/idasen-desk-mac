import Foundation

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

/// A cancellable main-actor loop. Replaces `Timer` so callbacks stay on the main actor.
@MainActor
final class RepeatingTask {
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        task != nil
    }

    deinit {
        task?.cancel()
    }

    func start(every interval: Duration, fireImmediately: Bool = false, _ body: @escaping @MainActor () -> Void) {
        stop()
        task = Task { @MainActor in
            if fireImmediately {
                body()
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else {
                    return
                }
                body()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}

/// A cancellable one-shot main-actor delay.
@MainActor
final class DelayedTask {
    private var task: Task<Void, Never>?

    var isPending: Bool {
        task != nil
    }

    deinit {
        task?.cancel()
    }

    func schedule(after delay: Duration, _ body: @escaping @MainActor () -> Void) {
        cancel()
        task = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            self?.task = nil
            body()
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

extension ProcessInfo {
    static var isRunningTests: Bool {
        processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
