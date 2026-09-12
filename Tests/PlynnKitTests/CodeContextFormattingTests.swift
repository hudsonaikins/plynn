import XCTest
import PlynnCodeContext
@testable import PlynnKit

final class CodeContextFormattingTests: XCTestCase {
    let symbols = [CodeSymbol(name: "ContextSnapshot", file: "Sources/ContextSnapshot.swift"),
                   CodeSymbol(name: "preferredSpellings", file: "Sources/Formatter.swift")]

    func testSourceVocabularyWorksWithoutModel() async {
        let formatter = TranscriptFormatter()
        let result = await formatter.format("update context snapshot and preferred spellings",
            context: ContextSnapshot(bundleID: "com.openai.codex", codeSymbols: symbols), aiPolish: false)
        XCTAssertEqual(result.text, "Update ContextSnapshot and preferredSpellings")
        XCTAssertEqual(result.verbatim, "update context snapshot and preferred spellings")
    }

    func testNonTechnicalAppNeverUsesSourceVocabulary() async {
        let result = await TranscriptFormatter().format("context snapshot",
            context: ContextSnapshot(bundleID: "com.apple.MobileSMS", codeSymbols: symbols), aiPolish: false)
        XCTAssertEqual(result.text, "Context snapshot")
    }

    func testOrdinaryPhraseIsNotForcedIntoCodeName() async {
        let context = ContextSnapshot(bundleID: "com.openai.codex",
            codeSymbols: [CodeSymbol(name: "getUser", file: "Users.ts")])
        let result = await TranscriptFormatter().format("get user feedback tomorrow", context: context, aiPolish: false)
        XCTAssertEqual(result.text, "Get user feedback tomorrow")
    }

    func testExplicitDictionaryWins() async {
        let formatter = TranscriptFormatter(personalization: {
            ([], [PersonalStore.Term(id: 1, text: "Context Snapshot", aliases: ["context snapshot"])])
        })
        let result = await formatter.format("use context snapshot",
            context: ContextSnapshot(bundleID: "com.openai.codex", codeSymbols: symbols), aiPolish: false)
        XCTAssertEqual(result.text, "Use Context Snapshot")
    }

    func testSnapshotPreservesVocabularyWhenAddingFilenames() {
        let context = ContextSnapshot(bundleID: "com.openai.codex", codeSymbols: symbols)
            .withFileCandidates(["Package.swift"])
        XCTAssertEqual(context.codeSymbols, symbols)
        XCTAssertEqual(context.fileCandidates, ["Package.swift"])
    }

    func testSpokenFilenamesStillTagBeforeSymbolCorrection() async {
        let result = await TranscriptFormatter().format("open context snapshot dot swift",
            context: ContextSnapshot(bundleID: "com.openai.codex",
                fileCandidates: ["ContextSnapshot.swift"], codeSymbols: symbols), aiPolish: false)
        XCTAssertEqual(result.text, "Open @ContextSnapshot.swift")
    }

    func testAvailableLocalModelPreservesGroundedNamesAndOrdinaryMeaning() async throws {
        guard ProcessInfo.processInfo.environment["PLYNN_VALIDATE_CODE_MODEL"] == "1" else {
            throw XCTSkip("Opt in to local model validation with PLYNN_VALIDATE_CODE_MODEL=1")
        }
        let formatter = TranscriptFormatter()
        if await formatter.polishEngine == nil {
            guard ProcessInfo.processInfo.environment["PLYNN_VALIDATE_QWEN"] == "1" else {
                throw XCTSkip("Apple Intelligence unavailable; opt in to Qwen validation separately")
            }
            await formatter.warmLLM()
        }
        guard let engine = await formatter.polishEngine else {
            XCTFail("Requested local model could not load")
            return
        }
        print("code-context validation engine: \(engine)")
        let sourceSymbols = try CodeVocabulary.parse(
            "func getQuokkaTelemetry() {}", file: "Telemetry.swift")
        let context = ContextSnapshot(bundleID: "com.openai.codex", codeSymbols: sourceSymbols)
        let coding = await formatter.format("um call get quokka telemetry after startup",
                                           context: context, aiPolish: true)
        XCTAssertTrue(coding.text.contains("getQuokkaTelemetry"), coding.text)
        XCTAssertTrue(coding.text.lowercased().contains("call"), coding.text)
        XCTAssertTrue(coding.text.lowercased().contains("after startup"), coding.text)
        XCTAssertFalse(coding.text.lowercased().contains("um "), coding.text)
        XCTAssertFalse(coding.text.lowercased().contains("glossary"), coding.text)
        let prose = await formatter.format("um buy groceries tomorrow", context: context, aiPolish: true)
        XCTAssertTrue(prose.text.lowercased().contains("buy groceries tomorrow"), prose.text)
        XCTAssertFalse(prose.text.contains("getQuokkaTelemetry"), prose.text)
        XCTAssertFalse(prose.text.contains("@"), prose.text)
        let ordinary = await formatter.format("um get user feedback tomorrow",
            context: ContextSnapshot(bundleID: "com.openai.codex",
                codeSymbols: [CodeSymbol(name: "getUser", file: "Users.ts")]), aiPolish: true)
        XCTAssertTrue(ordinary.text.lowercased().contains("get user feedback tomorrow"), ordinary.text)
        let evidence = ["engine": engine, "coding_output": coding.text, "prose_output": prose.text,
                        "ambiguous_prose_output": ordinary.text]
        print("CODE_CONTEXT_MODEL " + String(decoding: try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]), as: UTF8.self))
    }
}
