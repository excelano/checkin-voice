// CheckInShortcuts.swift — CheckIn Voice
// Registers app shortcuts so "Hey Siri, check in" works automatically
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import AppIntents

struct CheckInShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CheckInShortcut(),
            phrases: [
                "Check in with \(.applicationName)",
                "What's my day look like in \(.applicationName)"
            ],
            shortTitle: "Check In",
            systemImageName: "checkmark.circle"
        )
    }
}
