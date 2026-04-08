// ContentView.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ContentView: View {
    var authService: AuthService
    @State private var isSigningIn = false
    @State private var errorMessage: String?

    var body: some View {
        if authService.isAuthenticated {
            SummaryView(viewModel: CheckInViewModel(authService: authService))
        } else {
            signInView
        }
    }

    // MARK: - Sign In

    private var signInView: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("CheckIn")
                .font(.system(.largeTitle, design: .monospaced))
                .fontWeight(.bold)

            Text("Sign in with your Microsoft 365 account to get started.")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                signIn()
            } label: {
                HStack(spacing: 8) {
                    if isSigningIn {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(isSigningIn ? "Signing In..." : "Sign In with Microsoft")
                }
                .font(.system(.body, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .frame(maxWidth: 280)
                .padding(.vertical, 14)
                .background(Color.blue)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(isSigningIn)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    // MARK: - Actions

    private func signIn() {
        isSigningIn = true
        errorMessage = nil

        Task {
            do {
                // Teams disabled for now — Settings toggle will control this later
                _ = try await authService.signIn(enableTeams: false)
            } catch {
                print("Sign-in error: \(error)")
                errorMessage = "\(error)"
            }
            isSigningIn = false
        }
    }
}
