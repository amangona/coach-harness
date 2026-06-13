import Foundation

/// PILLAR: Tools.
/// A tool is anything the harness controls. The key lesson: the *documentation* is for the
/// model — `schema` is how the engine (or the loop) knows when a tool is relevant. Here the
/// loop runs each tool every speak-decision and folds non-nil notes into context; the
/// schemas are surfaced in the trace so observability shows what was available.
public struct ToolSchema: Sendable {
    public let name: String
    public let description: String
    public let parameters: [String: String]   // param name -> what it means
    public init(name: String, description: String, parameters: [String: String] = [:]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public protocol CoachTool: Sendable {
    var schema: ToolSchema { get }
    /// Returns a short context note, or nil if not relevant for this snapshot.
    func note(for telemetry: RunTelemetry, profile: RunnerProfile) -> String?
}

/// How far / how fast to the goal from here.
public struct PaceTargetTool: CoachTool {
    public init() {}
    public let schema = ToolSchema(
        name: "pace_target",
        description: "Project finish time and report remaining distance toward a distance goal.",
        parameters: ["distanceMeters": "current distance", "goalTargetMeters": "the goal distance"]
    )
    public func note(for t: RunTelemetry, profile: RunnerProfile) -> String? {
        guard let target = t.goalTargetMeters, target > t.distanceMeters,
              let pace = t.currentPaceSecPerKm, pace > 0 else { return nil }
        let remainingM = target - t.distanceMeters
        let etaSec = remainingM / 1000 * pace
        return "\(Fmt.dist(remainingM)) to go; at current pace ~\(Fmt.dur(etaSec)) remaining."
    }
}

/// Is the latest split a personal best?
public struct ComparePRTool: CoachTool {
    public init() {}
    public let schema = ToolSchema(
        name: "compare_to_pr",
        description: "Compare the latest split pace against the runner's best-ever split pace.",
        parameters: ["lastSplitPaceSecPerKm": "latest split", "bestSplitPaceSecPerKm": "historical best"]
    )
    public func note(for t: RunTelemetry, profile: RunnerProfile) -> String? {
        guard let last = t.lastSplitPaceSecPerKm, last > 0,
              let best = profile.bestSplitPaceSecPerKm, best > 0 else { return nil }
        if last < best {
            return "That split (\(Fmt.pace(last))) is a NEW personal best — beats \(Fmt.pace(best))!"
        }
        return nil
    }
}

/// Conditions for pacing/hydration advice. Stubbed (no network) for a deterministic demo.
public struct WeatherTool: CoachTool {
    private let summary: String
    public init(summary: String = "14°C, light breeze, dry — good conditions for a steady effort.") {
        self.summary = summary
    }
    public let schema = ToolSchema(
        name: "weather",
        description: "Current weather conditions to inform pacing and hydration cues.",
        parameters: [:]
    )
    public func note(for t: RunTelemetry, profile: RunnerProfile) -> String? {
        // Only worth mentioning at the very start.
        t.elapsed < 60 ? "Conditions: \(summary)" : nil
    }
}
