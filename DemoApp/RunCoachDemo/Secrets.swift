import Foundation

/// Resolves the Gemini API key WITHOUT ever hardcoding it in committed source.
///
/// Order of lookup:
///   1. `GEMINI_API_KEY` environment variable (handy for CLI / CI).
///   2. A gitignored `Secrets.plist` in the app bundle with a `GEMINI_API_KEY` string.
///
/// Returns nil if neither is present — the app then falls back to the offline MockAgent,
/// so it always builds and runs. To use the real engine, create
/// `DemoApp/RunCoachDemo/Secrets.plist` (already gitignored) containing your key.
enum Secrets {
    /// Env var or bundled plist. The user-entered Keychain key (see `CoachViewModel.resolvedKey`)
    /// takes precedence over this.
    static var fallbackKey: String? {
        if let env = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !env.isEmpty {
            return env
        }
        if let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
           let dict = NSDictionary(contentsOf: url),
           let key = dict["GEMINI_API_KEY"] as? String, !key.isEmpty {
            return key
        }
        return nil
    }
}
