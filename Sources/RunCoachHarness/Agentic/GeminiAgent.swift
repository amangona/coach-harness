import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The genuinely agentic engine: Gemini function-calling. The model is given the tools (plus
/// an implicit `stay_silent`) and runs a reason → call tool → observe → repeat loop until it
/// either emits a coaching line (plain text) or decides to stay quiet.
public struct GeminiAgent: CoachAgent {
    public let modelName: String
    private let apiKey: String
    private let session: URLSession
    private let maxSteps: Int

    public init(apiKey: String, modelName: String = "gemini-2.5-flash", maxSteps: Int = 4, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.modelName = modelName
        self.maxSteps = maxSteps
        self.session = session
    }

    private static let staySilentName = "stay_silent"

    public func decide(
        system: String,
        user: String,
        tools: [AgentTool],
        telemetry: RunTelemetry,
        profile: RunnerProfile
    ) async throws -> AgentOutcome {
        var contents: [Content] = [Content(role: "user", parts: [Part(text: user)])]
        var steps: [AgentStep] = []
        var promptTokens = 0
        var outputTokens = 0

        // Declare the lookup tools + a stay_silent tool so the model can choose silence.
        var declarations = tools.map {
            FunctionDeclaration(name: $0.name, description: $0.description, parameters: GeminiAgent.schema(for: $0))
        }
        declarations.append(FunctionDeclaration(
            name: GeminiAgent.staySilentName,
            description: "Call this if there is nothing useful or new worth saying to the runner at this moment.",
            parameters: .empty
        ))

        for _ in 0..<maxSteps {
            let response = try await send(system: system, contents: contents, declarations: declarations)
            promptTokens += response.usageMetadata?.promptTokenCount ?? 0
            outputTokens += response.usageMetadata?.candidatesTokenCount ?? 0

            guard let parts = response.candidates?.first?.content?.parts else { break }

            if let call = parts.compactMap({ $0.functionCall }).first {
                // Echo the model's function call back into the transcript.
                contents.append(Content(role: "model", parts: [Part(functionCall: call)]))

                if call.name == GeminiAgent.staySilentName {
                    steps.append(AgentStep(tool: GeminiAgent.staySilentName, result: "(model chose silence)"))
                    return .silent(steps: steps, promptTokens: promptTokens, outputTokens: outputTokens)
                }

                let result = await tools.first { $0.name == call.name }?
                    .invoke(args: call.args ?? [:], telemetry: telemetry, profile: profile) ?? "Unknown tool."
                steps.append(AgentStep(tool: call.name, result: result))

                // Feed the tool result back so the model can reason with it.
                contents.append(Content(
                    role: "user",
                    parts: [Part(functionResponse: FunctionResponse(name: call.name, response: .init(result: result)))]
                ))
                continue
            }

            // Plain text → the coaching line to speak.
            if let text = parts.compactMap({ $0.text }).first?.trimmingCharacters(in: .whitespacesAndNewlines),
               !text.isEmpty {
                return .speak(text: text, steps: steps, promptTokens: promptTokens, outputTokens: outputTokens)
            }
            break
        }

        // Ran out of steps without a clear line — safest is silence.
        return .silent(steps: steps, promptTokens: promptTokens, outputTokens: outputTokens)
    }

    // MARK: - Wire format

    private func send(system: String, contents: [Content], declarations: [FunctionDeclaration]) async throws -> Response {
        let urlStr = "https://generativelanguage.googleapis.com/v1beta/models/\(modelName):generateContent?key=\(apiKey)"
        guard let url = URL(string: urlStr) else { throw LLMError.badURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body = Request(
            systemInstruction: SystemInstruction(parts: [Part(text: system)]),
            contents: contents,
            tools: [ToolBlock(functionDeclarations: declarations)]
        )
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw LLMError.noResponse }
        guard (200..<300).contains(http.statusCode) else {
            throw LLMError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    // MARK: - Codable model (only the fields we use)

    private struct Part: Codable {
        var text: String?
        var functionCall: FunctionCall?
        var functionResponse: FunctionResponse?
    }
    private struct Content: Codable {
        let role: String
        let parts: [Part]
    }
    private struct SystemInstruction: Codable { let parts: [Part] }

    struct FunctionCall: Codable {
        let name: String
        // Coach tools take no arguments; we accept and ignore any args the model sends.
        let args: [String: String]?
        init(name: String, args: [String: String]? = nil) { self.name = name; self.args = args }
    }
    struct FunctionResponse: Codable {
        struct Wrapped: Codable { let result: String }
        let name: String
        let response: Wrapped
    }

    private struct PropertySchema: Codable {
        let type: String
        let description: String
    }
    private struct ParamSchema: Codable {
        let type: String
        let properties: [String: PropertySchema]
        let required: [String]?
        static let empty = ParamSchema(type: "object", properties: [:], required: nil)
    }
    private struct FunctionDeclaration: Codable {
        let name: String
        let description: String
        let parameters: ParamSchema
    }

    private static func schema(for tool: AgentTool) -> ParamSchema {
        guard !tool.parameters.isEmpty else { return .empty }
        var properties: [String: PropertySchema] = [:]
        var required: [String] = []
        for param in tool.parameters {
            properties[param.name] = PropertySchema(type: param.type, description: param.description)
            if param.required { required.append(param.name) }
        }
        return ParamSchema(type: "object", properties: properties, required: required.isEmpty ? nil : required)
    }
    private struct ToolBlock: Codable { let functionDeclarations: [FunctionDeclaration] }

    private struct Request: Codable {
        let systemInstruction: SystemInstruction
        let contents: [Content]
        let tools: [ToolBlock]
    }
    private struct Usage: Codable {
        let promptTokenCount: Int?
        let candidatesTokenCount: Int?
    }
    private struct Candidate: Codable { let content: Content? }
    private struct Response: Codable {
        let candidates: [Candidate]?
        let usageMetadata: Usage?
    }
}
