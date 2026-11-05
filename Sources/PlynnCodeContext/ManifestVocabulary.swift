import Foundation

public struct WorkspaceVocabularyTerm: Equatable, Sendable {
    public let text: String
    public let aliases: [String]
    public let source: String

    public init(text: String, aliases: [String] = [], source: String) {
        self.text = text
        self.aliases = aliases
        self.source = source
    }
}

public enum ManifestVocabulary {
    private static let names: Set<String> = [
        "package.json", "package.swift", "pyproject.toml", "requirements.txt",
        "cargo.toml", "go.mod",
    ]

    private static let ecosystem: [String: (String, [String])] = [
        "@modelcontextprotocol/sdk": ("MCP", ["model context protocol", "m c p"]),
        "@cloudflare/workers-types": ("Cloudflare Workers", ["cloud flare workers"]),
        "@neondatabase/serverless": ("Neon", ["neon database"]),
        "drizzle-orm": ("Drizzle ORM", ["drizzle o r m"]),
        "langgraph": ("LangGraph", ["lang graph"]),
        "mlx-swift": ("MLX", ["m l x"]),
        "next": ("Next.js", ["next js"]),
        "openai": ("OpenAI", ["open ai"]),
        "playwright": ("Playwright", []),
        "shadcn": ("shadcn", ["shad c n"]),
        "tailwindcss": ("Tailwind CSS", ["tailwind c s s"]),
        "vitest": ("Vitest", ["vite test"]),
        "wrangler": ("Wrangler", []),
    ]

    public static func supports(_ path: String) -> Bool {
        names.contains((path as NSString).lastPathComponent.lowercased())
    }

    public static func parse(_ source: String, file: String) -> [WorkspaceVocabularyTerm] {
        let name = (file as NSString).lastPathComponent.lowercased()
        let raw: [String]
        switch name {
        case "package.json": raw = packageJSON(source)
        case "package.swift": raw = matches(#"(?:\.package\s*\(\s*url:|\.product\s*\(\s*name:)\s*\"([^\"]+)\""#, in: source)
        case "requirements.txt": raw = requirements(source)
        case "pyproject.toml", "cargo.toml": raw = tomlDependencies(source)
        case "go.mod": raw = goModules(source)
        default: return []
        }
        var seen: Set<String> = []
        return raw.compactMap { term($0, source: file) }.filter {
            seen.insert($0.text.lowercased()).inserted
        }
    }

    private static func packageJSON(_ source: String) -> [String] {
        guard let data = source.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        var result = (object["name"] as? String).map { [$0] } ?? []
        for key in ["dependencies", "devDependencies", "peerDependencies", "optionalDependencies"] {
            result += (object[key] as? [String: Any]).map { Array($0.keys) } ?? []
        }
        return result
    }

    private static func requirements(_ source: String) -> [String] {
        source.components(separatedBy: .newlines).compactMap { line in
            let value = line.split(separator: "#", maxSplits: 1).first?.trimmingCharacters(in: .whitespaces) ?? ""
            guard !value.isEmpty, !value.hasPrefix("-") else { return nil }
            return value.split(whereSeparator: { "<>=!~;[ ".contains($0) }).first.map(String.init)
        }
    }

    private static func tomlDependencies(_ source: String) -> [String] {
        var section = ""
        var inDependencyArray = false
        var result: [String] = []
        for line in source.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("["), trimmed.hasSuffix("]") {
                section = trimmed.lowercased()
                inDependencyArray = false
                continue
            }
            if section == "[project]", trimmed.hasPrefix("dependencies"), trimmed.contains("[") {
                inDependencyArray = true
            }
            if inDependencyArray || section.contains("optional-dependencies") {
                result += matches(
                    #"[\"']([A-Za-z0-9_.-]+)(?:\[[^\]]+\])?(?:[<>=!~ ].*)?[\"']"#,
                    in: trimmed)
                if trimmed.contains("]") { inDependencyArray = false }
                continue
            }
            let pair = trimmed.split(separator: "=", maxSplits: 1)
            if section.contains("dependencies"), pair.count == 2 {
                let key = pair[0].trimmingCharacters(in: .whitespaces)
                if key.range(of: #"^[A-Za-z0-9_.-]+$"#, options: .regularExpression) != nil {
                    result.append(key)
                }
            }
        }
        return result
    }

    private static func goModules(_ source: String) -> [String] {
        source.components(separatedBy: .newlines).compactMap { line in
            let parts = line.trimmingCharacters(in: .whitespaces).split(whereSeparator: \.isWhitespace)
            guard let first = parts.first else { return nil }
            if first == "module", parts.count > 1 { return String(parts[1]) }
            if first.contains("/"), parts.count > 1 { return String(first) }
            return nil
        }
    }

    private static func matches(_ pattern: String, in source: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(source.startIndex..., in: source)
        return regex.matches(in: source, range: range).compactMap {
            Range($0.range(at: 1), in: source).map { String(source[$0]) }
        }
    }

    private static func term(_ raw: String, source: String) -> WorkspaceVocabularyTerm? {
        var key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.hasSuffix(".git") { key.removeLast(4) }
        if key.contains("://") { key = key.split(separator: "/").last.map(String.init) ?? key }
        guard !key.isEmpty else { return nil }
        if let known = ecosystem[key.lowercased()] {
            return WorkspaceVocabularyTerm(text: known.0, aliases: known.1, source: source)
        }
        if key.hasPrefix("@"), key.contains("/") { key = key.split(separator: "/").last.map(String.init) ?? key }
        if key.contains("/") { key = key.split(separator: "/").last.map(String.init) ?? key }
        guard (3...64).contains(key.count),
              key.range(of: #"^[A-Za-z][A-Za-z0-9_.+-]*$"#, options: .regularExpression) != nil
        else { return nil }
        let alias = key.replacingOccurrences(of: #"[-_.]+"#, with: " ", options: .regularExpression)
            .lowercased()
        return WorkspaceVocabularyTerm(
            text: key,
            aliases: alias == key.lowercased() ? [] : [alias],
            source: source)
    }
}
