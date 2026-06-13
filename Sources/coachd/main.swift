import Foundation
import RunCoachHarness

// coachd — CLI demo of the running-coach harness.
//
//   swift run coachd                     # mock engine (offline), motivational coach
//   swift run coachd drillSergeant       # pick a built-in persona by id
//   GEMINI_API_KEY=… swift run coachd     # use the real Gemini 2.5 Flash engine
//   COACH_SAY=1 swift run coachd          # speak aloud via macOS `say`

let env = ProcessInfo.processInfo.environment

// Engine: real Gemini if a key is present, otherwise the deterministic mock.
let model = env["GEMINI_MODEL"] ?? "gemini-2.5-flash"
let llm: LLMClient
let pricing: Pricing
if let key = env["GEMINI_API_KEY"], !key.isEmpty {
    llm = GeminiClient(apiKey: key, modelName: model)
    pricing = .gemini25Flash
    print("⚙️  engine: Gemini (\(model))")
} else {
    llm = MockLLMClient()
    pricing = .free
    print("⚙️  engine: mock  (set GEMINI_API_KEY to use Gemini)")
}

// Flags + persona. `--agentic` runs the model-driven AgenticCoachLoop.
let cliArgs = Array(CommandLine.arguments.dropFirst())
let agentic = cliArgs.contains("--agentic")
let personaId = cliArgs.first { !$0.hasPrefix("--") }
let persona = CoachPersona.builtins.first { $0.id == personaId } ?? .motivational

// Output: console by default; `say` aloud when COACH_SAY=1.
let speech: SpeechOutput = (env["COACH_SAY"] == "1") ? SaySpeech() : ConsoleSpeech()

print("🏃 coach: \(persona.name) [\(persona.id)] · voice \(persona.voiceName)")
print("════════════════════════════════════════════════════════\n")

let tracer = ConsoleTracer()
let memory = CoachMemory(persona: persona, profile: .demo)

if agentic {
    print("🧠 mode: agentic (model decides speak/silent + which tools to call)\n")
    let apiKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"].flatMap { $0.isEmpty ? nil : $0 }
    let agent: CoachAgent = apiKey.map { GeminiAgent(apiKey: $0) } ?? MockAgent()
    let critic: OutputCritic = apiKey.map { LLMOutputCritic(client: GeminiClient(apiKey: $0)) } ?? NoOpCritic()

    // Memory: seed a few past runs so recall_past_runs has history to surface.
    let journal = InMemoryRunJournal(seed: [
        RunMemory(date: Date(timeIntervalSinceNow: -7 * 86_400), distanceMeters: 5000, duration: 1680,
                  avgPaceSecPerKm: 336, bestSplitPaceSecPerKm: 318, notes: ["Faded on the final hill"]),
        RunMemory(date: Date(timeIntervalSinceNow: -3 * 86_400), distanceMeters: 5000, duration: 1625,
                  avgPaceSecPerKm: 325, bestSplitPaceSecPerKm: 305, notes: ["Negative split, strong finish"]),
    ])

    let loop = AgenticCoachLoop(
        source: SimulatedRun(),
        agent: agent,
        speech: speech,
        tracer: tracer,
        tools: AgentTools.coachDefaults + [RecallPastRunsTool(journal: journal)],
        critic: critic,
        journal: journal,
        memory: memory,
        pricing: pricing
    )
    await loop.run()
} else {
    let loop = CoachLoop(
        source: SimulatedRun(),
        llm: llm,
        speech: speech,
        tracer: tracer,
        tools: [PaceTargetTool(), ComparePRTool(), WeatherTool()],
        memory: memory,
        pricing: pricing
    )
    await loop.run()
}

print("\n" + tracer.summary())
