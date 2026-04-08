// CheckInShortcut.swift — CheckIn Voice
// AppIntent for "Hey Siri, check in"
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

struct CheckInShortcut: AppIntent {
    static var title: LocalizedStringResource = "Check In"
    static var description = IntentDescription(
        "Get a summary of your next meeting, unread emails, and Teams messages."
    )

    // Opens the app so MSAL can silently authenticate and TTS can play
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let authService = AuthService()

        guard authService.isAuthenticated else {
            return .result(dialog: "Please open CheckIn and sign in first.")
        }

        let enableTeams = UserDefaults.standard.bool(forKey: "enableTeams")
        let client = GraphClient(authService: authService, enableTeams: enableTeams)

        do {
            try await client.fetchUserID()
        } catch {
            return .result(dialog: "Could not connect to Microsoft 365.")
        }

        // Fetch sequentially (simpler, avoids Swift 6 sendability issues)
        var parts: [String] = []

        if let meeting = try? await client.nextMeeting() {
            parts.append("Your next meeting is \(meeting.subject), \(untilTime(meeting.start)).")
        } else {
            parts.append("No upcoming meetings.")
        }

        if let emails = try? await client.unreadEmails() {
            if emails.isEmpty {
                parts.append("No unread emails.")
            } else {
                parts.append("You have \(emails.count) unread email\(emails.count == 1 ? "" : "s").")
            }
        }

        if enableTeams {
            if let chats = try? await client.pendingChats() {
                if chats.isEmpty {
                    parts.append("No pending Teams messages.")
                } else {
                    parts.append("\(chats.count) pending Teams message\(chats.count == 1 ? "" : "s").")
                }
            }
        }

        return .result(dialog: IntentDialog(stringLiteral: parts.joined(separator: " ")))
    }
}
