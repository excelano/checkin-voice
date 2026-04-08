// ReplyView.swift — CheckIn Voice
// Voice dictation or keyboard reply with confirm/cancel
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct ReplyView: View {
    var viewModel: CheckInViewModel
    let item: Item
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    // Who you're replying to
                    Text("Replying to \(item.fromName)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)

                    // Text input
                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3))
                        )
                        .frame(minHeight: 120)
                        .focused($isFocused)

                    // Send button
                    Button {
                        send()
                    } label: {
                        HStack {
                            if viewModel.isSending {
                                ProgressView()
                                    .tint(.black)
                            }
                            Text(viewModel.isSending ? "Sending..." : "Send")
                        }
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Color.gray : Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isSending)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.red)
                }
            }
            .onAppear { isFocused = true }
        }
        .preferredColorScheme(.dark)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }

        Task {
            switch item {
            case .email(let email):
                await viewModel.replyToEmail(email, comment: text)
            case .chat(let chat):
                await viewModel.replyToChat(chat, text: text)
            }
            await viewModel.fetchSummary()
            dismiss()
        }
    }
}
