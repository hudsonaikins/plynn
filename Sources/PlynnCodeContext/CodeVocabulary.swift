import Foundation
import SwiftTreeSitter
import TreeSitterSwift
import TreeSitterTypeScript
import TreeSitterTSX
import TreeSitterPython
import TreeSitterJavaScript

public struct CodeSymbol: Equatable, Sendable {
    public let name: String
    public let file: String
    public let kind: String

    public init(name: String, file: String, kind: String = "identifier") {
        self.name = name
        self.file = file
        self.kind = kind
    }
}

/// Syntax-derived vocabulary only: no comments, literals, or model inference.
public enum CodeVocabulary {
    public static let extensions: Set<String> = ["swift", "ts", "tsx", "mts", "cts", "js", "jsx", "py"]
    private static let identifierTypes: Set<String> = [
        "identifier", "simple_identifier", "type_identifier", "property_identifier",
    ]

    public static func parse(_ source: String, file: String) throws -> [CodeSymbol] {
        let language: OpaquePointer
        switch (file as NSString).pathExtension.lowercased() {
        case "swift": language = tree_sitter_swift()
        case "ts", "mts", "cts": language = tree_sitter_typescript()
        case "tsx": language = tree_sitter_tsx()
        case "js", "jsx": language = tree_sitter_javascript()
        case "py": language = tree_sitter_python()
        default: return []
        }
        let parser = Parser()
        try parser.setLanguage(language)
        parser.timeout = 0.03
        guard let tree = parser.parse(source), let root = tree.rootNode else { return [] }
        let text = source as NSString
        var stack = [root]
        var positions: [String: Int] = [:]
        var symbols: [CodeSymbol] = []
        let declarations = ["class_declaration": "class", "class_definition": "class",
            "function_declaration": "function", "function_definition": "function",
            "method_definition": "method", "method_declaration": "method",
            "property_declaration": "property", "public_field_definition": "property",
            "variable_declarator": "variable", "enum_declaration": "enum"]
        while let node = stack.popLast() {
            if Task.isCancelled { return [] }
            if let defaultKind = declarations[node.nodeType ?? ""],
               let nameNode = node.child(byFieldName: "name"), NSMaxRange(nameNode.range) <= text.length {
                let name = text.substring(with: nameNode.range)
                if validIdentifier(name) {
                    let kind = node.child(byFieldName: "declaration_kind").map { text.substring(with: $0.range) } ?? defaultKind
                    let symbol = CodeSymbol(name: name, file: file, kind: kind)
                    if let position = positions[name] { symbols[position] = symbol }
                    else { positions[name] = symbols.count; symbols.append(symbol) }
                }
            }
            if identifierTypes.contains(node.nodeType ?? ""), NSMaxRange(node.range) <= text.length {
                let name = text.substring(with: node.range)
                if validIdentifier(name), positions[name] == nil {
                    positions[name] = symbols.count
                    symbols.append(CodeSymbol(name: name, file: file, kind: node.nodeType ?? "identifier"))
                }
            }
            if symbols.count >= 500 { break }
            for index in (0..<node.namedChildCount).reversed() {
                if let child = node.namedChild(at: index) { stack.append(child) }
            }
        }
        return symbols
    }

    public static func validIdentifier(_ value: String) -> Bool {
        guard (3...120).contains(value.count) else { return false }
        return value.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    public static func spokenWords(_ name: String) -> String {
        name.replacingOccurrences(of: #"([A-Z]+)([A-Z][a-z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: " ")
            .lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Multiword code names are eligible hints. Ordinary words never gain a
    /// repository-driven replacement just because they are local variable names.
    public static func relevant(to transcript: String, symbols: [CodeSymbol], limit: Int = 16) -> [CodeSymbol] {
        let lower = transcript.lowercased()
        let transcriptWords = Set(lower.split { !$0.isLetter && !$0.isNumber }.map(String.init))
        let groups = Dictionary(grouping: symbols.filter { validIdentifier($0.name) }, by: { spokenWords($0.name) })
        var ranked: [(Int, CodeSymbol)] = []
        for (spoken, candidates) in groups {
            // Different source spellings for the same spoken phrase: abstain.
            guard Set(candidates.map(\.name)).count == 1 else { continue }
            let parts = Set(spoken.split(separator: " ").map(String.init))
            guard let symbol = candidates.sorted(by: { $0.file < $1.file }).first else { continue }
            guard parts.count >= 2 || symbol.name.contains("_")
                || symbol.name == symbol.name.uppercased() else { continue }
            let canonicalMention = transcriptWords.contains(symbol.name.lowercased())
            let matched = parts.intersection(transcriptWords).count
            guard canonicalMention || (parts.count >= 2 && matched >= 2) else { continue }
            ranked.append(((canonicalMention ? 10 : 0) + matched, symbol))
        }
        return ranked.sorted {
            $0.0 == $1.0 ? $0.1.name < $1.1.name : $0.0 > $1.0
        }.prefix(max(0, limit)).map(\.1)
    }
}
