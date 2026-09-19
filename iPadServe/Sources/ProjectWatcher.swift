import Foundation

/// Watches the served project's directory tree for changes so open pages can
/// live-reload and the file browser stays current.
///
/// Kernel file events only fire for the directory whose descriptor changed, so
/// the watcher holds one `DispatchSource` per directory (root plus every
/// subdirectory). When any of them fires, the tree is re-scanned after a short
/// debounce, which both coalesces editor save bursts and picks up newly
/// created subfolders to watch.
///
/// For linked folders the security-scoped access is owned by `ProjectStore`
/// for as long as the project exists; the watcher only opens descriptors while
/// that access is active and closes them all in `stop()`/`pause()` so nothing
/// keeps the folder pinned while the app is backgrounded.
@MainActor
final class ProjectWatcher: ObservableObject {
    /// Called on the main actor after changes settle. The directory tree has
    /// already been re-scanned for new/removed subfolders at that point.
    var onChange: (() -> Void)?

    private var sources: [String: DispatchSourceFileSystemObject] = [:]
    private var rootURL: URL?
    private var debounceTask: Task<Void, Never>?
    /// Coalesces rapid-fire events (editors often write temp file + rename).
    private let debounceMilliseconds = 400
    /// Safety cap so a huge linked folder cannot exhaust file descriptors.
    private let maxWatchedDirectories = 256

    func start(watching root: URL) {
        stop()
        rootURL = root
        watchTree()
    }

    func stop() {
        pause()
        rootURL = nil
        // Break the retain cycle watcher -> onChange -> owning view value ->
        // StateObject wrapper -> watcher; the owner reassigns it on restart.
        onChange = nil
    }

    /// Closes every descriptor but remembers the root, so `resume()` can
    /// rebuild the watchers when the app returns to the foreground.
    func pause() {
        debounceTask?.cancel()
        debounceTask = nil
        for source in sources.values {
            source.cancel()
        }
        sources.removeAll()
    }

    func resume() {
        guard rootURL != nil else { return }
        watchTree()
    }

    deinit {
        for source in sources.values {
            source.cancel()
        }
    }

    /// Scans the directory tree, watching new directories and dropping
    /// watchers whose directories no longer exist.
    private func watchTree() {
        guard let rootURL else { return }

        var directories: Set<String> = [rootURL.standardizedFileURL.path]
        if let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard directories.count < maxWatchedDirectories else { break }
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    directories.insert(url.standardizedFileURL.path)
                }
            }
        }

        for (path, source) in sources where !directories.contains(path) {
            source.cancel()
            sources[path] = nil
        }
        for path in directories where sources[path] == nil {
            watch(path)
        }
    }

    private func watch(_ path: String) {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleChange()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        source.resume()
        sources[path] = source
    }

    private func scheduleChange() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self, debounceMilliseconds] in
            try? await Task.sleep(nanoseconds: UInt64(debounceMilliseconds) * 1_000_000)
            guard !Task.isCancelled else { return }
            self?.handleChange()
        }
    }

    private func handleChange() {
        // Re-scan first so freshly created subfolders are watched before the
        // caller reacts (e.g. rescans the file list).
        watchTree()
        onChange?()
    }
}
