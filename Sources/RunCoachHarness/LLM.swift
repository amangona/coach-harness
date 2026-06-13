import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// PILLAR: LLM (the engine). Stateless: text in, text out, plus token usage so the
/// observability pillar can report real cost.
public struct LLMResponse: Sendable {
    public let text: String
    public let promptTokens: Int
    public let outputTokens: Int
    public init(text: String, promptTokens: Int = 0, outputTokens: Int = 0) {
        self.text = text
        self.promptTokens = promptTokens
        self.outputTokens = outputTokens
    }
}

public protocol LLMClient: Sendable {
    var modelName: String { get }
    func generate(system: String, user: String) async throws -> LLMResponse
}

public enum LLMError: Error, CustomStringConvertible {
    case badURL
    case noResponse
    case http(Int, String)

    public var description: String {
        switch self {
        case .badURL:               return "bad URL"
        case .noResponse:           return "no HTTP response"
        case .http(let code, let m): return "HTTP \(code): \(m.prefix(160))"
        }
    }
}

// MARK: - Gemini (production engine, parity with the app)

public struct GeminiClient: LLMClient {
    public let modelName: String
    private let apiKey: String
    private let session: URLSession

    public init(apiKey: String, modelName: String = "gemini-2.5-flash", session: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.session = session
    }

    private struct Part: Codable { let text: String }
    private struct Content: Codable { let role: String?; let parts: [Part] }
    private struct SystemInstruction: Codable { let parts: [Part] }
    private struct GenConfig: Codable { let temperature: Double; let maxOutputTokens: Int }
    private struct Request: Codable {
        let systemInstruction: SystemInstruction
        let contents: [Content]
        let generationConfig: GenConfig
    }
    private struct RespPart: Codable { let text: String? }
    private struct RespContent: Codable { let parts: [RespPart]? }
    private struct Candidate: Codable { let content: RespContent? }
    private struct Usage: Codable { let promptTokenCount: Int?; let candidatesTokenCount: Int? }
    private struct Response: Codable { let candidates: [Candidate]?; let usageMetadata: Usage? }

    public func generate(system: String, user: String) async throws -> LLMResponse {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw LLMError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Request(
            systemInstruction: .init(parts: [.init(text: system)]),
            contents: [.init(role: "user", parts: [.init(text: user)])],
            generationConfig: .init(temperature: 0.9, maxOutputTokens: 120)
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let text = decoded.candidates?.first?.content?.parts?.first?.text ?? ""
        return LLMResponse(
            text: text,
            promptTokens: decoded.usageMetadata?.promptTokenCount ?? 0,
            outputTokens: decoded.usageMetadata?.candidatesTokenCount ?? 0
        )
    }
}

// MARK: - Mock (deterministic, offline — safe against bad conference wifi)

public struct MockLLMClient: LLMClient {
    public let modelName = "mock"
    public init() {}

    public func generate(system: String, user: String) async throws -> LLMResponse {
        let line = MockLLMClient.compose(user: user)
        return LLMResponse(
            text: line,
            promptTokens: MockLLMClient.estimateTokens(system + "\n" + user),
            outputTokens: MockLLMClient.estimateTokens(line)
        )
    }

    private static func estimateTokens(_ s: String) -> Int {
        max(1, s.split(whereSeparator: { $0 == " " || $0 == "\n" }).count * 4 / 3)
    }

    private static func compose(user: String) -> String {
        let trigger = user
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("TRIGGER:") })
            .map { $0.replacingOccurrences(of: "TRIGGER: ", with: "") } ?? ""

        let variants: [String]
        switch trigger {
        case "runStart":
            variants = [
                "Alright, let's roll — settle into a smooth rhythm and we'll build from here.",
                "Here we go. Easy first few minutes, find your breathing, the rest follows.",
                "Good to be out here with you. Loose shoulders, steady legs, let's move.",
            ]
        case "splitCompleted":
            variants = [
                "Clean split, that pace is right where we want it. Hold the cadence.",
                "That's a strong one — you're settling in nicely, keep it rolling.",
                "Locked in on that split. Breathing easy? Good. Stay patient.",
                "Right on rhythm there. Eyes up, shoulders down, carry it forward.",
            ]
        case "heartRateZoneChange":
            variants = [
                "Heart rate's climbing — breathe deep and hold this effort, you've got it.",
                "You just moved up a zone. That's the work. Stay relaxed through it.",
                "Effort's building. Control the breath and this pace stays comfortable.",
            ]
        case "runEnd":
            variants = [
                "That's the run — strong work start to finish. Walk it out and be proud.",
                "Done and done. You closed that out beautifully. Great session today.",
                "Finished strong. That's exactly how we wanted it. Recover well.",
            ]
        case "cheerReceived":
            variants = [
                "[playful] A friend just cheered you on — don't let them down, pick it up!",
                "[playful] Someone's rooting for you out there. Give 'em a show!",
            ]
        case "userSpoke":
            variants = [
                "Good question — you're on pace, just hold this effort steady to the finish.",
                "You're right where you should be. Keep the legs turning and trust it.",
            ]
        default:
            variants = ["Looking strong out there — keep it steady."]
        }
        let idx = abs(user.hashValue) % variants.count
        return variants[idx]
    }
}
