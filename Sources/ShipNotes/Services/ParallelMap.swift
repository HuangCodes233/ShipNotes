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
/// keeps the in-flight window at `maxConcurrent`. A cancelled caller simply
/// keeps waiting until the in-flight requests finish and drops the stale
/// result through its request-ID guard.
func mapConcurrently<Item: Sendable, T: Sendable>(
    _ items: [Item],
    maxConcurrent: Int,
    operation: @escaping @Sendable (Item) async -> T
) async -> [T] {
    let window = max(1, min(maxConcurrent, items.count))
    var pending: [Task<T, Never>] = []
    var results: [T] = []
    var started = 0
    while results.count < items.count {
        while started < items.count && pending.count < window {
            let item = items[started]
            pending.append(Task { await operation(item) })
            started += 1
        }
        results.append(await pending.removeFirst().value)
    }
    return results
}
