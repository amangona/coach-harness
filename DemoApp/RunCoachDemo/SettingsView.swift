import SwiftUI

/// In-app API key entry — stored in the Keychain, takes precedence over any bundled key.
struct SettingsView: View {
    @ObservedObject var vm: CoachViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Google Gemini API key") {
                    SecureField("AIza… or AQ.…", text: $vm.apiKeyInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Save key") { vm.saveAPIKey() }
                        .disabled(vm.apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Clear key", role: .destructive) { vm.clearAPIKey() }
                }

                Section {
                    Label(
                        vm.googleVoicesAvailable ? "Using Google Gemini — real voices + agent" : "No key — Apple voice + mock agent",
                        systemImage: vm.googleVoicesAvailable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(vm.googleVoicesAvailable ? .green : .orange)
                } footer: {
                    Text("Stored in this device's Keychain — never synced or committed. Get a key at aistudio.google.com.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
