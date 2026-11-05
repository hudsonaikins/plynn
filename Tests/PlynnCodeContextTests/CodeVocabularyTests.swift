import XCTest
@testable import PlynnCodeContext

final class CodeVocabularyTests: XCTestCase {
    func testNativeGrammarsExtractCodeNotLiteralsOrComments() throws {
        let cases = [
            ("Engine.swift", "// FakeComment\nstruct ContextSnapshot { let preferredSpellings = \"SecretLiteral\" }"),
            ("engine.ts", "// FakeComment\nclass ContextSnapshot { preferredSpellings = 'SecretLiteral'; }"),
            ("engine.tsx", "// FakeComment\nconst ContextSnapshot = () => <span>{preferredSpellings}</span>; const x = 'SecretLiteral';"),
            ("engine.js", "// FakeComment\nclass ContextSnapshot { preferredSpellings = 'SecretLiteral'; }"),
            ("engine.py", "# FakeComment\nclass ContextSnapshot:\n    preferredSpellings = 'SecretLiteral'\n"),
        ]
        for (file, source) in cases {
            let names = Set(try CodeVocabulary.parse(source, file: file).map(\.name))
            XCTAssertTrue(names.contains("ContextSnapshot"), file)
            XCTAssertTrue(names.contains("preferredSpellings"), file)
            XCTAssertFalse(names.contains("SecretLiteral"), file)
            XCTAssertFalse(names.contains("FakeComment"), file)
        }
    }

    func testMultiwordHintsAndAmbiguity() {
        let symbols = ["ContextSnapshot", "preferredSpellings", "context", "HTTPClient", "HttpClient"]
            .map { CodeSymbol(name: $0, file: "Engine.swift") }
        XCTAssertEqual(CodeVocabulary.relevant(to: "update context snapshot", symbols: symbols).map(\.name), ["ContextSnapshot"])
        XCTAssertTrue(CodeVocabulary.relevant(to: "the context matters", symbols: symbols).isEmpty)
        XCTAssertTrue(CodeVocabulary.relevant(to: "change http client", symbols: symbols).isEmpty)
        XCTAssertTrue(CodeVocabulary.relevant(to: "buy groceries tomorrow", symbols: symbols).isEmpty)
        XCTAssertEqual(CodeVocabulary.spokenWords("getHTTPClient_ID"), "get http client id")
    }

    func testPathBoundary() {
        for path in [".env.py", "../outside.ts", "/absolute.ts", "node_modules/foo.ts", "build/a.swift", "foo//a.py", "keys.pem"] {
            XCTAssertFalse(WorkspaceCodeIndex.allowedPath(path), path)
        }
        XCTAssertTrue(WorkspaceCodeIndex.allowedPath("Sources/Engine.swift"))
    }

    func testSelectedWorkspaceIndexAndRetrieval() async throws {
        guard let root = ProcessInfo.processInfo.environment["PLYNN_VALIDATE_WORKSPACE"] else {
            throw XCTSkip("Set PLYNN_VALIDATE_WORKSPACE to exercise an explicitly selected repository")
        }
        let started = ContinuousClock.now
        let symbols = await WorkspaceCodeIndex().symbols(at: root)
        let hints = CodeVocabulary.relevant(to: "change context snapshot and preferred spellings", symbols: symbols)
        let duration = started.duration(to: .now)
        XCTAssertTrue(symbols.contains { $0.name == "ContextSnapshot" })
        XCTAssertTrue(hints.contains { $0.name == "preferredSpellings" })
        XCTAssertLessThan(duration, .seconds(2))
        print("CODE_CONTEXT_WORKSPACE symbols=\(symbols.count) hints=\(hints.count) elapsed=\(duration)")
    }

    func testRepositoryNameVocabularyFollowsActiveRoot() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        for name in ["herdr", "another-project"] {
            let root = base.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = ["init", "-q", root.path]
            try git.run(); git.waitUntilExit()
            XCTAssertEqual(git.terminationStatus, 0)
        }
        let index = WorkspaceCodeIndex()
        let herdr = await index.snapshot(at: base.appendingPathComponent("herdr").path)
        XCTAssertEqual(herdr.vocabulary.first?.text, "herdr")
        let other = await index.snapshot(at: base.appendingPathComponent("another-project").path)
        XCTAssertEqual(other.vocabulary.first?.text, "another-project")
        XCTAssertFalse(other.vocabulary.contains { $0.text == "herdr" })
    }

    func testWorkspaceRefreshIgnoresSecretsSymlinksAndDeletedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["init", "-q", root.path]
        try git.run(); git.waitUntilExit()
        XCTAssertEqual(git.terminationStatus, 0)
        try "ignored.swift\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try "struct SecretSymbol {}".write(to: root.appendingPathComponent("ignored.swift"), atomically: true, encoding: .utf8)
        let source = root.appendingPathComponent("Engine.swift")
        try "struct FirstContext {}".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("linked.swift"), withDestinationURL: source)
        let index = WorkspaceCodeIndex()
        let first = await index.symbols(at: root.path)
        XCTAssertEqual(Set(first.map(\.name)), ["FirstContext"])
        XCTAssertFalse(first.contains { $0.file == "linked.swift" })
        let vocabularyOnly = await index.snapshot(at: root.path)
        XCTAssertTrue(vocabularyOnly.files.isEmpty)
        let sourceSnapshot = await index.snapshot(at: root.path, includeSource: true)
        XCTAssertEqual(sourceSnapshot.files.map(\.path), ["Engine.swift"])
        XCTAssertTrue(sourceSnapshot.files[0].source.contains("FirstContext"))
        try "struct SecondContext {}".write(to: source, atomically: true, encoding: .utf8)
        let second = await index.symbols(at: root.path)
        XCTAssertEqual(Set(second.map(\.name)), ["SecondContext"])
        let refreshed = await index.snapshot(at: root.path, includeSource: true)
        XCTAssertTrue(refreshed.files[0].source.contains("SecondContext"))
        XCTAssertFalse(refreshed.files[0].source.contains("FirstContext"))
        try FileManager.default.removeItem(at: source)
        let deleted = await index.symbols(at: root.path)
        XCTAssertTrue(deleted.isEmpty)
        let deletedSnapshot = await index.snapshot(at: root.path, includeSource: true)
        XCTAssertTrue(deletedSnapshot.files.isEmpty)
    }
}
