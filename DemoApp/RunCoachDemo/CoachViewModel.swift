import Foundation
import RunCoachHarness

/// Drives the harness from SwiftUI: builds the loop, observes telemetry for the dashboard,
/// and collects spoken lines + observability traces.
@MainActor
final class CoachViewModel: ObservableObject {
    enum SourceKind: String, CaseIterable, Identifiable {
        case simulated = "Simulated"
        case live = "Live GPS"
        var id: String { rawValue }
    }

    enum GoalKind: String, CaseIterable, Identifiable {
        case free = "Free"
        case distance = "Distance"
        case time = "Time"
        var id: String { rawValue }
    }

    /// A user-authored coach: free-text personality + a chosen Gemini voice.
    struct CustomCoach: Codable, Equatable {
        var name: String
        var instructions: String
        var voiceName: String
        var styleHint: String
    }

    // Configuration
    @Published var personaId: String = CoachPersona.motivational.id
    @Published var sourceKind: SourceKind = .simulated
    @Published var goalKind: GoalKind = .distance
    @Published var goalDistanceKm: Double = 5
    @Published var goalTimeMinutes: Double = 30
    @Published var speakAloud: Bool = true
    @Published private(set) var usingRealEngine = false
    @Published var customCoach: CustomCoach? { didSet { persistCustomCoach() } }
    @Published var apiKeyInput: String = KeyStore.load() ?? ""

    /// User-entered key (live, even before saving) wins; otherwise env/bundled fallback.
    var resolvedKey: String? {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Secrets.fallbackKey : trimmed
    }

    /// Whether Google (Gemini) voices/agent are available; otherwise Apple voice + mock.
    var googleVoicesAvailable: Bool { resolvedKey != nil }

    func saveAPIKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        trimmed.isEmpty ? KeyStore.clear() : KeyStore.save(trimmed)
    }

    func clearAPIKey() {
        apiKeyInput = ""
        KeyStore.clear()
    }

    /// The selected goal, assembled from the goal controls.
    var goal: RunGoal {
        switch goalKind {
        case .free:     return .free
        case .distance: return .distance(meters: goalDistanceKm * 1000)
        case .time:     return .time(seconds: goalTimeMinutes * 60)
        }
    }

    // Run state
    @Published private(set) var running = false
    @Published private(set) var distanceMeters: Double = 0
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var paceSecPerKm: Double?
    @Published private(set) var heartRate: Double?
    @Published private(set) var zone: String?

    // Coach + observability
    @Published private(set) var currentLine: String = "Pick a coach and tap Start."
    @Published private(set) var currentStyle: String = ""
    @Published private(set) var traces: [CoachTrace] = []

    private var task: Task<Void, Never>?
    private let location = LiveLocationProvider()

    // Persistent memory: accumulates real runs across launches; seeded once so recall has
    // history to show on first launch.
    private let journal = FileRunJournal(url: FileRunJournal.defaultURL())

    private let customCoachKey = "customCoach"

    init() {
        loadCustomCoach()
        let journal = self.journal
        Task {
            if await journal.allRuns().isEmpty {
                await journal.add(RunMemory(date: Date(timeIntervalSinceNow: -7 * 86_400), distanceMeters: 5000,
                                            duration: 1680, avgPaceSecPerKm: 336, bestSplitPaceSecPerKm: 318,
                                            notes: ["Faded on the final hill"]))
                await journal.add(RunMemory(date: Date(timeIntervalSinceNow: -3 * 86_400), distanceMeters: 5000,
                                            duration: 1625, avgPaceSecPerKm: 325, bestSplitPaceSecPerKm: 305,
                                            notes: ["Negative split, strong finish"]))
            }
        }
    }

    var persona: CoachPersona {
        if personaId == "custom", let c = customCoach {
            return .custom(name: c.name, voiceName: c.voiceName, styleHint: c.styleHint, instructions: c.instructions)
        }
        return CoachPersona.builtins.first { $0.id == personaId } ?? .motivational
    }

    /// Preview the coach: generate a greeting that matches the personality directive (real
    /// engine) and speak it in the chosen Gemini voice. Falls back to a generic line + Apple
    /// voice when no key is present.
    func previewVoice(voiceName: String, instructions: String) async {
        var line = "Alright, let's get moving — nice and easy to start. I've got you."
        if let key = resolvedKey {
            let system =
                "You are writing ONE short spoken greeting (under 90 characters) for a running " +
                "coach, to be played as a voice sample. Match this persona's tone and vocabulary " +
                "EXACTLY. No emojis, no hashtags, no quotation marks, no names. Return only the sentence."
            if let resp = try? await GeminiClient(apiKey: key).generate(system: system, user: "Persona: \(instructions)") {
                let text = resp.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { line = text }
            }
        }
        let synth: VoiceSynthesizer = resolvedKey
            .map { GeminiVoiceSynthesizer(apiKey: $0, voiceName: voiceName) } ?? AppleVoiceSynthesizer()
        await synth.speak(line)
    }

    /// Past runs, newest first (for the history screen).
    func loadHistory() async -> [RunMemory] {
        await journal.allRuns().sorted { $0.date > $1.date }
    }

    func clearHistory() async {
        await journal.removeAll()
    }

    private func loadCustomCoach() {
        if let data = UserDefaults.standard.data(forKey: customCoachKey),
           let coach = try? JSONDecoder().decode(CustomCoach.self, from: data) {
            customCoach = coach
        }
    }

    private func persistCustomCoach() {
        if let coach = customCoach, let data = try? JSONEncoder().encode(coach) {
            UserDefaults.standard.set(data, forKey: customCoachKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customCoachKey)
        }
    }

    // Derived observability totals
    var spokenCount: Int { traces.filter { $0.decision == "spoke" }.count }
    var skippedCount: Int { traces.filter { $0.decision != "spoke" }.count }
    var totalTokens: Int { traces.reduce(0) { $0 + $1.promptTokens + $1.outputTokens } }
    var totalCost: Double { traces.reduce(0) { $0 + $1.costUSD } }
    var avgLatencyMs: Int {
        let spoke = traces.filter { $0.decision == "spoke" }
        return spoke.isEmpty ? 0 : spoke.reduce(0) { $0 + $1.latencyMs } / spoke.count
    }

    func start() {
        guard !running else { return }
        running = true
        traces = []
        distanceMeters = 0; elapsed = 0; paceSecPerKm = nil; heartRate = nil; zone = nil
        currentLine = "…"; currentStyle = ""

        let key = resolvedKey
        usingRealEngine = key != nil

        // Tap telemetry for the dashboard.
        let onSnap: @Sendable (RunTelemetry) -> Void = { [weak self] snap in
            Task { @MainActor in self?.apply(snap) }
        }

        let base: TelemetrySource
        switch sourceKind {
        case .simulated:
            base = SimulatedRun(goal: goal, tickMillis: 140)
        case .live:
            location.start(goal: goal)
            let provider = location
            base = PollingTelemetrySource(intervalMillis: 1000) { await provider.snapshot() }
        }
        let source = ObservingSource(base: base, onSnapshot: onSnap)

        let tracer = BridgeTracer { [weak self] trace in
            Task { @MainActor in self?.ingest(trace) }
        }
        // Voice: Gemini TTS in the coach's chosen voice when a key exists, else Apple.
        let voiceName = persona.voiceName
        let synthesizer: VoiceSynthesizer? = speakAloud
            ? (key.map { GeminiVoiceSynthesizer(apiKey: $0, voiceName: voiceName) } ?? AppleVoiceSynthesizer())
            : nil
        let speech = BridgeSpeech(synthesizer: synthesizer) { [weak self] text, style in
            Task { @MainActor in
                self?.currentLine = text
                self?.currentStyle = style
            }
        }

        // Agentic loop: the model decides whether to speak and which tools to call.
        // Uses the real Gemini agent when a key is available (Secrets), else an offline
        // MockAgent so the demo always runs. Never hardcode a key here.
        let agent: CoachAgent = key.map { GeminiAgent(apiKey: $0) } ?? MockAgent()
        let critic: OutputCritic = key.map { LLMOutputCritic(client: GeminiClient(apiKey: $0)) } ?? NoOpCritic()

        let loop = AgenticCoachLoop(
            source: source,
            agent: agent,
            speech: speech,
            tracer: tracer,
            tools: AgentTools.coachDefaults + [RecallPastRunsTool(journal: journal)],
            critic: critic,
            journal: journal,
            memory: CoachMemory(persona: persona, profile: .demo),
            pricing: key == nil ? .free : .gemini25Flash
        )

        task = Task { [weak self] in
            await loop.run()
            await MainActor.run { self?.running = false }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        location.stop()
        running = false
    }

    private func apply(_ s: RunTelemetry) {
        distanceMeters = s.distanceMeters
        elapsed = s.elapsed
        paceSecPerKm = s.currentPaceSecPerKm
        heartRate = s.heartRate
        zone = s.heartRateZone
    }

    private func ingest(_ trace: CoachTrace) {
        traces.insert(trace, at: 0)              // newest first
        if traces.count > 60 { traces.removeLast(traces.count - 60) }
    }
}
