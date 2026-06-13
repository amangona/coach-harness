import Foundation

/// What we know about the runner from prior runs — fed into context for personalization.
public struct RunnerProfile: Sendable, Codable {
    public var name: String?
    public var avgDistanceMeters: Double?
    public var avgPaceSecPerKm: Double?
    public var bestSplitPaceSecPerKm: Double?

    public init(name: String? = nil, avgDistanceMeters: Double? = nil,
                avgPaceSecPerKm: Double? = nil, bestSplitPaceSecPerKm: Double? = nil) {
        self.name = name
        self.avgDistanceMeters = avgDistanceMeters
        self.avgPaceSecPerKm = avgPaceSecPerKm
        self.bestSplitPaceSecPerKm = bestSplitPaceSecPerKm
    }

    public static let demo = RunnerProfile(
        name: "Abe", avgDistanceMeters: 5000, avgPaceSecPerKm: 330, bestSplitPaceSecPerKm: 300
    )
}

/// PILLAR: Memory.
/// "Memory is everything that is not the LLM." Assembles the context object passed to the
/// engine on every speak-decision: persona + runner history + a rolling buffer of the
/// lines already said this run (so the coach never repeats an opener).
public struct CoachMemory: Sendable {
    public let persona: CoachPersona
    public let profile: RunnerProfile
    public let bufferSize: Int
    public private(set) var recentLines: [String] = []

    public init(persona: CoachPersona, profile: RunnerProfile, bufferSize: Int = 6) {
        self.persona = persona
        self.profile = profile
        self.bufferSize = bufferSize
    }

    public mutating func remember(_ line: String) {
        recentLines.append(line)
        if recentLines.count > bufferSize {
            recentLines.removeFirst(recentLines.count - bufferSize)
        }
    }

    /// The system instruction = base contract + persona directive.
    public var systemInstruction: String {
        CoachMemory.baseSystem + "\n\nPersona: " + persona.instructions
    }

    static let baseSystem =
        "You are a friendly, encouraging running coach. Give a short coaching message " +
        "(1-3 sentences, under 280 characters). Be specific about the runner's numbers. " +
        "Be warm but not over-the-top. No emojis. No hashtags. Speak naturally as if talking " +
        "to the runner mid-run. If a moment calls for playful banter or a joke, prefix your " +
        "entire message with [playful] — the prefix will be stripped before delivery."

    /// Build the user-content context block for a given tick.
    public func contextBlock(trigger: CoachingTrigger, telemetry t: RunTelemetry, toolNotes: [String]) -> String {
        var lines: [String] = []
        lines.append("TRIGGER: \(trigger.rawValue)")
        lines.append("")
        lines.append("Current metrics:")
        lines.append("- Distance: \(Fmt.dist(t.distanceMeters))")
        lines.append("- Elapsed: \(Fmt.dur(t.elapsed))")
        lines.append("- Current pace: \(Fmt.pace(t.currentPaceSecPerKm))")
        if let hr = t.heartRate, let z = t.heartRateZone {
            lines.append("- Heart rate: \(Int(hr)) bpm (\(z) zone)")
        }
        lines.append("- Elevation gain: \(Int(t.elevationGainMeters)) m")

        if let prog = t.goalProgress, let target = t.goalTargetMeters {
            lines.append("")
            lines.append("Goal: \(Fmt.dist(target)) — \(Int(prog * 100))% complete")
        }

        lines.append("")
        switch trigger {
        case .runStart:
            lines.append("This is the START of the run. Greet the runner and set the tone.")
        case .splitCompleted:
            lines.append("They just finished split #\(t.completedSplits) at \(Fmt.pace(t.lastSplitPaceSecPerKm)). React to it.")
        case .heartRateZoneChange:
            lines.append("Their heart-rate zone just changed to \(t.heartRateZone ?? "?"). Acknowledge it.")
        case .runEnd:
            lines.append("The run is FINISHED: \(Fmt.dist(t.distanceMeters)) in \(Fmt.dur(t.elapsed)). Congratulate them.")
        case .cheerReceived:
            lines.append("A friend just sent a cheer. Announce it energetically.")
        case .userSpoke:
            lines.append("The runner asked you something. Answer, referencing their current numbers.")
        }

        if let avg = profile.avgPaceSecPerKm {
            lines.append("")
            lines.append("Runner history: avg pace \(Fmt.pace(avg)), best split \(Fmt.pace(profile.bestSplitPaceSecPerKm)).")
        }

        if !toolNotes.isEmpty {
            lines.append("")
            lines.append("Tool notes:")
            toolNotes.forEach { lines.append("- \($0)") }
        }

        if !recentLines.isEmpty {
            lines.append("")
            lines.append("Lines you ALREADY said this run (do NOT repeat openers or phrasing — vary your angle):")
            recentLines.forEach { lines.append("- \"\($0)\"") }
        }

        return lines.joined(separator: "\n")
    }
}

/// Locale-light formatting helpers (metric, km).
enum Fmt {
    static func pace(_ secPerKm: Double?) -> String {
        guard let s = secPerKm, s > 0 else { return "—" }
        return String(format: "%d:%02d/km", Int(s) / 60, Int(s) % 60)
    }
    static func dist(_ m: Double) -> String { String(format: "%.2f km", m / 1000) }
    static func dur(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
