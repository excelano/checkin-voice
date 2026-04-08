// SettingsView.swift — CheckIn Voice
// Teams toggle and sign out
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SettingsView: View {
    var viewModel: CheckInViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 24) {
                // Teams toggle
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { viewModel.enableTeams },
                        set: { viewModel.enableTeams = $0 }
                    )) {
                        Text("Enable Teams")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                    .tint(.green)

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
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}
