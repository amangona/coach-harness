# coach-harness

A standalone AI **running coach harness** — it turns live run telemetry into spoken,
in-character coaching. The LLM is just the engine; the harness is the car around it.

Built on the six pillars: **LLM · Memory · Loop · Tools · Guardrails · Observability**.
See [`ARCHITECTURE.md`](./ARCHITECTURE.md) for the full design.

## Quick start

```bash
swift run coachd            # runs the loop against a simulated run (mock LLM)
GEMINI_API_KEY=… swift run coachd   # use the real Gemini 2.5 Flash engine
```

## Layout

```
Sources/RunCoachHarness/   # the six pillars (pure Swift, no app deps)
Sources/coachd/            # CLI demo that wires a telemetry source + LLM + tracer
ARCHITECTURE.md            # design doc / submission diagram
```
