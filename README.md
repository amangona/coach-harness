# coach-harness

A standalone AI **running coach harness** — it turns live run telemetry into spoken,
in-character coaching. The LLM is just the engine; the harness is the car around it.

Built on the six pillars: **LLM · Memory · Loop · Tools · Guardrails · Observability**.
See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full design and a diagram.

---

## Requirements

- **macOS.**
- **Swift 5.9+ toolchain** — for the command-line demo (`swift` is included with Xcode or the
  Command Line Tools). This is all you need to see the harness run.
- **Xcode 16 or later + an iOS 17+ simulator** — only if you also want the SwiftUI demo app.
- **No API key required.** Everything runs offline out of the box (a deterministic mock engine
  + Apple voice). A Google Gemini key is optional and unlocks the real LLM + Google voices.

---

## 1. Fastest way to see it run (≈10 seconds, no setup)

```bash
git clone https://github.com/amangona/coach-harness.git
cd coach-harness
swift run coachd
```

**What you'll see:** a simulated ~5 K run streamed on an accelerated clock. The coach speaks at
the start, on each km split, on heart-rate zone changes, and at the finish — and a live
**observability** readout prints each tick's trigger, decision (spoke / skipped + why), tokens,
cost, and latency, with a summary at the end.

Other CLI options:

```bash
swift run coachd --agentic          # model-driven loop: the model calls tools + decides to speak
swift run coachd drillSergeant      # pick a built-in coach (motivational | calmZen | drillSergeant | friendlyPacer)
swift test                          # 24 unit tests (guardrails + memory/recall)
```

> **Two loops ship side by side.** `CoachLoop` makes one LLM call per moment (predictable,
> production-shaped). `AgenticCoachLoop` (`--agentic`) lets the model call tools and decide
> whether to speak. See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the tradeoff.

---

## 2. Use the real Gemini engine (optional)

Without a key the demo uses a mock engine + Apple voice. To use the real **Gemini 2.5 Flash**
model (and Google TTS voices in the app):

1. Get a free key at **https://aistudio.google.com/apikey**.
2. For the CLI, pass it inline:

```bash
GEMINI_API_KEY=your_key_here swift run coachd --agentic
```

(In the iOS app you can instead paste the key in-app — see below.)

---

## 3. Run the SwiftUI demo app (optional)

```bash
open DemoApp/RunCoachDemo.xcodeproj
```

Then in Xcode:

1. Select an **iPhone simulator** (any iOS 17+) in the run-target dropdown.
2. Press **⌘R**. (On first open, Xcode resolves the local Swift package — give it a moment.
   No signing/team is needed for the simulator.)

To use the real engine + Google voices, open **Settings (🔑 top-right) → paste your Gemini key
→ Save** (stored in the device Keychain). Tap **🕘 (top-left)** to see run history.

For live GPS in the simulator, set a route via **Xcode ▸ Debug ▸ Simulate Location** or
`xcrun simctl location <udid> start …`.

### What the demo includes
- **Goal picker** — Free run, a **Distance** goal (1–10 km), or a **Time** goal (10–60 min).
- **Custom coaches** — *Create coach* to author one: a name, a free-text personality (the LLM
  persona directive), and a **Gemini TTS voice** with live, persona-matched preview.
- **Voices** — coaching spoken in the coach's Gemini voice when a key is set, else an Apple voice.
- **In-app API key** — resolution order: in-app (Keychain) → `GEMINI_API_KEY` env → bundled
  `Secrets.plist` (gitignored). No key → offline mock + Apple voice.
- **Run history** — past runs from the persistent journal the coach recalls from; each finished
  run is saved and personalizes the next.
- **Live observability** — tokens / cost / latency / decisions, with the model's tool-call trail.

---

## Project layout

```
Sources/RunCoachHarness/
  ├─ Telemetry / LLM / Memory / Personas / Tools / Guardrails / Observability / TTS / Voices
  ├─ Journal/      # persistent run journal — the cross-run Memory pillar
  ├─ Agentic/      # CoachAgent (Gemini function-calling) + AgenticCoachLoop + model-callable tools
  └─ CoachLoop     # deterministic loop (one completion per moment)
Sources/coachd/    # CLI demo (--agentic for the model-driven loop)
DemoApp/           # SwiftUI iOS sample app (consumes the package via local path)
ARCHITECTURE.md    # design doc / submission diagram
INTEGRATION.md     # how a production app bridges its real services into the harness
```
