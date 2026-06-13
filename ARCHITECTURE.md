# RunCoachHarness — Architecture

A standalone agent **harness** that turns live run telemetry into spoken, in-character
coaching. The harness is the *car*; the LLM is just the *engine*. Everything that makes
the model useful and safe lives in the six pillars below.

> Built on an existing in-app AI running coach, lifted out of the iOS app into a clean,
> observable, standalone loop. The app becomes one telemetry adapter, not the whole system.

---

## One-line summary

> A live running coach: on every tick of run telemetry, the harness decides **whether**
> to speak and **what** to say — in the user's chosen coach persona — guarded for safety
> and brevity, and fully instrumented for tokens, cost, and latency.

---

## The six pillars

```
                          ┌─────────────────────────────────────────────┐
   LIVE RUN               │                  THE LOOP                     │
   (TelemetrySource)      │   tick → derive trigger → decide → speak      │
        │                 │                                               │
        │  RunTelemetry    │   ┌──────────┐   ┌──────────┐   ┌──────────┐ │
        ├────────────────▶│   │ GUARDRAIL│   │  MEMORY   │   │  TOOLS   │ │
        │  (pace, dist,    │   │  (input) │   │ (context) │   │ (lookups)│ │
        │   HR, splits,    │   └────┬─────┘   └────┬─────┘   └────┬─────┘ │
        │   goal, zone)    │        └──── build context ──────────┘       │
        │                 │                    │                          │
        │                 │              ┌─────▼─────┐                    │
        │                 │              │    LLM    │  (Gemini 2.5 Flash)│
        │                 │              │  (engine) │                    │
        │                 │              └─────┬─────┘                    │
        │                 │              ┌─────▼─────┐                    │
        │                 │              │ GUARDRAIL │  (output: ≤280 ch, │
        │                 │              │  (output) │   on-persona, safe)│
        │                 │              └─────┬─────┘                    │
        │                 │              ┌─────▼─────┐                    │
        │                 │              │    TTS    │ ──▶ 🔊 spoken line  │
        │                 │              └───────────┘                    │
        │                 │                                               │
        │                 │   every tick ▶ OBSERVABILITY                  │
        │                 │   (trigger, decision, tokens, cost, latency)  │
        │                 └─────────────────────────────────────────────┘
```

### 1. LLM — the engine
- **Stateless.** Text in, text out. Knows nothing on its own.
- Model: **Gemini 2.5 Flash** (parity with the production app).
- Abstracted behind an `LLMClient` protocol so a deterministic mock can drive
  offline demos; the Gemini client parses `usageMetadata` for real token counts.

### 2. Memory — everything that is *not* the LLM
The harness assembles a context object on every speak-decision:
- **Coach persona** — built-in (motivational / calm-zen / drill-sergeant / friendly-pacer)
  or a **user-authored custom coach** (name, voice, free-text instructions). This is the
  customization surface.
- **Runner profile / history** — avg distance, avg pace, best split, typical HR (last ~10 runs).
- **Session buffer** — the last 6 lines the coach already said this run, so it does not
  repeat openers or hooks. ("Vary your angle.")
- **Current telemetry** — the live snapshot for this tick.

### 3. The Loop — "do something *until*"
- Consumes `RunTelemetry` snapshots from a `TelemetrySource`.
- **Derives a trigger** by diffing consecutive snapshots: first snapshot → `runStart`;
  `completedSplits` increased → `splitCompleted`; `heartRateZone` changed →
  `heartRateZoneChange`; stream ends / goal reached → `runEnd`.
- **Halt condition:** the run finishes (telemetry `isFinished`) or the stream completes.
- **Decider / brakes:** a 30s rate-limit cooldown between utterances (bypassed by
  high-priority moments: start, end, cheers, user questions) — this is the "bumper" that
  prevents a runaway, chatty loop.

### 4. Tools — anything the harness controls
- Documented, schema-described helpers the coach can draw on, e.g.
  `pace_target` (what pace hits the goal from here), `compare_to_pr` (is this split a PR?),
  `weather` (conditions for pacing/hydration advice).
- **The documentation is for the model** — the schema/description is how it knows when a
  tool is relevant. Schemas are surfaced in the trace for observability.

### 5. Guardrails — bumper bowling
- **Input guard:** sanity-check telemetry before acting (implausible pace/HR, GPS dropout)
  so the coach never reacts to garbage.
- **Output guard:** enforce the brand/safety contract before anything is spoken —
  ≤ 280 characters, no emojis/hashtags, strip the internal `[playful]` control token,
  reject medical claims, reject near-duplicates of recent lines. Can escalate to a second
  LLM pass if a line looks off.

### 6. Observability — "if you can't see it, you can't fix it"
Every tick emits a structured trace record:
- which **trigger** fired,
- the **decision** (`spoke` / `skipped: rate-limited` / `skipped: guardrail`),
- **tokens** (prompt + output, from Gemini `usageMetadata`),
- **cost** (tokens × 2.5-Flash rate),
- **latency** (model round-trip),
- the **text** delivered.

Emitted as JSON-lines + a live console panel; running totals for tokens/cost/latency at
run end. This is also the demo's "wow" surface — judges watch the coach think tick-by-tick.

---

## The live bridge (key design decision)

Telemetry enters through a single protocol:

```swift
protocol TelemetrySource {
    func stream() -> AsyncStream<RunTelemetry>
}
```

- **Demo:** a `SimulatedRun` source (and JSONL replay) — runs anywhere, even on bad
  conference wifi, deterministic for judging.
- **Production:** the app conforms its real location / heart-rate / run services to the
  same protocol → the existing app becomes a live telemetry adapter with **zero changes to
  the harness**. One harness, many sources.

---

## Module map

| File | Pillar | Responsibility |
|------|--------|----------------|
| `Telemetry.swift` | (input) | `RunTelemetry` snapshot, `CoachingTrigger`, `TelemetrySource` protocol |
| `LLM.swift` | LLM | `LLMClient` protocol, `GeminiClient` (REST + usage), `MockLLMClient` |
| `Memory.swift` | Memory | persona + profile + rolling session buffer → context assembly |
| `Personas.swift` | Memory | built-in personas + custom-coach model |
| `CoachLoop.swift` | Loop | tick → derive trigger → decide → generate → speak → record |
| `Tools.swift` | Tools | `CoachTool` protocol + sample documented tools |
| `Guardrails.swift` | Guardrails | input sanity + output safety/brevity/anti-repeat |
| `Observability.swift` | Observability | `CoachTrace`, `Tracer`, token/cost/latency tallies |
| `TTS.swift` | (output) | `SpeechOutput` protocol + console/`say` sinks |
| `Sources/coachd/main.swift` | — | CLI demo: wires a source + LLM + tracer and runs the loop |

---

## Demo flow

1. `swift run coachd` (uses `MockLLMClient` by default; set `GEMINI_API_KEY` for the real engine).
2. `SimulatedRun` streams a ~5K run on an accelerated clock.
3. The loop speaks on start, each km split, HR-zone changes, and the finish — in the
   selected persona.
4. A live observability panel prints trigger / decision / tokens / cost / latency per tick,
   with run-end totals.
