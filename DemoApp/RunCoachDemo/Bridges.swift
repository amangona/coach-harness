import Foundation
import RunCoachHarness

/// A `TelemetrySource` that taps every snapshot (for the live dashboard) before passing it
/// through to the loop unchanged.
struct ObservingSource: TelemetrySource {
    let base: TelemetrySource
    let onSnapshot: @Sendable (RunTelemetry) -> Void

    func stream() -> AsyncStream<RunTelemetry> {
        AsyncStream { continuation in
            let task = Task {
                for await snapshot in base.stream() {
                    onSnapshot(snapshot)
                    continuation.yield(snapshot)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Forwards observability traces out of the harness to a callback (→ SwiftUI).
final class BridgeTracer: Tracer, @unchecked Sendable {
    private let onTrace: @Sendable (CoachTrace) -> Void
    init(onTrace: @escaping @Sendable (CoachTrace) -> Void) { self.onTrace = onTrace }
    func record(_ trace: CoachTrace) { onTrace(trace) }
    func summary() -> String { "" }
}

/// Surfaces spoken lines to SwiftUI and, when a synthesizer is provided, speaks them aloud
/// (Gemini TTS voice if a key is set, else Apple). Pass `synthesizer: nil` to stay silent.
struct BridgeSpeech: SpeechOutput {
    let synthesizer: VoiceSynthesizer?
    let onSpeak: @Sendable (_ text: String, _ style: String) -> Void

    func speak(_ text: String, style: String) async {
        onSpeak(text, style)
        await synthesizer?.speak(text)
    }
}
