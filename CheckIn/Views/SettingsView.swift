// SettingsView.swift — CheckIn Voice
// Teams toggle, voice settings, and sign out
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SettingsView: View {
    var viewModel: CheckInViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showReauthAlert = false

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Voice on Start toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { viewModel.voiceOnStart },
                        set: { viewModel.voiceOnStart = $0 }
                    )) {
                        Text("Voice on Start")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .tint(Brand.accent)

                    Text("Read your summary aloud when the app starts.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.gray)
                }

                Divider().overlay(Color.gray.opacity(0.3))

                // Teams toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { viewModel.enableTeams },
                        set: { newValue in
                            viewModel.enableTeams = newValue
                            if newValue {
                                showReauthAlert = true
                            }
                        }
                    )) {
                        Text("Enable Teams")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .tint(Brand.accent)

                    Text("Requires admin consent from your IT department. "
                         + "Email and calendar work without this.")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.gray)
                }

                Divider().overlay(Color.gray.opacity(0.3))

                // Sign out
                Button {
                    viewModel.signOut()
                    dismiss()
                } label: {
                    Text("Sign Out")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }

                Spacer()
            }
            .padding()
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Brand.bgDarker, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .alert("Sign In Again", isPresented: $showReauthAlert) {
            Button("Sign In") {
                viewModel.signOut()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                viewModel.enableTeams = false
            }
        } message: {
            Text("Teams requires additional permissions. You'll need to sign in again to grant access.")
        }
    }
}
