import Foundation

/// Workspace marker written by the optional `plynn_codex` shell wrapper.
/// The marker contains a path only; it never contains transcript or file data.
public struct CodexCLIContext: Equatable, Sendable {
    public let workspaceRoot: String
    public let updatedAt: Date
}

public enum CodexDesktopWorkspace {
    public static let bundleID = "com.openai.codex"
    public static let defaultsKey = "codexDesktopWorkspace"

    /// Codex Desktop's local selection is read at dictation start, not cached across projects.
    /// A remote selection has no readable source tree on this Mac.
    public static func activeRoot(
        stateURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/.codex-global-state.json")
    ) -> String? {
        guard let data = try? Data(contentsOf: stateURL),
            let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return configuredRoot }

        guard let selected = state["selected-project"] as? [String: String] else { return nil }
        guard selected["type"] == "local",
            let id = selected["projectId"],
            let projects = state["local-projects"] as? [String: [String: Any]],
            let roots = projects[id]?["rootPaths"] as? [String],
            roots.count == 1
        else { return nil }
        let root = URL(fileURLWithPath: roots[0]).standardizedFileURL.path
        // Do not index a parent folder of unrelated projects or Codex's private files.
        guard FileManager.default.fileExists(atPath: root + "/.git") else { return nil }
        return root
    }

    public static var configuredRoot: String? {
        let raw = UserDefaults.standard.string(forKey: defaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return nil }

        let root = URL(fileURLWithPath: raw).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return root
    }
}

public enum CodexCLIContextReader {
    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Plynn", isDirectory: true)
            .appendingPathComponent("codex-workspace")
    }

    public static func read(
        path: URL = defaultURL,
        now: Date = .now,
        maxAge: TimeInterval = 3_600
    ) -> CodexCLIContext? {
        let fileManager = FileManager.default
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: path.path),
            let updatedAt = attributes[.modificationDate] as? Date,
            now.timeIntervalSince(updatedAt) >= 0,
            now.timeIntervalSince(updatedAt) <= maxAge,
            let raw = try? String(contentsOf: path, encoding: .utf8)
        else { return nil }

        let root = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !root.isEmpty else { return nil }
        let standardized = URL(fileURLWithPath: root).standardizedFileURL.path
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: standardized, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return nil }
        return CodexCLIContext(workspaceRoot: standardized, updatedAt: updatedAt)
    }
}

/// Bounded, filename-only workspace index used by the Codex CLI context.
/// 500-file cap; add an event-driven index if repository scale or
/// measured lookup latency requires it.
public enum WorkspaceFileIndex {
    private static let ignoredDirectories: Set<String> = [
        ".git", ".build", ".swiftpm", "build", "deriveddata", "dist", "node_modules",
        "pods", "target", "vendor",
    ]

    public static func candidates(at root: String, limit: Int = 500) -> [String] {
        guard limit > 0 else { return [] }
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: root).standardizedFileURL
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var unique: [String: String] = [:]
        var ambiguous = Set<String>()
        var fileCount = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey]) else { continue }
            if values.isDirectory == true {
                if ignoredDirectories.contains(url.lastPathComponent.lowercased()) {
                    enumerator.skipDescendants()
                }
                continue
            }

            let name = url.lastPathComponent
            guard name.contains(".") else { continue }
            fileCount += 1
            if fileCount > limit { break }

            let key = name.lowercased()
            guard !ambiguous.contains(key) else { continue }
            if unique[key] != nil {
                unique[key] = nil
                ambiguous.insert(key)
            } else {
                unique[key] = name
            }
        }
        return unique.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
}
