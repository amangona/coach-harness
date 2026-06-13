import Foundation

/// PILLAR: The Loop — agentic variant.
///
/// Same cheap deterministic gate as `CoachLoop` (input guard → trigger → rate limit) decides
/// *candidate* moments, keeping cost/latency sane. But at each candidate, instead of one
/// fixed LLM completion, it hands control to a `CoachAgent`: the model calls tools as it sees
/// fit and decides whether to speak or stay silent. The agency lives in the model.
public actor AgenticCoachLoop {
    private let source: TelemetrySource
    private let agent: CoachAgent
    private let speech: SpeechOutput
    private let tracer: Tracer
    private let tools: [AgentTool]
    private let critic: OutputCritic
    private let journal: RunJournal?
    private let pricing: Pricing
    private let cooldown: TimeInterval
    private var memory: CoachMemory

    private var tick = 0
    private var started = false
    private var endFired = false
    private var lastSpokeElapsed: TimeInterval?
    private var lastSplitCount = 0
    private var lastZone: String?
    private var bestSplitSeen: Double?

    public init(
        source: TelemetrySource,
        agent: CoachAgent,
        speech: SpeechOutput,
        tracer: Tracer,
        tools: [AgentTool] = AgentTools.coachDefaults,
        critic: OutputCritic = NoOpCritic(),
        journal: RunJournal? = nil,
        memory: CoachMemory,
        pricing: Pricing = .gemini25Flash,
        cooldown: TimeInterval = 30
    ) {
        self.source = source
        self.agent = agent
        self.speech = speech
        self.tracer = tracer
        self.tools = tools
        self.critic = critic
        self.journal = journal
        self.memory = memory
        self.pricing = pricing
        self.cooldown = cooldown
    }

    private static let agentSystemSuffix =
        "\n\nYou are deciding, in real time, whether and what to say to a runner mid-run. " +
        "You may call tools to gather facts before deciding — only call a tool if its result " +
        "would change what you say. If nothing new or useful warrants speaking right now, call " +
        "stay_silent. Otherwise, once you have what you need, reply with ONLY the coaching line " +
        "to speak (no preamble)."

    public func run() async {
        // Memory: derive the runner's profile from journalled history before coaching starts.
        if let journal {
            let runs = await journal.allRuns()
            memory.profile = .derived(from: runs, name: memory.profile.name)
        }
        for await snapshot in source.stream() {
            await handle(snapshot)
        }
    }

    private func handle(_ t: RunTelemetry) async {
        tick += 1

        let input = InputGuard.check(t)
        guard input.passed else {
            record(t, trigger: "—", decision: "skipped: input guard (\(input.reason ?? "?"))")
            return
        }
        // Track the fastest split for the journal record.
        if let split = t.lastSplitPaceSecPerKm, split > 0 {
            bestSplitSeen = min(bestSplitSeen ?? .greatestFiniteMagnitude, split)
        }

        guard let trigger = deriveTrigger(t) else { return }

        // Memory: persist the completed run so the coach learns for next time.
        if trigger == .runEnd, let journal {
            await journal.add(makeRecord(t))
        }

        if !trigger.bypassesRateLimit, let last = lastSpokeElapsed, t.elapsed - last < cooldown {
            record(t, trigger: trigger.rawValue, decision: "skipped: rate-limited")
            return
        }

        let system = memory.systemInstruction + AgenticCoachLoop.agentSystemSuffix
        // No pre-run tools here: the model decides which to call.
        let user = memory.contextBlock(trigger: trigger, telemetry: t, toolNotes: [])

        let clock = ContinuousClock()
        let start = clock.now
        let outcome: AgentOutcome
        do {
            outcome = try await agent.decide(system: system, user: user, tools: tools, telemetry: t, profile: memory.profile)
        } catch {
            record(t, trigger: trigger.rawValue, decision: "skipped: agent error (\(error))")
            return
        }
        let latencyMs = Int(start.duration(to: clock.now) / .milliseconds(1))
        let cost = pricing.cost(prompt: outcome.promptTokens, output: outcome.outputTokens)
        let toolCalls = outcome.steps.map { $0.tool }

        switch outcome {
        case .silent:
            record(t, trigger: trigger.rawValue, decision: "skipped: agent chose silence",
                   prompt: outcome.promptTokens, out: outcome.outputTokens, latencyMs: latencyMs,
                   cost: cost, toolCalls: toolCalls)

        case .speak(let raw, _, _, _):
            let (clean, isPlayful) = OutputGuard.stripPlayful(raw)
            let output = OutputGuard.validate(clean, recent: memory.recentLines)
            guard output.passed else {
                record(t, trigger: trigger.rawValue, decision: "skipped: output guard (\(output.reason ?? "?"))",
                       prompt: outcome.promptTokens, out: outcome.outputTokens, latencyMs: latencyMs,
                       cost: cost, toolCalls: toolCalls)
                return
            }
            // Second-opinion LLM critic (no-op unless configured).
            let verdict = await critic.review(output.text, persona: memory.persona)
            guard verdict.passed else {
                record(t, trigger: trigger.rawValue, decision: "skipped: \(verdict.reason ?? "critic")",
                       prompt: outcome.promptTokens, out: outcome.outputTokens, latencyMs: latencyMs,
                       cost: cost, toolCalls: toolCalls)
                return
            }
            let style = styleHint(trigger: trigger, telemetry: t, isPlayful: isPlayful)
            await speech.speak(output.text, style: style)
            memory.remember(output.text)
            lastSpokeElapsed = t.elapsed
            record(t, trigger: trigger.rawValue, decision: "spoke",
                   prompt: outcome.promptTokens, out: outcome.outputTokens, latencyMs: latencyMs,
                   cost: cost, text: output.text, toolCalls: toolCalls)
        }
    }

    /// Build a journal entry from the finished run, with human-meaningful notes.
    private func makeRecord(_ t: RunTelemetry) -> RunMemory {
        var notes = ["Ran \(Fmt.dist(t.distanceMeters)) in \(Fmt.dur(t.elapsed))."]
        if let best = bestSplitSeen, let prior = memory.profile.bestSplitPaceSecPerKm, best < prior {
            notes.append("New best split at \(Fmt.pace(best)).")
        }
        if let p = t.currentPaceSecPerKm, let avg = memory.profile.avgPaceSecPerKm, p < avg {
            notes.append("Strong, fast finish.")
        }
        return RunMemory(
            date: Date(),
            distanceMeters: t.distanceMeters,
            duration: t.elapsed,
            avgPaceSecPerKm: t.currentPaceSecPerKm ?? memory.profile.avgPaceSecPerKm ?? 0,
            bestSplitPaceSecPerKm: bestSplitSeen,
            elevationGainMeters: t.elevationGainMeters,
            notes: notes
        )
    }

    private func deriveTrigger(_ t: RunTelemetry) -> CoachingTrigger? {
        if !started {
            started = true
            lastSplitCount = t.completedSplits
            lastZone = t.heartRateZone
            return .runStart
        }
        if t.isFinished {
            guard !endFired else { return nil }
            endFired = true
            return .runEnd
        }
        if t.completedSplits > lastSplitCount {
            lastSplitCount = t.completedSplits
            return .splitCompleted
        }
        if let zone = t.heartRateZone, zone != lastZone {
            lastZone = zone
            return .heartRateZoneChange
        }
        return nil
    }

    private func styleHint(trigger: CoachingTrigger, telemetry t: RunTelemetry, isPlayful: Bool) -> String {
        if isPlayful { return "playful" }
        if trigger == .runEnd { return "calm" }
        if let p = t.goalProgress, p >= 0.9, p < 1.0 { return "intense" }
        if let last = t.lastSplitPaceSecPerKm, let best = memory.profile.bestSplitPaceSecPerKm,
           last > 0, last < best { return "enthusiastic" }
        return memory.persona.styleHint
    }

    private func record(_ t: RunTelemetry, trigger: String, decision: String,
                        prompt: Int = 0, out: Int = 0, latencyMs: Int = 0,
                        cost: Double = 0, text: String? = nil, toolCalls: [String]? = nil) {
        tracer.record(CoachTrace(
            tick: tick, elapsed: t.elapsed, trigger: trigger, decision: decision,
            promptTokens: prompt, outputTokens: out, latencyMs: latencyMs,
            costUSD: cost, text: text, toolCalls: toolCalls
        ))
    }
}
