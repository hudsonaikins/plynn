import XCTest
@testable import PlynnCodeContext
@testable import PlynnKit

final class DictationVocabularyTests: XCTestCase {
    func testPersonalThenManifestThenDistinctiveSymbols() {
        let personal = [PersonalStore.Term(id: 1, text: "Plynn", aliases: ["plin"])]
        let workspace = CodeWorkspaceContext(
            symbols: [
                CodeSymbol(name: "WorkspaceCodeIndex", file: "Index.swift", kind: "class"),
                CodeSymbol(name: "value", file: "Index.swift", kind: "variable"),
            ],
            vocabulary: [
                WorkspaceVocabularyTerm(text: "MCP", aliases: ["m c p"], source: "package.json")
            ])

        let terms = DictationVocabulary.build(personal: personal, workspace: workspace)

        XCTAssertEqual(terms.map(\.text), ["Plynn", "MCP", "WorkspaceCodeIndex"])
        XCTAssertEqual(terms.last?.aliases, ["workspace code index"])
    }

    func testDeduplicatesAndHonorsLimit() {
        let personal = [
            PersonalStore.Term(id: 1, text: "OpenAI", aliases: []),
            PersonalStore.Term(id: 2, text: "openai", aliases: ["open ai"]),
        ]
        let workspace = CodeWorkspaceContext(vocabulary: [
            WorkspaceVocabularyTerm(text: "MCP", source: "package.json")
        ])

        let terms = DictationVocabulary.build(personal: personal, workspace: workspace, limit: 1)

        XCTAssertEqual(terms.map(\.text), ["OpenAI"])
    }
}
