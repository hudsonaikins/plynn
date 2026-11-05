import XCTest
@testable import PlynnKit

final class CodexCLIContextTests: XCTestCase {
    func testReadsFreshWorkspaceMarker() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("codex-workspace")
        try workspace.path.write(to: marker, atomically: true, encoding: .utf8)

        let context = CodexCLIContextReader.read(path: marker, now: .now, maxAge: 60)

        XCTAssertEqual(context?.workspaceRoot, workspace.standardizedFileURL.path)
    }

    func testIgnoresStaleWorkspaceMarker() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let marker = root.appendingPathComponent("codex-workspace")
        try workspace.path.write(to: marker, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: -120)],
            ofItemAtPath: marker.path)

        XCTAssertNil(CodexCLIContextReader.read(path: marker, now: .now, maxAge: 60))
    }

    func testIndexesUniqueFilenamesAndSkipsBuildDirectories() throws {
        let (root, workspace) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceDirectory = workspace.appendingPathComponent("Sources", isDirectory: true)
        let testsDirectory = workspace.appendingPathComponent("Tests", isDirectory: true)
        let ignoredDirectory = workspace.appendingPathComponent("node_modules", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: testsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ignoredDirectory, withIntermediateDirectories: true)
        try Data().write(to: sourceDirectory.appendingPathComponent("Package.swift"))
        try Data().write(to: sourceDirectory.appendingPathComponent("main.swift"))
        try Data().write(to: testsDirectory.appendingPathComponent("main.swift"))
        try Data().write(to: ignoredDirectory.appendingPathComponent("ignored.ts"))

        let candidates = WorkspaceFileIndex.candidates(at: workspace.path)

        XCTAssertTrue(candidates.contains("Package.swift"))
        XCTAssertFalse(candidates.contains("main.swift"))
        XCTAssertFalse(candidates.contains("ignored.ts"))
    }

    func testFollowsSelectedLocalRepoWithoutLeakingBetweenProjects() throws {
        let (root, first) = try makeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let second = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        for repo in [first, second] {
            try FileManager.default.createDirectory(
                at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)
        }
        try Data().write(to: first.appendingPathComponent("herdr.swift"))
        try Data().write(to: second.appendingPathComponent("Plynn.swift"))
        let stateURL = root.appendingPathComponent("state.json")
        func saveSelection(_ id: String, type: String = "local") throws {
            let state: [String: Any] = [
                "selected-project": ["type": type, "projectId": id],
                "local-projects": [
                    "first": ["rootPaths": [first.path]],
                    "second": ["rootPaths": [second.path]],
                    "parent": ["rootPaths": [root.path]],
                ],
            ]
            try JSONSerialization.data(withJSONObject: state).write(to: stateURL)
        }
        try saveSelection("first")
        XCTAssertEqual(CodexDesktopWorkspace.activeRoot(stateURL: stateURL), first.path)
        XCTAssertEqual(WorkspaceFileIndex.candidates(at: first.path), ["herdr.swift"])
        try saveSelection("second")
        XCTAssertEqual(CodexDesktopWorkspace.activeRoot(stateURL: stateURL), second.path)
        XCTAssertEqual(WorkspaceFileIndex.candidates(at: second.path), ["Plynn.swift"])
        try saveSelection("parent")
        XCTAssertNil(CodexDesktopWorkspace.activeRoot(stateURL: stateURL))
        try saveSelection("first", type: "remote")
        XCTAssertNil(CodexDesktopWorkspace.activeRoot(stateURL: stateURL))
    }

    private func makeWorkspace() throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("plynn-codex-context-\(UUID().uuidString)", isDirectory: true)
        let workspace = root.appendingPathComponent("workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return (root, workspace)
    }
}
