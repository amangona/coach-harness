// swift-tools-version:5.9
import PackageDescription

// RunCoachHarness — a standalone agent "harness" that turns live run telemetry
// into spoken coaching. Pure Swift, no app dependencies. Can you use any ticker
// becomes a TelemetrySource adapter; the harness itself is the six pillars:
// LLM · Memory · Loop · Tools · Guardrails · Observability.
let package = Package(
    name: "RunCoachHarness",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "RunCoachHarness", targets: ["RunCoachHarness"]),
        .executable(name: "coachd", targets: ["coachd"]),
    ],
    targets: [
        .target(name: "RunCoachHarness"),
        .executableTarget(
            name: "coachd",
            dependencies: ["RunCoachHarness"]
        ),
    ]
)
