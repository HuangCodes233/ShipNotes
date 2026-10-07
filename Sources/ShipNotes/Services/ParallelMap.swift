import Foundation

/// Maps `operation` over `items` with at most `maxConcurrent` in flight,
/// using unstructured tasks — never a TaskGroup or `async let`.
///
/// macOS 27.2 beta (26B5091g) crashes in `swift::TaskGroup::offer` when a
/// group is torn down while a child is still completing (cancelled host,
/// cancelled waiter, races the standalone stress tests could not fully
/// cover; ShipNotes hit it on every screenshot import). Unstructured tasks
/// never participate in group teardown, so this shape cannot reach that
/// path. Results come back in input order; tasks are reaped FIFO, which
/// keeps the in-flight window at `maxConcurrent`. Cancellation is forwarded to
/// in-flight tasks and stops scheduling new work. A cancelled caller receives
/// only the completed input prefix, so callers must not assume a full result.
func mapConcurrently<Item: Sendable, T: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    operation: @escaping @Sendable (Item) async -> T
) async -> [T] {
    let cancellations = ConcurrentMapCancellation()
    return await withTaskCancellationHandler {
        let window = max(1, min(maxConcurrent, items.count))
        var pending: [Task<T, Never>] = []
        var results: [T] = []
        var started = 0
        while results.count < items.count && !Task.isCancelled {
            while started < items.count && pending.count < window && !Task.isCancelled {
                let item = items[started]
                let task = Task { await operation(item) }
                cancellations.register { task.cancel() }
                pending.append(task)
                started += 1
            }
            guard !pending.isEmpty else { break }
            results.append(await pending.removeFirst().value)
        }
        // Reap cancelled tasks too: operation-owned cleanup finishes before
        // this map returns, without Swift TaskGroup teardown.
        if Task.isCancelled {
            cancellations.cancel()
            for task in pending { _ = await task.value }
        }
        return results
    } onCancel: {
        cancellations.cancel()
    }
}

private final class ConcurrentMapCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var isCancelled = false
    private var handlers: [@Sendable () -> Void] = []

    func register(_ handler: @escaping @Sendable () -> Void) {
        lock.lock()
        if isCancelled {
            lock.unlock()
            handler()
        } else {
            handlers.append(handler)
            lock.unlock()
        }
    }

    func cancel() {
        lock.lock()
        isCancelled = true
        let pending = handlers
        handlers = []
        lock.unlock()
        for handler in pending { handler() }
    }
}
