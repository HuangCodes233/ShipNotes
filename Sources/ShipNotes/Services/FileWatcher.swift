import CoreServices
import Foundation

/// Watches a directory tree for file changes using FSEventStream (recursive).
/// Debounces rapid events and invokes `onChange` on the main queue.
@MainActor
final class FileWatcher {
    /// FSEventStreamRef is a C pointer; stop/invalidate/release are thread-safe.
    /// Marked `nonisolated(unsafe)` so `deinit` (which is nonisolated in Swift 6)
    /// can clean up as a safety net even if `stop()` was not called explicitly.
    nonisolated(unsafe) private var stream: FSEventStreamRef?
    private var onChange: (() -> Void)?
    private var root: URL?
    private var debounceWork: DispatchWorkItem?
    private static let debounceInterval: TimeInterval = 0.2

    func start(url: URL, onChange: @escaping () -> Void) {
        stop()
        self.onChange = onChange
        self.root = url

        let path = url.path as CFString
        let pathsToWatch = [path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
            // `kFSEventStreamCreateFlagUseCFTypes` makes this a CFArray of CFString.
            let paths = (Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray) as? [String] ?? []
            MainActor.assumeIsolated {
                watcher.handleEvents(paths: paths)
            }
        }

        guard
            let stream = FSEventStreamCreate(
                nil,
                callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.3,  // latency before delivering events (seconds)
                UInt32(
                    kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                        | kFSEventStreamCreateFlagUseCFTypes)
            )
        else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
        self.stream = stream
    }

    func stop() {
        debounceWork?.cancel()
        debounceWork = nil
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        stream = nil
    }

    private func handleEvents(paths: [String]) {
        guard let root else { return }
        // No paths means FSEvents couldn't say what changed; reload to be safe.
        guard paths.isEmpty || paths.contains(where: { Self.isRelevantChange(path: $0, root: root) }) else {
            return
        }
        scheduleDebouncedCallback()
    }

    /// Watching a project root also sees git, build and editor churn. Those
    /// folders are never parsed (see `FileScannerUtils.shouldSkip`), so a
    /// build or `git checkout` must not trigger a full re-parse every few
    /// hundred milliseconds.
    nonisolated static func isRelevantChange(path: String, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
        guard standardized.hasPrefix(rootPath) else { return true }
        let components = standardized.dropFirst(rootPath.count).split(separator: "/").map(String.init)
        guard let name = components.last else { return true }
        if components.contains(where: { FileScannerUtils.shouldSkip(URL(fileURLWithPath: $0), isDirectory: true) }) {
            return false
        }
        if name == ".DS_Store" || name.hasSuffix("~") || name.hasSuffix(".swp") || name.hasPrefix(".#") {
            return false
        }
        return true
    }

    private func scheduleDebouncedCallback() {
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.onChange?()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceInterval, execute: work)
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
}
