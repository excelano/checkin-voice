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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

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
        .toolbarBackground(.black, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showReply = true
                } label: {
                    Image(systemName: "arrowshape.turn.up.left")
                        .foregroundStyle(.green)
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
    }

    // MARK: - Email Detail

    @ViewBuilder
    private func emailDetail(_ email: Email) -> some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            Text(email.subject)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
            Text("From: \(email.from)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.cyan)
            Text(relativeTime(email.received))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray)
        }

        Divider().overlay(Color.gray.opacity(0.3))

        // Body
        if viewModel.isLoadingDetail {
            ProgressView()
                .tint(.green)
        } else if let body = viewModel.emailBody {
            Text(body)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.white)
        }

        // Mark as read button
        Button {
            Task {
                await viewModel.markRead(email)
            }
        } label: {
            Text("Mark as Read")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.black)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.green)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .padding(.top, 8)
    }

    // MARK: - Chat Detail

    @ViewBuilder
    private func chatDetail(_ chat: ChatMessage) -> some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            Text(chat.topic)
                .font(.system(.headline, design: .monospaced))
                .foregroundStyle(.white)
            Text(relativeTime(chat.sent))
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.gray)
        }

        Divider().overlay(Color.gray.opacity(0.3))

        // Messages
        if viewModel.isLoadingDetail {
            ProgressView()
                .tint(.green)
        } else if let messages = viewModel.chatMessages {
            ForEach(messages) { msg in
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.from)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.cyan)
                    Text(msg.preview)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(relativeTime(msg.sent))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.gray)
                }
                .padding(.vertical, 4)
            }
        }
    }
}
