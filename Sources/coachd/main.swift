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

// Persona: built-in id from the first arg, default motivational.
let personaId = CommandLine.arguments.dropFirst().first
let persona = CoachPersona.builtins.first { $0.id == personaId } ?? .motivational

// Output: console by default; `say` aloud when COACH_SAY=1.
let speech: SpeechOutput = (env["COACH_SAY"] == "1") ? SaySpeech() : ConsoleSpeech()

print("🏃 coach: \(persona.name) [\(persona.id)] · voice \(persona.voiceName)")
print("════════════════════════════════════════════════════════\n")

let tracer = ConsoleTracer()
let loop = CoachLoop(
    source: SimulatedRun(),
    llm: llm,
    speech: speech,
    tracer: tracer,
    tools: [PaceTargetTool(), ComparePRTool(), WeatherTool()],
    memory: CoachMemory(persona: persona, profile: .demo),
    pricing: pricing
)

await loop.run()

print("\n" + tracer.summary())
