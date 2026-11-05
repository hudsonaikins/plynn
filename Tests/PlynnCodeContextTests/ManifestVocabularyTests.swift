import XCTest
@testable import PlynnCodeContext

final class ManifestVocabularyTests: XCTestCase {
    func testPackageJSONExtractsDependenciesAndKnownSpellings() {
        let source = #"{"name":"voice-tool","dependencies":{"@modelcontextprotocol/sdk":"1","next":"1","foo-bar":"1"},"scripts":{"ignored":"x"}}"#
        let terms = ManifestVocabulary.parse(source, file: "package.json")

        XCTAssertTrue(terms.contains { $0.text == "MCP" && $0.aliases.contains("model context protocol") })
        XCTAssertTrue(terms.contains { $0.text == "Next.js" })
        XCTAssertTrue(terms.contains { $0.text == "foo-bar" && $0.aliases == ["foo bar"] })
        XCTAssertFalse(terms.contains { $0.text == "ignored" })
    }

    func testPackageSwiftExtractsPackageAndProductNames() {
        let source = #"""
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.8"),
        .product(name: "MLXLLM", package: "mlx-swift-examples")
        """#
        let terms = ManifestVocabulary.parse(source, file: "Package.swift")

        XCTAssertTrue(terms.contains { $0.text == "FluidAudio" })
        XCTAssertTrue(terms.contains { $0.text == "MLXLLM" })
    }

    func testRequirementsRejectsOptionsAndVersions() {
        let terms = ManifestVocabulary.parse(
            "openai>=2\n-r base.txt\nfastapi[standard]==1\n",
            file: "requirements.txt")

        XCTAssertEqual(terms.map(\.text), ["OpenAI", "fastapi"])
    }

    func testPyprojectReadsDependenciesOnly() {
        let source = #"""
        [project]
        description = "private agent platform"
        dependencies = [
          "openai>=2",
          "fastapi[standard]",
        ]
        [tool.poetry.dependencies]
        langgraph = "^1"
        """#

        let terms = ManifestVocabulary.parse(source, file: "pyproject.toml")

        XCTAssertEqual(Set(terms.map(\.text)), ["OpenAI", "fastapi", "LangGraph"])
        XCTAssertFalse(terms.contains { $0.text == "private" || $0.text == "agent" })
    }
}
