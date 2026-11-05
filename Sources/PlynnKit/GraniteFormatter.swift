import Foundation

/// Optional local-only MLX server. Failure leaves the deterministic transcript intact.
public actor GraniteFormatter {
    private static let model = "mlx-community/granite-3.3-2b-instruct-4bit"
    private static let endpoint = URL(string: "http://127.0.0.1:8766/v1/chat/completions")!
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func available() async -> Bool {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:8766/v1/models")!)
        request.timeoutInterval = 0.5
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let models = try? JSONDecoder().decode(ModelList.self, from: data)
        else { return false }
        return models.data.contains { $0.id == Self.model }
    }

    public func complete(_ prompt: String) async -> String? {
        guard prompt.count <= 12_000 else { return nil }
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 8
        request.httpBody = try? JSONEncoder().encode(ChatRequest(
            model: Self.model, messages: [Message(role: "user", content: prompt)],
            temperature: 0, max_tokens: 256))
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              data.count < 65_536,
              let result = try? JSONDecoder().decode(ChatResponse.self, from: data)
        else { return nil }
        return result.choices.first?.message.content
    }

    public func format(_ text: String, tone: Tone, technical: Bool,
                       preferredSpellings: [String]) async -> String {
        let prompt = PolishPrompt.build(transcript: text, tone: tone, technical: technical,
                                        preferredSpellings: preferredSpellings)
        return PolishPrompt.sanitize(await complete(prompt), input: text,
                                     glossary: preferredSpellings, removeRepeatedTrailingList: true)
    }

    private struct ModelList: Decodable { let data: [Model] }
    private struct Model: Decodable { let id: String }
    private struct ChatRequest: Encodable {
        let model: String
        let messages: [Message]
        let temperature: Double
        let max_tokens: Int
    }
    private struct Message: Codable { let role: String; let content: String }
    private struct ChatResponse: Decodable { let choices: [Choice] }
    private struct Choice: Decodable { let message: Message }
}
