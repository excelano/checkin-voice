// DetailView.swift — CheckIn Voice
// Shows email body or chat message history
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct DetailView: View {
    var viewModel: CheckInViewModel
    let item: Item
    @State private var showReply = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Brand.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch item {
                    case .email(let email):
                        emailDetail(email)
                    case .chat(let chat):
                        chatDetail(chat)
                    }
                }
                .padding()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Brand.bgDarker, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 16) {
                    if case .email(let email) = item {
                        Button {
                            Task {
                                await viewModel.markRead(email)
                                await viewModel.fetchSummary()
                                dismiss()
                            }
                        } label: {
                            Image(systemName: "envelope.open")
                                .foregroundStyle(Brand.accent)
                        }
                    }
                    Button {
                        showReply = true
                    } label: {
                        Image(systemName: "arrowshape.turn.up.left")
                            .foregroundStyle(Brand.accent)
                    }
                }
            }
        }
        .sheet(isPresented: $showReply) {
            ReplyView(viewModel: viewModel, item: item)
        }
        .task {
            switch item {
            case .email(let email):
                await viewModel.viewEmail(email)
            case .chat(let chat):
                await viewModel.viewChat(chat)
            }
        }
        .onChange(of: viewModel.replySent) {
            if viewModel.replySent {
                viewModel.replySent = false
                Task {
                    await viewModel.fetchSummary()
                }
                dismiss()
            }
        }
    }

    // MARK: - Email Detail

    @ViewBuilder
    private func emailDetail(_ email: Email) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(email.subject)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
            Text("From: \(email.from)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Brand.accent)
            Text(relativeTime(email.received))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Brand.textMuted)
        }

        Divider().overlay(Brand.accentDim.opacity(0.3))

        if viewModel.isLoadingDetail {
            ProgressView()
                .tint(Brand.accent)
        } else if let body = viewModel.emailBody {
            Text(body)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
        }
    }

    // MARK: - Chat Detail

    @ViewBuilder
    private func chatDetail(_ chat: ChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.topic)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
            Text(relativeTime(chat.sent))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(Brand.textMuted)
        }

        Divider().overlay(Brand.accentDim.opacity(0.3))

        if viewModel.isLoadingDetail {
            ProgressView()
                .tint(Brand.accent)
        } else if let messages = viewModel.chatMessages {
            ForEach(messages) { msg in
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.from)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Brand.accent)
                    Text(msg.preview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(relativeTime(msg.sent))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(Brand.textMuted)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
