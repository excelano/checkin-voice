// ChatMessage.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

struct ChatMessage: Identifiable {
    let id = UUID()
    let chatID: String
    let topic: String
    let from: String
    let preview: String
    let sent: Date
}
