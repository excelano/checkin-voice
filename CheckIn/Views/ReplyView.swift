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
                Brand.bg.ignoresSafeArea()

                VStack(alignment: .leading, spacing: 16) {
                    Text("Replying to \(item.fromName)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Brand.accent)

                    TextEditor(text: $draft)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                        .scrollContentBackground(.hidden)
                        .background(Brand.bgDarker)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Brand.accentDim.opacity(0.3))
                        )
                        .frame(minHeight: 120)
                        .focused($isFocused)

                    Spacer()
                }
                .padding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Brand.bgDarker, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(.red)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if viewModel.isSending {
                        ProgressView()
                            .tint(Brand.accent)
                    } else {
                        Button { send() } label: {
                            Image(systemName: "paperplane.fill")
                                .foregroundStyle(draft.trimmingCharacters(in: .whitespaces).isEmpty ? Brand.textMuted : Brand.accent)
                        }
                        .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
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
