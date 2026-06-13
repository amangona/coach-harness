import Foundation

/// PILLAR: The Loop — "do something *until*".
/// Consumes telemetry snapshots, derives a trigger, applies the brakes (input guard +
/// rate limit), builds context (memory + tools), calls the engine, guards the output,
/// speaks it, and records a trace. Halts when the run finishes.
public actor CoachLoop {
    private let source: TelemetrySource
    private let llm: LLMClient
    private let speech: SpeechOutput
    private let tracer: Tracer
    private let tools: [CoachTool]
    private let pricing: Pricing
    private let cooldown: TimeInterval
    private var memory: CoachMemory

    // Loop state.
    private var tick = 0
    private var started = false
    private var endFired = false
    private var lastSpokeElapsed: TimeInterval?
    private var lastSplitCount = 0
    private var lastZone: String?

    public init(
        source: TelemetrySource,
        llm: LLMClient,
        speech: SpeechOutput,
        tracer: Tracer,
        tools: [CoachTool],
        memory: CoachMemory,
        pricing: Pricing = .gemini25Flash,
        cooldown: TimeInterval = 30
    ) {
        self.source = source
        self.llm = llm
        self.speech = speech
        self.tracer = tracer
        self.tools = tools
        self.memory = memory
        self.pricing = pricing
        self.cooldown = cooldown
    }

    public func run() async {
        for await snapshot in source.stream() {
            await handle(snapshot)
        }
    }

    private func handle(_ t: RunTelemetry) async {
        tick += 1

        // 1. Input guardrail — never react to garbage.
        let input = InputGuard.check(t)
        guard input.passed else {
            record(t, trigger: "—", decision: "skipped: input guard (\(input.reason ?? "?"))")
            return
        }

        // 2. Derive the trigger (the decider).
        guard let trigger = deriveTrigger(t) else { return }

        // 3. Rate limit — the brakes that stop a runaway, chatty loop.
        if !trigger.bypassesRateLimit, let last = lastSpokeElapsed, t.elapsed - last < cooldown {
            record(t, trigger: trigger.rawValue, decision: "skipped: rate-limited")
            return
        }

        // 4. Tools → context notes.
        let notes = tools.compactMap { $0.note(for: t, profile: memory.profile) }

        // 5. Build context (memory) and call the engine (LLM), timed.
        let system = memory.systemInstruction
        let user = memory.contextBlock(trigger: trigger, telemetry: t, toolNotes: notes)

        let clock = ContinuousClock()
        let start = clock.now
        let response: LLMResponse
        do {
            response = try await llm.generate(system: system, user: user)
        } catch {
            record(t, trigger: trigger.rawValue, decision: "skipped: llm error (\(error))")
            return
        }
        let latencyMs = Int(start.duration(to: clock.now) / .milliseconds(1))
        let cost = pricing.cost(prompt: response.promptTokens, output: response.outputTokens)

        // 6. Output guardrail.
        let (clean, isPlayful) = OutputGuard.stripPlayful(response.text)
        let output = OutputGuard.validate(clean, recent: memory.recentLines)
        guard output.passed else {
            record(t, trigger: trigger.rawValue, decision: "skipped: output guard (\(output.reason ?? "?"))",
                   prompt: response.promptTokens, out: response.outputTokens, latencyMs: latencyMs, cost: cost)
            return
        }

        // 7. Speak, remember, record.
        let style = styleHint(trigger: trigger, telemetry: t, isPlayful: isPlayful)
        await speech.speak(output.text, style: style)
        memory.remember(output.text)
        lastSpokeElapsed = t.elapsed

        record(t, trigger: trigger.rawValue, decision: "spoke",
               prompt: response.promptTokens, out: response.outputTokens,
               latencyMs: latencyMs, cost: cost, text: output.text)
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

    /// Maps the moment to a prosody style for TTS (mirrors the app's classifyStyleHint).
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
                        cost: Double = 0, text: String? = nil) {
        tracer.record(CoachTrace(
            tick: tick, elapsed: t.elapsed, trigger: trigger, decision: decision,
            promptTokens: prompt, outputTokens: out, latencyMs: latencyMs,
            costUSD: cost, text: text
        ))
    }
}
