import Foundation
import PlynnCodeContext

public enum DictationVocabulary {
    public static func build(
        personal: [PersonalStore.Term],
        workspace: CodeWorkspaceContext,
        limit: Int = 64
    ) -> [DictationVocabularyTerm] {
        guard limit > 0 else { return [] }
        var result: [DictationVocabularyTerm] = []
        var seen: Set<String> = []

        func append(_ text: String, aliases: [String]) {
            let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard safe(text), seen.insert(text.lowercased()).inserted else { return }
            let cleanAliases = aliases.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { safe($0) && $0.caseInsensitiveCompare(text) != .orderedSame }
            result.append(DictationVocabularyTerm(
                text: text,
                aliases: Array(Set(cleanAliases)).sorted()))
        }

        for term in personal where result.count < limit {
            append(term.text, aliases: term.aliases)
        }
        for term in workspace.vocabulary where result.count < limit {
            append(term.text, aliases: term.aliases)
        }

        let kindRank = ["class": 4, "enum": 4, "struct": 4, "actor": 4,
                        "function": 3, "method": 3, "property": 2, "variable": 1]
        let groups = Dictionary(grouping: workspace.symbols.filter {
            CodeVocabulary.validIdentifier($0.name)
        }, by: { CodeVocabulary.spokenWords($0.name) })
        let symbols = groups.compactMap { spoken, candidates -> (Int, CodeSymbol)? in
            guard Set(candidates.map(\.name)).count == 1,
                  let symbol = candidates.max(by: {
                      (kindRank[$0.kind] ?? 0) < (kindRank[$1.kind] ?? 0)
                  }) else { return nil }
            let distinctive = spoken.contains(" ") || symbol.name.contains("_")
                || symbol.name == symbol.name.uppercased()
                || symbol.name.dropFirst().contains(where: \.isUppercase)
            guard distinctive else { return nil }
            return (kindRank[symbol.kind] ?? 0, symbol)
        }.sorted {
            $0.0 == $1.0 ? $0.1.name < $1.1.name : $0.0 > $1.0
        }
        for (_, symbol) in symbols where result.count < limit {
            append(symbol.name, aliases: [CodeVocabulary.spokenWords(symbol.name)])
        }
        return result
    }

    private static func safe(_ value: String) -> Bool {
        guard (3...80).contains(value.count), !value.contains("://"), !value.contains("=") else {
            return false
        }
        return value.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.union(CharacterSet(charactersIn: " ._+#@/-")).contains($0)
        }
    }
}
