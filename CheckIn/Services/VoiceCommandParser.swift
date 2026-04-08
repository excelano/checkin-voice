// VoiceCommandParser.swift — CheckIn Voice
// Parses speech transcripts into commands using simple keyword matching
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum VoiceCommand {
    case readEmail(from: String)
    case readChat(from: String)
    case reply
    case send
    case cancel
    case refresh
    case markRead(from: String)
    case markAllRead
    case stop
    case unknown(String)
}

func parseVoiceCommand(_ transcript: String, items: [Item]) -> VoiceCommand {
    let text = transcript.lowercased().trimmingCharacters(in: .whitespaces)

    // Exact/simple commands first
    if text == "send" || text == "send it" { return .send }
    if text == "cancel" || text == "never mind" { return .cancel }
    if text == "refresh" || text == "check again" { return .refresh }
    if text == "mark all read" || text == "mark all done" { return .markAllRead }
    if text == "stop" || text == "be quiet" || text == "shut up" { return .stop }
    if text == "reply" { return .reply }

    // "read email from Tony" or "email from Tony"
    if let name = extractName(from: text, prefixes: ["read email from", "email from", "open email from"]) {
        return .readEmail(from: name)
    }

    // "read chat from Sarah" or "chat from Sarah"
    if let name = extractName(from: text, prefixes: ["read chat from", "chat from", "open chat from", "read message from", "message from"]) {
        return .readChat(from: name)
    }

    // "mark read from Tony" or "done with Tony"
    if let name = extractName(from: text, prefixes: ["mark read from", "mark done from", "done with"]) {
        return .markRead(from: name)
    }

    // "read from Tony" — infer email or chat based on what's in the items list
    if let name = extractName(from: text, prefixes: ["read from", "open from"]) {
        // Check emails first, then chats
        let matched = items.first { $0.fromName.lowercased().contains(name) }
        switch matched {
        case .email: return .readEmail(from: name)
        case .chat: return .readChat(from: name)
        case nil: return .readEmail(from: name)  // default to email
        }
    }

    return .unknown(text)
}

/// Extracts the name portion after one of the given prefixes.
/// "read email from Tony Garcia" with prefix "read email from" returns "tony garcia"
private func extractName(from text: String, prefixes: [String]) -> String? {
    for prefix in prefixes {
        if text.hasPrefix(prefix) {
            let name = String(text.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return name }
        }
    }
    return nil
}
