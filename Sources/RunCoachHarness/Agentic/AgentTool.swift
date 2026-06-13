import Foundation

/// A parameter the model fills in when calling a tool.
public struct AgentToolParameter: Sendable {
    public let name: String
    public let type: String       // JSON-schema type, e.g. "string"
    public let description: String
    public let required: Bool
    public init(name: String, type: String = "string", description: String, required: Bool = true) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

/// A tool the *model itself* chooses to call during the agentic loop — the lecture's notion
/// of a tool, where the description IS the documentation the LLM reads to decide relevance.
public protocol AgentTool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [AgentToolParameter] { get }
    func invoke(args: [String: String], telemetry: RunTelemetry, profile: RunnerProfile) async -> String
}

public extension AgentTool {
    var parameters: [AgentToolParameter] { [] }   // most coach tools are parameter-free lookups
}

/// Adapts an existing parameter-free `CoachTool` into a model-callable `AgentTool`.
public struct CoachToolAgentAdapter: AgentTool {
    private let base: CoachTool
    public init(_ base: CoachTool) { self.base = base }
    public var name: String { base.schema.name }
    public var description: String { base.schema.description }
    public func invoke(args: [String: String], telemetry: RunTelemetry, profile: RunnerProfile) async -> String {
        base.note(for: telemetry, profile: profile) ?? "No notable result for this metric right now."
    }
}

public enum AgentTools {
    /// The default parameter-free coach toolset, model-callable.
    public static let coachDefaults: [AgentTool] = [
        CoachToolAgentAdapter(ComparePRTool()),
        CoachToolAgentAdapter(PaceTargetTool()),
        CoachToolAgentAdapter(WeatherTool()),
    ]
}

/// A REAL tool: it takes an argument and fetches state the model does NOT already have in
/// context — the runner's past runs from the journal. This is Memory + Tools composed.
public struct RecallPastRunsTool: AgentTool {
    private let journal: RunJournal
    public init(journal: RunJournal) { self.journal = journal }

    public let name = "recall_past_runs"
    public var description: String {
        "Search the runner's past runs for relevant history (e.g. 'final hill fade', 'fast 5k', " +
        "'this route'). Call this when prior context would make your coaching more specific and personal."
    }
    public var parameters: [AgentToolParameter] {
        [AgentToolParameter(name: "query", description: "What to look for in past runs.")]
    }

    public func invoke(args: [String: String], telemetry: RunTelemetry, profile: RunnerProfile) async -> String {
        let query = args["query"] ?? ""
        let runs = await journal.recall(query: query, limit: 3)
        guard !runs.isEmpty else { return "No relevant past runs found." }
        return runs.map { run in
            let head = "\(Fmt.dist(run.distanceMeters)) @ \(Fmt.pace(run.avgPaceSecPerKm))"
            return run.notes.first.map { "\(head) — \($0)" } ?? head
        }.joined(separator: "; ")
    }
}
