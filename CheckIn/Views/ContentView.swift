// ContentView.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ContentView: View {
    var authService: AuthService
    @State private var isSigningIn = false
    @State private var errorMessage: String?
    @State private var viewModel: CheckInViewModel?
    @State private var permissionChecked = false

    var body: some View {
        if authService.isAuthenticated {
            let vm = viewModel ?? createViewModel()
            ZStack {
                SummaryView(viewModel: vm)

                // Floating mic button
                VStack {
                    Spacer()
                    micButton(vm: vm)
                        .padding(.bottom, 30)
                }
                .task {
                    if !permissionChecked {
                        permissionChecked = true
                        await vm.dictationService.requestPermission()
                    }
                }
            }
        } else {
            signInView
        }
    }

    private func createViewModel() -> CheckInViewModel {
        let vm = CheckInViewModel(authService: authService)
        Task { @MainActor in
            viewModel = vm
        }
        return vm
    }

    // MARK: - Floating Mic Button (Push-to-Talk)

    private func micButton(vm: CheckInViewModel) -> some View {
        ZStack {
            Circle()
                .fill(vm.dictationService.isListening ? Color.red : Brand.accent)
                .frame(width: 64, height: 64)
                .shadow(color: vm.dictationService.isListening
                        ? Color.red.opacity(0.5)
                        : Brand.accent.opacity(0.3),
                        radius: vm.dictationService.isListening ? 12 : 6)

            Image(systemName: vm.dictationService.isListening ? "mic.fill" : "mic")
                .font(.title2)
                .foregroundStyle(.white)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !vm.dictationService.isListening {
                        vm.speechService.stop()
                        vm.dictationService.startListening()
                    }
                }
                .onEnded { _ in
                    let transcript = vm.dictationService.stopListening()
                    if !transcript.isEmpty {
                        Task {
                            await vm.handleVoiceCommand(transcript)
                        }
                    }
                }
        )
        .disabled(!vm.dictationService.permissionGranted)
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
                _ = try await authService.signIn(enableTeams: false)
            } catch {
                print("Sign-in error: \(error)")
                errorMessage = "\(error)"
            }
            isSigningIn = false
        }
    }
}
