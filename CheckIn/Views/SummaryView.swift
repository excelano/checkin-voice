// SummaryView.swift — CheckIn Voice
// Terminal-aesthetic dashboard mirroring the Go CLI's renderDashboard output
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI

struct SummaryView: View {
    var viewModel: CheckInViewModel

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.bg.ignoresSafeArea()

                if viewModel.isLoading && viewModel.summary == nil {
                    ProgressView("Checking in...")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Brand.accent)
                        .tint(Brand.accent)
                } else if let summary = viewModel.summary {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            meetingSection(summary.meeting)
                            emailSection(summary.emails, error: summary.emailError)
                            teamsSection(summary.chats, error: summary.chatError, enabled: summary.teamsEnabled)
                        }
                        .padding()
                    }
                    .refreshable {
                        await viewModel.fetchSummary()
                    }
                } else if let error = viewModel.error {
                    VStack(spacing: 12) {
                        Text(error)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.red)
                        Button("Retry") {
                            Task { await viewModel.fetchSummary() }
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Brand.accent)
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        if viewModel.speechService.isSpeaking {
                            Button {
                                viewModel.speechService.stop()
                            } label: {
                                Image(systemName: "speaker.slash")
                                    .foregroundStyle(.yellow)
                            }
                        }

                        NavigationLink {
                            SettingsView(viewModel: viewModel)
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Brand.textMuted)
                        }
                    }
                }
            }
            .toolbarBackground(Brand.bgDarker, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationDestination(for: EmailDestination.self) { dest in
                DetailView(viewModel: viewModel, item: .email(dest.email))
            }
            .navigationDestination(for: ChatDestination.self) { dest in
                DetailView(viewModel: viewModel, item: .chat(dest.chat))
            }
            .task {
                if viewModel.summary == nil {
                    await viewModel.fetchSummary()
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Meeting

    @ViewBuilder
    private func meetingSection(_ meeting: Meeting?) -> some View {
        if let meeting {
            let timeUntil = untilTime(meeting.start)
            let urgency = meetingUrgency(meeting.start)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundStyle(Brand.accent)
                    Text(meeting.subject)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                }
                .font(.system(.body, design: .monospaced))

                HStack(spacing: 12) {
                    Text(timeUntil)
                        .foregroundStyle(urgency)
                    if !meeting.location.isEmpty {
                        Text(meeting.location)
                            .foregroundStyle(Brand.textMuted)
                    } else if meeting.isOnline {
                        Text("Online")
                            .foregroundStyle(Brand.textMuted)
                    }
                }
                .font(.system(.caption, design: .monospaced))
            }
        } else {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .foregroundStyle(Brand.accent)
                Text("No upcoming meetings")
                    .foregroundStyle(Brand.textMuted)
            }
            .font(.system(.body, design: .monospaced))
        }

        Divider().overlay(Brand.accentDim.opacity(0.3))
    }

    private func meetingUrgency(_ start: Date) -> Color {
        let until = start.timeIntervalSinceNow
        if until < 0 { return .red }
        if until < 15 * 60 { return .yellow }
        return Brand.accent
    }

    // MARK: - Email

    @ViewBuilder
    private func emailSection(_ emails: [Email], error: String?) -> some View {
        if let error {
            errorRow(icon: "envelope", text: "Could not load emails: \(error)")
        } else if emails.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .foregroundStyle(Brand.accent)
                Text("No unread emails")
                    .foregroundStyle(Brand.textMuted)
            }
            .font(.system(.body, design: .monospaced))
        } else {
            HStack(spacing: 6) {
                Image(systemName: "envelope")
                    .foregroundStyle(Brand.accent)
                Text("unread emails (\(emails.count)):")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .font(.system(.body, design: .monospaced))

            ForEach(Array(emails.enumerated()), id: \.element.id) { index, email in
                NavigationLink(value: EmailDestination(email: email)) {
                    itemRow(
                        number: index + 1,
                        from: email.from,
                        detail: truncate(email.subject, maxLen: 40),
                        time: relativeTime(email.received)
                    )
                }
            }
        }

        Divider().overlay(Brand.accentDim.opacity(0.3))
    }

    // MARK: - Teams

    @ViewBuilder
    private func teamsSection(_ chats: [ChatMessage], error: String?, enabled: Bool) -> some View {
        if !enabled {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Brand.accent)
                Text("Teams disabled")
                    .foregroundStyle(Brand.textMuted)
            }
            .font(.system(.body, design: .monospaced))
        } else if let error {
            errorRow(icon: "bubble.left.and.bubble.right", text: "Could not load chats: \(error)")
        } else if chats.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Brand.accent)
                Text("No pending chats")
                    .foregroundStyle(Brand.textMuted)
            }
            .font(.system(.body, design: .monospaced))
        } else {
            let offset = viewModel.summary?.emails.count ?? 0

            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .foregroundStyle(Brand.accent)
                Text("pending chats (\(chats.count)):")
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
            }
            .font(.system(.body, design: .monospaced))

            ForEach(Array(chats.enumerated()), id: \.element.id) { index, chat in
                NavigationLink(value: ChatDestination(chat: chat)) {
                    itemRow(
                        number: offset + index + 1,
                        from: chat.topic,
                        detail: truncate(chat.preview, maxLen: 40),
                        time: relativeTime(chat.sent)
                    )
                }
            }
        }
    }

    // MARK: - Shared Components

    private func itemRow(number: Int, from: String, detail: String, time: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("\(number). ")
                .foregroundStyle(Brand.accent)
                .frame(width: 30, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(from) — \"\(detail)\"")
                    .foregroundStyle(.white)
                Text(time)
                    .foregroundStyle(Brand.textMuted)
            }
            Spacer()
        }
        .font(.system(.caption, design: .monospaced))
    }

    private func errorRow(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(Brand.accent)
            Text(text)
                .foregroundStyle(.red)
        }
        .font(.system(.body, design: .monospaced))
    }
}

// MARK: - Navigation Destinations

struct EmailDestination: Hashable {
    let email: Email
    func hash(into hasher: inout Hasher) { hasher.combine(email.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.email.id == rhs.email.id }
}

struct ChatDestination: Hashable {
    let chat: ChatMessage
    func hash(into hasher: inout Hasher) { hasher.combine(chat.id) }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.chat.id == rhs.chat.id }
}
