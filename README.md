# coach-harness

A standalone AI **running coach harness** — it turns live run telemetry into spoken,
in-character coaching. The LLM is just the engine; the harness is the car around it.

Built on the six pillars: **LLM · Memory · Loop · Tools · Guardrails · Observability**.
See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full design.

## Quick start

```bash
swift run coachd                      # deterministic loop, simulated run, mock LLM
swift run coachd --agentic            # model-driven loop (model decides speak/silent + tools)
swift run coachd drillSergeant        # pick a built-in coach persona
GEMINI_API_KEY=… swift run coachd     # use the real Gemini 2.5 Flash engine
swift test                            # 24 unit tests (guardrails + journal/recall)
```

Two loops ship side by side: **`CoachLoop`** (one completion per moment — predictable,
production-shaped) and **`AgenticCoachLoop`** (the model calls tools and decides whether to
speak). See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the tradeoff.

## SwiftUI demo app

`DemoApp/RunCoachDemo.xcodeproj` is a sample iOS app that consumes the harness as a local
Swift package, with a polished UI (coral accent, rounded stat cards, accent chips). It runs
the agentic loop live and includes:

- **Goal picker** — Free run, a **Distance** goal (1–10 km), or a **Time** goal (10–60 min).
- **Custom coaches** — tap *Create coach* to author one: a name, a free-text
  personality (the LLM persona directive), and a **Google (Gemini) TTS voice** from a catalog,
  with live persona-matched preview.
- **Voices** — coaching is spoken in the coach's Gemini voice when a key is set; otherwise an
  Apple voice is used.
- **API key in-app** — the 🔑 (Settings) screen takes a Gemini key, stored in the **Keychain**.
  Resolution order: in-app key → `GEMINI_API_KEY` env → bundled `Secrets.plist` (gitignored).
  With no key it falls back to the offline mock agent + Apple voice.
- **Run history** — the 🕘 screen lists past runs from the persistent journal (the Memory the
  coach recalls from); each finished run is saved and used to personalize the next.
- **Live observability** — tokens / cost / latency / decisions, with the model's tool-call trail.

```bash
# build & run in the simulator
open DemoApp/RunCoachDemo.xcodeproj          # then ⌘R
# or from the CLI (any booted iOS 26 sim UDID):
xcodebuild -project DemoApp/RunCoachDemo.xcodeproj -scheme RunCoachDemo \
  -destination 'id=<SIM_UDID>' build
```

For live GPS in the simulator, set a route via **Xcode ▸ Debug ▸ Simulate Location** or
`xcrun simctl location <udid> start …`.

## Layout

```
Sources/RunCoachHarness/
  ├─ Telemetry / LLM / Memory / Personas / Tools / Guardrails / Observability / TTS / Voices
  ├─ Journal/      # persistent run journal — the cross-run Memory pillar
  ├─ Agentic/      # CoachAgent (Gemini function-calling) + AgenticCoachLoop + model-callable tools
  └─ CoachLoop     # deterministic loop (one completion per moment)
Sources/coachd/    # CLI demo (--agentic for the model-driven loop)
DemoApp/           # SwiftUI iOS sample app (consumes the package via local path)
ARCHITECTURE.md    # design doc / submission diagram
INTEGRATION.md     # how a production app bridges its services into the harness
```
