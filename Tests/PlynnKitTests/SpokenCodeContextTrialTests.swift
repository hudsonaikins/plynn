import Foundation
import XCTest
import PlynnCodeContext
@testable import PlynnKit

final class SpokenCodeContextTrialTests: XCTestCase {
    func testSynthesizedSpeechThroughStreamingPipeline() async throws {
        guard let root = ProcessInfo.processInfo.environment["PLYNN_SPOKEN_TRIAL_ROOT"] else {
            throw XCTSkip("Set PLYNN_SPOKEN_TRIAL_ROOT to run the local spoken trials")
        }
        let directory = URL(fileURLWithPath: root).appendingPathComponent("docs/validation/spoken-audio")
        let code = await WorkspaceCodeIndex().snapshot(at: root, includeSource: true)
        let symbols = code.symbols
        let context = ContextSnapshot(bundleID: "com.openai.codex", workspaceRoot: root,
            fileCandidates: WorkspaceFileIndex.candidates(at: root), codeSymbols: symbols, codeFiles: code.files)
        let formatter = TranscriptFormatter()
        guard await formatter.polishEngine != nil else {
            throw XCTSkip("Apple Intelligence is not available on this Mac")
        }
        await formatter.warmAppleFM()
        let polishEngine = await formatter.polishEngine
        let engine = StreamingTranscriber()
        await engine.setVocabulary(DictationVocabulary.build(personal: [], workspace: code))
        var rows: [[String: Any]] = []
        for (name, utterance) in [
            ("filename", "Open context snapshot dot swift"),
            ("symbols", "Update context snapshot and preferred spellings"),
            ("prose", "Get user feedback tomorrow"),
            ("description", "Update the struct that captures context at the hotkey boundary"),
            ("file-description", "Open the file that defines the context captured at the hotkey boundary"),
            ("paraphrase", "Update the struct holding dictation context"),
            ("generic", "Update the struct")
        ] {
            let samples = try AudioFile.loadSamples16kMono(url: directory.appendingPathComponent(name + ".aiff"))
            let start = Date()
            try await engine.start()
            let loaded = Date()
            for chunk in samples.chunks(of: 8_000) {
                try await engine.append(samples: Array(chunk))
            }
            let raw = try await engine.finish()
            let transcribed = Date()
            let result = await formatter.format(raw, context: context, aiPolish: true)
            let finished = Date()
            let passed: Bool
            switch name {
            case "filename":
                passed = result.text.contains("@ContextSnapshot.swift") && result.text.lowercased().contains("open")
            case "symbols":
                passed = result.text.contains("ContextSnapshot") && result.text.contains("preferredSpellings")
                    && result.text.lowercased().contains("update")
            case "description", "paraphrase":
                passed = result.text.trimmingCharacters(in: .punctuationCharacters) == "Update ContextSnapshot"
            case "file-description":
                passed = result.text.contains("@Sources/PlynnKit/ContextSnapshot.swift")
                    && result.text.lowercased().hasPrefix("open ")
            case "generic":
                passed = result.text.trimmingCharacters(in: .punctuationCharacters) == "Update the struct"
            default:
                passed = result.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
                    == "get user feedback tomorrow" && !result.text.contains("getUser")
            }
            let row: [String: Any] = ["case": name, "utterance": utterance, "raw_asr": raw,
                "output": result.text, "status": passed ? "passed" : "failed",
                "audio_seconds": Double(samples.count) / 16_000,
                "engine_start_seconds": loaded.timeIntervalSince(start),
                "asr_seconds": transcribed.timeIntervalSince(loaded),
                "format_seconds": finished.timeIntervalSince(transcribed),
                "retrieved_files": CodeReferenceResolver.prepare(raw, context: context)?.candidates.map(\.file) ?? []]
            rows.append(row)
            print("SPOKEN_TRIAL " + String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
            XCTAssertTrue(passed, "\(name): raw=\(raw), output=\(result.text)")
        }
        let evidence: [String: Any] = ["base_commit": "6588034870ecc377b6eb96bd05d8bed8fea2af81",
            "candidate": "See candidate.json for commit identity and source file digests",
            "scope": "Samantha synthesized speech, streaming ASR and formatter; no microphone, hotkey or paste validation",
            "asr_engine": engine.displayName, "polish_engine": polishEngine ?? "unavailable",
            "voice": "Samantha", "words_per_minute": 160, "symbol_count": symbols.count,
            "personalization": "empty test store", "external_api_cost": 0,
            "status": rows.allSatisfy { $0["status"] as? String == "passed" } ? "passed" : "failed", "trials": rows]
        try JSONSerialization.data(withJSONObject: evidence, options: [.prettyPrinted, .sortedKeys])
            .write(to: directory.appendingPathComponent("results.json"), options: .atomic)
    }
}
