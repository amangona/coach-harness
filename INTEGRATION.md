# Integrating the harness into a live iOS app

The harness consumes telemetry through one protocol — `TelemetrySource`. The demo ships
`SimulatedRun`; production swaps in `PollingTelemetrySource`, which polls a closure that
reads your existing run services. **Nothing in the harness changes.**

```
┌────────────────────────────┐        ┌──────────────────────────────┐
│  iOS app (the tracker)      │        │  RunCoachHarness (the loop)   │
│                             │        │                               │
│  LocationService  ─┐        │        │   CoachLoop                   │
│  HealthKitService ─┼─ read ─┼──────▶ │     ← PollingTelemetrySource  │
│  RunService       ─┘        │ snapshot│     → CoachMemory / LLM /     │
│                             │ closure │       Guardrails / Tracer     │
│  (becomes a SpeechOutput    │◀───────┼──── speak(text, style)        │
│   that calls TTSService)    │        │                               │
└────────────────────────────┘        └──────────────────────────────┘
```

## 1. Bridge telemetry in

Construct a `PollingTelemetrySource` whose closure snapshots your services each tick. Note
the unit conversions: the app stores pace as **seconds per meter**, so multiply by 1000 for
the harness's **seconds per km**.

```swift
import RunCoachHarness

@MainActor
func makeTelemetrySource(
    location: LocationService,
    health: HealthKitService,
    run: RunService
) -> PollingTelemetrySource {
    PollingTelemetrySource(intervalMillis: 1000) {
        await MainActor.run {
            RunTelemetry(
                elapsed: run.currentRun?.elapsedExcludingPauses ?? 0,
                distanceMeters: location.totalDistance,
                currentPaceSecPerKm: location.currentPace.map { $0 * 1000 },      // s/m → s/km
                lastSplitPaceSecPerKm: location.completedSplits.last
                    .map { $0.pace },                                            // already s/km in Split
                heartRate: health.currentHeartRate,
                heartRateZone: health.heartRateZone?.rawValue,
                elevationGainMeters: location.totalElevationGain,
                completedSplits: location.completedSplits.count,
                goalType: run.activeGoal?.kindRawValue,                          // "distance" | "time"
                goalTargetMeters: run.activeGoal?.targetMeters,
                isGoalReached: run.isGoalReached,
                isFinished: !run.isRunning
            )
        }
    }
}
```

> The field names above are illustrative — map them to whatever your services actually
> expose. The only contract is: return a filled-in `RunTelemetry`, and set `isFinished`
> when the run ends so the loop halts and fires `runEnd`.

## 2. Bridge speech out

Wrap the existing TTS layer as a `SpeechOutput` so the harness's approved text flows back
into the app's audio pipeline (ducking, priority, talking-avatar metering, etc.):

```swift
struct AppSpeechOutput: SpeechOutput {
    let tts: TTSService
    func speak(_ text: String, style: String) async {
        await tts.speak(text, priority: .splitCompleted, style: StyleHint(rawValue: style) ?? .neutral)
    }
}
```

## 3. Run the loop alongside the run

```swift
let loop = CoachLoop(
    source: makeTelemetrySource(location: locationService, health: healthKitService, run: runService),
    llm: GeminiClient(apiKey: geminiKey),                 // or route through your Firebase callable
    speech: AppSpeechOutput(tts: ttsService),
    tracer: ConsoleTracer(),                              // swap for an OTel/analytics tracer in prod
    tools: [PaceTargetTool(), ComparePRTool(), WeatherTool()],
    memory: CoachMemory(
        persona: selectedCoach.toPersona(),               // built-in or the user's CustomCoach
        profile: RunnerProfile(/* from last ~10 runs */)
    )
)

Task { await loop.run() }   // completes when telemetry reports isFinished
```

## Why this shape

- **One harness, many sources.** The same loop runs against `SimulatedRun` in CI/demo and
  `PollingTelemetrySource` in production — identical decision logic, no `#if DEBUG`.
- **The app owns I/O, the harness owns judgement.** GPS, HealthKit, and audio stay in the
  app; *when and what to say* — and the guardrails around it — live in one testable place.
- **Custom coaches drop straight in.** A user's `CustomCoach` (name, voice, free-text
  instructions) maps to `CoachPersona.custom(...)` with zero loop changes.
