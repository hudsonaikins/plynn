import Foundation
import PlynnCodeContext

public struct FormatResult: Equatable, Sendable {
    public let text: String
    public let pressEnter: Bool
    public let verbatim: String
}

/// The full formatting pipeline: rules pass, snippet expansion, dictionary
/// correction, then optional LLM polish. Every path returns something
/// pasteable; LLM problems degrade to the deterministic output.
public actor TranscriptFormatter {
    private let appleFM = AppleFMFormatter()
    private let granite = GraniteFormatter()
    /// Reloaded per call so Settings edits apply immediately.
    private let personalization: @Sendable () -> (
        snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
    )

    public init(
        personalization: @escaping @Sendable () -> (
            snippets: [PersonalStore.Snippet], terms: [PersonalStore.Term]
        ) = { ([], []) }
    ) {
        self.personalization = personalization
    }

    /// Which polish engine is live, for status display. Nil = rules only.
    public var polishEngine: String? {
        get async {
            if appleFM.ready { return "Apple Intelligence" }
            return await granite.available() ? "Granite 3.3 2B (local MLX)" : nil
        }
    }

    /// Why Apple's model isn't in use (nil when it is).
    public var appleFMStatus: String? {
        appleFM.ready ? nil : appleFM.availabilityDescription
    }

    /// On-device completion for source resolution and summarization.
    public func complete(_ prompt: String) async -> String? {
        if appleFM.ready { return await appleFM.complete(prompt) }
        return await granite.complete(prompt)
    }

    /// Command mode: apply a spoken instruction to selected text.
    /// Nil = no engine or the transform failed — caller must touch nothing.
    public func transform(selection: String, instruction: String) async -> String? {
        let prompt = TransformPrompt.build(selectedText: selection, instruction: instruction)
        let raw = await complete(prompt)
        let out = PolishPrompt.sanitize(raw, input: selection)
        return out == selection ? nil : out
    }

    /// Prewarm Apple's on-device model when it is available.
    public func warmAppleFM() async {
        await appleFM.warm()
    }

    public func format(
        _ transcript: String, context: ContextSnapshot, aiPolish: Bool
    ) async -> FormatResult {
        let (snippets, terms) = personalization()
        let rules = RulesFormatter.format(transcript)
        var text = rules.text
        text = SnippetExpander.expand(text, snippets: snippets)
        text = DictionaryCorrector.correct(text, terms: terms)
        var sourceResolved = false
        if aiPolish, let request = CodeReferenceResolver.prepare(text, context: context),
           await polishEngine != nil {
            let resolved = request.applying(await complete(request.prompt))
            sourceResolved = resolved != text
            text = resolved
            // User vocabulary still wins after a source-backed resolution.
            text = DictionaryCorrector.correct(text, terms: terms)
        }
        let profile = context.profile
        let protected = Set(terms.flatMap { [$0.text] + $0.aliases }.map { $0.lowercased() })
        let codeHints = profile.isTechnical
            ? CodeVocabulary.relevant(to: text, symbols: context.codeSymbols).filter {
                !protected.contains($0.name.lowercased())
                    && !protected.contains(CodeVocabulary.spokenWords($0.name))
            } : []
        let codeWords = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        let explicitCodeAction = !codeWords.isDisjoint(with: [
            "call", "invoke", "rename", "refactor", "import", "implement", "override",
            "initialize", "instantiate", "update", "function", "method", "class", "struct",
            "enum", "parameter", "property", "variable", "identifier", "symbol",
        ])
        let codeTerms = codeHints.enumerated().map { offset, symbol in
            PersonalStore.Term(id: -1 - Int64(offset), text: symbol.name,
                               aliases: explicitCodeAction ? [CodeVocabulary.spokenWords(symbol.name)] : [])
        }
        if profile.isTechnical {
            text = ReferenceResolver.tagFileReferences(
                text, terms: terms, fileCandidates: context.fileCandidates)
        }
        // Latency gate: clean short dictations paste instantly; the LLM only
        // runs when there are fillers/backtracks/lists to fix or it's long.
        text = DictionaryCorrector.correct(text, terms: codeTerms)
        if aiPolish, !text.isEmpty, PolishGate.needsPolish(text) || (!sourceResolved && !codeHints.isEmpty) {
            let spellings = Array(Set(DictionaryCorrector.relevantTerms(for: text, terms: terms)
                + codeHints.map(\.name))).sorted()
            if appleFM.ready {
                text = await appleFM.format(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            } else {
                text = await granite.format(
                    text, tone: profile.tone, technical: profile.isTechnical,
                    preferredSpellings: spellings)
            }
            // The LLM can regress a spelling it saw in the raw text; re-assert.
            text = DictionaryCorrector.correct(text, terms: terms)
            if profile.isTechnical {
                text = ReferenceResolver.tagFileReferences(
                    text, terms: terms, fileCandidates: context.fileCandidates)
            }
        }
        text = DictionaryCorrector.correct(text, terms: codeTerms)
        return FormatResult(text: text, pressEnter: rules.pressEnter, verbatim: transcript)
    }

    /// Backward-compatible convenience for callers that only know the app ID.
    public func format(
        _ transcript: String, bundleID: String?, aiPolish: Bool
    ) async -> FormatResult {
        await format(
            transcript,
            context: ContextSnapshot(bundleID: bundleID),
            aiPolish: aiPolish)
    }
}
