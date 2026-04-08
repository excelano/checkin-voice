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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Build a quick text summary for Siri to speak.
        // The app opens and does the full fetch + TTS in the foreground,
        // but this dialog gives Siri something to say immediately.
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

        // Fetch concurrently
        var meetingText = ""
        var emailText = ""
        var chatText = ""

        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                if let meeting = try? await client.nextMeeting() {
                    meetingText = "Your next meeting is \(meeting.subject), \(untilTime(meeting.start))."
                } else {
                    meetingText = "No upcoming meetings."
                }
            }

            group.addTask {
                if let emails = try? await client.unreadEmails() {
                    if emails.isEmpty {
                        emailText = "No unread emails."
                    } else {
                        emailText = "You have \(emails.count) unread email\(emails.count == 1 ? "" : "s")."
                    }
                }
            }

            if enableTeams {
                group.addTask {
                    if let chats = try? await client.pendingChats() {
                        if chats.isEmpty {
                            chatText = "No pending Teams messages."
                        } else {
                            chatText = "\(chats.count) pending Teams message\(chats.count == 1 ? "" : "s")."
                        }
                    }
                }
            }
        }

        let summary = [meetingText, emailText, chatText]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return .result(dialog: IntentDialog(stringLiteral: summary))
    }
}
