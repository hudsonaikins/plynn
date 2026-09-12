import Foundation
import CryptoKit
import Darwin

/// In-memory index of the explicitly selected Git workspace. Refresh work is
/// bounded and cancellable; no disk cache or source text reaches the model.
public actor WorkspaceCodeIndex {
    public static let shared = WorkspaceCodeIndex()
    private var cachedRoot: String?
    private var cached: [String: (digest: SHA256.Digest, symbols: [CodeSymbol])] = [:]
    public init() {}

    public func symbols(at root: String) -> [CodeSymbol] {
        if cachedRoot != root { cached.removeAll(); cachedRoot = root }
        guard !Task.isCancelled, let names = Self.gitFiles(at: root) else { return [] }
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath()
        let started = ContinuousClock.now
        var result: [CodeSymbol] = []
        var retained: [String: (digest: SHA256.Digest, symbols: [CodeSymbol])] = [:]
        var bytes = 0
        var count = 0
        for name in names.sorted() {
            if Task.isCancelled { return [] }
            if started.duration(to: .now) > .milliseconds(600) { break }
            guard Self.allowedPath(name) else { continue }
            let file = rootURL.appendingPathComponent(name).standardizedFileURL
            guard file.path.hasPrefix(rootURL.path + "/"),
                file.resolvingSymlinksInPath().path == file.path,
                let attributes = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                attributes.isRegularFile == true, let size = attributes.fileSize,
                size <= 256_000, bytes + size <= 8_000_000
            else { continue }
            count += 1
            if count > 500 { break }
            guard let data = Self.readSource(name, root: rootURL), bytes + data.count <= 8_000_000,
                file.resolvingSymlinksInPath().path == file.path,
                let source = String(data: data, encoding: .utf8)
            else { continue }
            bytes += data.count
            let digest = SHA256.hash(data: data)
            let symbols: [CodeSymbol]
            if let previous = cached[name], previous.digest == digest {
                symbols = previous.symbols
            } else {
                symbols = (try? CodeVocabulary.parse(source, file: name)) ?? []
            }
            retained[name] = (digest, symbols)
            result += symbols
        }
        cached = retained
        return result
    }

    /// Anchor every path component to an open directory descriptor. Concurrent
    /// symlink/FIFO swaps cannot redirect or indefinitely block source reads.
    private static func readSource(_ path: String, root: URL) -> Data? {
        var directory = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { return nil }
        defer { close(directory) }
        let components = path.split(separator: "/").map(String.init)
        for component in components.dropLast() {
            let next = openat(directory, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { return nil }
            close(directory)
            directory = next
        }
        guard let name = components.last else { return nil }
        let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
            info.st_size <= 256_000,
            let data = try? handle.read(upToCount: 256_001), data.count <= 256_000 else { return nil }
        return data
    }

    public static func allowedPath(_ path: String) -> Bool {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        let ignored: Set<String> = ["node_modules", "vendor", "dist", "build", "target", "pods", "coverage"]
        guard !parts.isEmpty, !parts.contains(where: {
            $0.isEmpty || $0.hasPrefix(".") || ignored.contains($0.lowercased())
        }) else { return false }
        return CodeVocabulary.extensions.contains((path as NSString).pathExtension.lowercased())
    }

    private static func gitFiles(at root: String) -> [String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.untrackedCache=false",
                             "-C", root, "ls-files", "-z", "--cached", "--others", "--exclude-standard"]
        process.environment = ["PATH": "/usr/bin:/bin", "GIT_CONFIG_NOSYSTEM": "1",
                               "GIT_CONFIG_GLOBAL": "/dev/null", "GIT_OPTIONAL_LOCKS": "0"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: timeout)
        defer { timeout.cancel(); try? pipe.fileHandleForReading.close() }
        var data = Data()
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            data.append(chunk)
            if data.count > 1_000_000 || Task.isCancelled { process.terminate(); return nil }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, let text = String(data: data, encoding: .utf8) else { return nil }
        return Array(Set(text.split(separator: "\0").map(String.init)))
    }
}
