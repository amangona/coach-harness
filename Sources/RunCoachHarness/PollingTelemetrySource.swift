import Foundation

/// The production live bridge: a `TelemetrySource` that polls a caller-supplied closure
/// on a fixed cadence until the snapshot reports `isFinished`. An iOS app wires this up by
/// reading its own location / heart-rate / run services inside the closure — the harness
/// stays completely app-agnostic. See INTEGRATION.md.
public struct PollingTelemetrySource: TelemetrySource {
    private let interval: Duration
    private let snapshot: @Sendable () async -> RunTelemetry

    public init(intervalMillis: Int = 1000, snapshot: @escaping @Sendable () async -> RunTelemetry) {
        self.interval = .milliseconds(intervalMillis)
        self.snapshot = snapshot
    }

    public func stream() -> AsyncStream<RunTelemetry> {
        AsyncStream { continuation in
            let task = Task {
                while !Task.isCancelled {
                    let snap = await snapshot()
                    continuation.yield(snap)
                    if snap.isFinished { break }
                    try? await Task.sleep(for: interval)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
