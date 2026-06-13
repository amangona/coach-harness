import Foundation

/// One step in the agent's reasoning trail: a tool it chose to call + what came back.
public struct AgentStep: Sendable, Codable {
    public let tool: String
    public let result: String
    public init(tool: String, result: String) {
        self.tool = tool
        self.result = result
    }
}

/// The agent's decision for a moment: speak a line, or deliberately stay silent. Either way
/// it carries the tool-call trail and token usage for observability.
public enum AgentOutcome: Sendable {
    case speak(text: String, steps: [AgentStep], promptTokens: Int, outputTokens: Int)
    case silent(steps: [AgentStep], promptTokens: Int, outputTokens: Int)

    public var steps: [AgentStep] {
        switch self {
        case .speak(_, let s, _, _), .silent(let s, _, _): return s
        }
    }
    public var promptTokens: Int {
        switch self {
        case .speak(_, _, let p, _), .silent(_, let p, _): return p
        }
    }
    public var outputTokens: Int {
        switch self {
        case .speak(_, _, _, let o), .silent(_, _, let o): return o
        }
    }
}

/// PILLAR: LLM + Loop, the agentic way. Unlike `LLMClient` (single text completion), a
/// `CoachAgent` is handed the tools and DECIDES: call tools to gather facts, then either
/// speak or stay silent. The model is the decider, not the surrounding code.
public protocol CoachAgent: Sendable {
    func decide(
        system: String,
        user: String,
        tools: [AgentTool],
        telemetry: RunTelemetry,
        profile: RunnerProfile
    ) async throws -> AgentOutcome
}

/// Offline agent: deterministically demonstrates the multi-step trail (consult a tool, then
/// speak) so the demo works without a network or key. The real reasoning is in `GeminiAgent`.
public struct MockAgent: CoachAgent {
    public init() {}

    public func decide(
        system: String,
        user: String,
        tools: [AgentTool],
        telemetry: RunTelemetry,
        profile: RunnerProfile
    ) async throws -> AgentOutcome {
        var steps: [AgentStep] = []
        let trigger = MockAgent.trigger(in: user)

        // At the start it recalls relevant history (Memory via a tool).
        if trigger == "runStart", let recall = tools.first(where: { $0.name == "recall_past_runs" }) {
            let result = await recall.invoke(args: ["query": "recent runs"], telemetry: telemetry, profile: profile)
            steps.append(AgentStep(tool: "recall_past_runs", result: result))
        }
        // The "model" decides to check for a PR when a split just completed.
        if trigger == "splitCompleted", let pr = tools.first(where: { $0.name == "compare_to_pr" }) {
            steps.append(AgentStep(tool: "compare_to_pr", result: await pr.invoke(args: [:], telemetry: telemetry, profile: profile)))
        }
        // On the final stretch it checks how much is left.
        if let p = telemetry.goalProgress, p >= 0.9, p < 1.0, let pace = tools.first(where: { $0.name == "pace_target" }) {
            steps.append(AgentStep(tool: "pace_target", result: await pace.invoke(args: [:], telemetry: telemetry, profile: profile)))
        }

        let line = MockAgent.compose(trigger: trigger, steps: steps)
        let pt = max(1, (system + user).split(whereSeparator: { $0 == " " || $0 == "\n" }).count * 4 / 3)
        let ot = max(1, line.split(separator: " ").count * 4 / 3)
        return .speak(text: line, steps: steps, promptTokens: pt, outputTokens: ot)
    }

    private static func trigger(in user: String) -> String {
        user.split(separator: "\n")
            .first(where: { $0.hasPrefix("TRIGGER:") })
            .map { $0.replacingOccurrences(of: "TRIGGER: ", with: "") } ?? ""
    }

    private static func compose(trigger: String, steps: [AgentStep]) -> String {
        if steps.contains(where: { $0.result.lowercased().contains("personal best") }) {
            return "That's a new personal best on that split — outstanding! Ride that momentum."
        }
        // Use recalled history to personalize the greeting (Memory showing up in the output).
        if trigger == "runStart",
           let recall = steps.first(where: { $0.tool == "recall_past_runs" }),
           !recall.result.lowercased().contains("no relevant") {
            return "Welcome back. Last time out: \(recall.result). Let's build on that — easy to start."
        }
        switch trigger {
        case "runStart":            return "Here we go — settle into an easy rhythm and we'll build from there."
        case "splitCompleted":      return "Clean split, right on pace. Stay relaxed and keep the cadence."
        case "heartRateZoneChange": return "Effort's stepping up — breathe deep and hold it, you're in control."
        case "runEnd":              return "That's the run — strong finish. Walk it out, you earned it."
        default:                    return "Looking strong out there — steady as you go."
        }
    }
}
