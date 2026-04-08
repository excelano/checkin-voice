// CheckInViewModel.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import SwiftUI

enum Item: Identifiable {
    case email(Email)
    case chat(ChatMessage)

    var id: String {
        switch self {
        case .email(let e): return e.id
        case .chat(let c): return c.id.uuidString
        }
    }

    var fromName: String {
        switch self {
        case .email(let e): return e.from
        case .chat(let c): return c.from
        }
    }
}

@MainActor @Observable
final class CheckInViewModel {
    // State
    private(set) var summary: CheckInSummary?
    private(set) var items: [Item] = []
    private(set) var isLoading = false
    private(set) var error: String?

    // Detail state
    private(set) var selectedItem: Item?
    private(set) var emailBody: String?
    private(set) var chatMessages: [ChatMessage]?
    private(set) var isLoadingDetail = false

    // Reply state
    var isReplying = false
    var replyDraft = ""
    private(set) var isSending = false

    // Services
    let authService: AuthService
    private let graphClient: GraphClient
    let speechService = SpeechService()
    let dictationService = DictationService()
    @ObservationIgnored var enableTeams: Bool {
        didSet { UserDefaults.standard.set(enableTeams, forKey: "enableTeams") }
    }

    init(authService: AuthService) {
        self.authService = authService
        self.enableTeams = UserDefaults.standard.bool(forKey: "enableTeams")
        self.graphClient = GraphClient(authService: authService, enableTeams: enableTeams)
    }

    // MARK: - Fetch Summary

    func fetchSummary() async {
        isLoading = true
        error = nil

        do {
            try await graphClient.fetchUserID()
        } catch {
            self.error = "Failed to fetch user profile: \(error.localizedDescription)"
            isLoading = false
            return
        }

        // Sequential fetch (avoids concurrency issues with TaskGroup)
        var meeting: Meeting?
        var emails: [Email] = []
        var chats: [ChatMessage] = []
        var emailError: String?
        var chatError: String?

        do {
            meeting = try await graphClient.nextMeeting()
            print("DEBUG: Calendar fetch succeeded")
        } catch {
            print("DEBUG: Calendar fetch failed: \(error)")
        }

        do {
            emails = try await graphClient.unreadEmails()
            print("DEBUG: Email fetch succeeded, count: \(emails.count)")
        } catch {
            emailError = error.localizedDescription
            print("DEBUG: Email fetch failed: \(error)")
        }

        if enableTeams {
            do {
                chats = try await graphClient.pendingChats()
                print("DEBUG: Teams fetch succeeded, count: \(chats.count)")
            } catch {
                chatError = error.localizedDescription
                print("DEBUG: Teams fetch failed: \(error)")
            }
        }

        summary = CheckInSummary(
            meeting: meeting,
            emails: emails,
            chats: chats,
            emailError: emailError,
            chatError: chatError,
            teamsEnabled: enableTeams
        )

        // Build flat items list: emails first, then chats (mirrors Go CLI)
        items = emails.map { .email($0) } + chats.map { .chat($0) }

        isLoading = false

        // Read summary aloud
        if let summary {
            speechService.speakSummary(summary)
        }
    }

    // MARK: - View Detail

    func viewEmail(_ email: Email) async {
        selectedItem = .email(email)
        emailBody = nil
        chatMessages = nil
        isLoadingDetail = true

        do {
            emailBody = try await graphClient.getEmailBody(id: email.id)
        } catch {
            emailBody = "Failed to load email: \(error.localizedDescription)"
        }

        isLoadingDetail = false
    }

    func viewChat(_ chat: ChatMessage) async {
        selectedItem = .chat(chat)
        emailBody = nil
        chatMessages = nil
        isLoadingDetail = true

        do {
            let messages = try await graphClient.getChatMessages(chatID: chat.chatID)
            chatMessages = messages.reversed()  // oldest first, like Go CLI
        } catch {
            chatMessages = []
        }

        isLoadingDetail = false
    }

    func clearDetail() {
        selectedItem = nil
        emailBody = nil
        chatMessages = nil
    }

    // MARK: - Actions

    func markRead(_ email: Email) async {
        do {
            try await graphClient.markEmailRead(id: email.id)
            items.removeAll { $0.id == email.id }
            summary = summary.map {
                CheckInSummary(
                    meeting: $0.meeting,
                    emails: $0.emails.filter { $0.id != email.id },
                    chats: $0.chats,
                    emailError: $0.emailError,
                    chatError: $0.chatError,
                    teamsEnabled: $0.teamsEnabled
                )
            }
        } catch {
            self.error = "Failed to mark as read: \(error.localizedDescription)"
        }
    }

    func markAllRead() async {
        guard let summary else { return }
        for email in summary.emails {
            try? await graphClient.markEmailRead(id: email.id)
        }
        await fetchSummary()
    }

    func replyToEmail(_ email: Email, comment: String) async {
        isSending = true
        do {
            try await graphClient.replyToEmail(id: email.id, comment: comment)
            replyDraft = ""
            isReplying = false
        } catch {
            self.error = "Failed to send reply: \(error.localizedDescription)"
        }
        isSending = false
    }

    func replyToChat(_ chat: ChatMessage, text: String) async {
        isSending = true
        do {
            try await graphClient.sendChatMessage(chatID: chat.chatID, text: text)
            replyDraft = ""
            isReplying = false
        } catch {
            self.error = "Failed to send message: \(error.localizedDescription)"
        }
        isSending = false
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ transcript: String) async {
        let command = parseVoiceCommand(transcript, items: items)

        switch command {
        case .readEmail(let name):
            if let item = findItem(name: name, type: .email) {
                if case .email(let email) = item {
                    await viewEmail(email)
                }
            }

        case .readChat(let name):
            if let item = findItem(name: name, type: .chat) {
                if case .chat(let chat) = item {
                    await viewChat(chat)
                }
            }

        case .reply:
            isReplying = true

        case .send:
            // Handled by ReplyView directly
            break

        case .cancel:
            isReplying = false
            replyDraft = ""

        case .refresh:
            await fetchSummary()

        case .markRead(let name):
            if let item = findItem(name: name, type: .email),
               case .email(let email) = item {
                await markRead(email)
                speechService.speak("Marked as read.")
            }

        case .markAllRead:
            await markAllRead()
            speechService.speak("All emails marked as read.")

        case .stop:
            speechService.stop()

        case .unknown:
            break
        }
    }

    private enum ItemType { case email, chat }

    private func findItem(name: String, type: ItemType) -> Item? {
        let nameLower = name.lowercased()
        return items.first { item in
            let matchesName = item.fromName.lowercased().contains(nameLower)
            switch (item, type) {
            case (.email, .email): return matchesName
            case (.chat, .chat): return matchesName
            default: return false
            }
        }
    }

    // MARK: - Sign Out

    func signOut() {
        speechService.stop()
        authService.signOut()
    }
}
