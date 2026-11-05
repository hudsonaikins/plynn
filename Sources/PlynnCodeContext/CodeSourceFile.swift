import Foundation

public struct CodeWorkspaceContext: Equatable, Sendable {
    public let symbols: [CodeSymbol]
    public let files: [CodeSourceFile]
    public let vocabulary: [WorkspaceVocabularyTerm]

    public init(
        symbols: [CodeSymbol] = [],
        files: [CodeSourceFile] = [],
        vocabulary: [WorkspaceVocabularyTerm] = []
    ) {
        self.symbols = symbols
        self.files = files
        self.vocabulary = vocabulary
    }
}

public struct CodeSourceFile: Equatable, Sendable {
    public let path: String
    public let source: String

    public init(path: String, source: String) {
        self.path = path
        self.source = source
    }

    /// Retrieve bounded, nearby source lines; no generated summaries or embeddings.
    /// A missing lexical match abstains instead of guessing from unrelated files.
    public static func relevant(to transcript: String, files: [Self]) -> [Self] {
        let stop = Set("the that a an and or of to for in on with is it its this holding holds containing contains which who update change open refactor rename call invoke implement struct class actor enum function method property file module please".split(separator: " ").map(String.init))
        func words(_ text: String) -> Set<String> {
            Set(CodeVocabulary.spokenWords(text).split { !$0.isLetter && !$0.isNumber }.map(String.init))
        }
        let query = words(transcript).subtracting(stop).filter { $0.count > 2 }
        guard !query.isEmpty else { return [] }
        var ranked: [(score: Int, file: Self)] = []
        for file in files where WorkspaceCodeIndex.allowedPath(file.path) {
            let lines = file.source.components(separatedBy: .newlines)
            var bestScore = 0
            var bestExcerpt = ""
            for index in lines.indices {
                let lineScore = query.intersection(words(lines[index])).count
                guard lineScore > 0 else { continue }
                let excerpt = String(lines[max(0, index - 4)..<min(lines.count, index + 12)]
                    .joined(separator: "\n").prefix(1_600))
                let score = query.intersection(words(excerpt)).count * 4 + lineScore
                    + query.intersection(words((file.path as NSString).lastPathComponent)).count * 3
                if score > bestScore {
                    bestScore = score
                    bestExcerpt = excerpt
                }
            }
            // Test fixtures repeat descriptions and expected answers. Prefer
            // implementation evidence unless the speaker asks about tests.
            let pathParts = file.path.lowercased().split(separator: "/")
            let isTest = pathParts.contains { $0 == "tests" || $0 == "test" || $0 == "__tests__" || $0 == "fixtures" }
                || file.path.contains(".test.") || file.path.contains(".spec.")
            if isTest, !query.contains("test"), !query.contains("tests") { bestScore /= 3 }
            if bestScore > 0 { ranked.append((bestScore, Self(path: file.path, source: bestExcerpt))) }
        }
        return ranked.sorted { $0.score == $1.score ? $0.file.path < $1.file.path : $0.score > $1.score }
            .prefix(3).map(\.file)
    }
}
