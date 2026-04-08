// SpeechService.swift — CheckIn Voice
// Text-to-speech using AVSpeechSynthesizer, voice follows device locale
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import AVFoundation

@Observable
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    private func configureAudioSession() {
        do {
            // .playback allows audio even when the silent switch is on
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt)
        } catch {
            print("Failed to configure audio session: \(error.localizedDescription)")
        }
    }

    // MARK: - Speak

    func speak(_ text: String) {
        stop()

        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.pitchMultiplier = 1.0

        // Pick a voice matching the device locale (en-GB = British, en-US = American, etc.)
        let lang = Locale.current.language.languageCode?.identifier ?? "en"
        let region = Locale.current.language.region?.identifier ?? "US"
        let voiceLocale = "\(lang)-\(region)"

        if let voice = AVSpeechSynthesisVoice(language: voiceLocale) {
            utterance.voice = voice
        }

        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Build Summary Script

    /// Builds a natural-language summary for TTS, mirroring the CLI dashboard output
    func speakSummary(_ summary: CheckInSummary) {
        var parts: [String] = []

        // Meeting
        if let meeting = summary.meeting {
            let time = untilTime(meeting.start)
            var location = ""
            if !meeting.location.isEmpty {
                location = ", at \(meeting.location)"
            } else if meeting.isOnline {
                location = ", online"
            }
            parts.append("Your next meeting is \(meeting.subject), \(time)\(location).")
        } else {
            parts.append("No upcoming meetings.")
        }

        // Emails
        if let error = summary.emailError {
            parts.append("Could not load emails. \(error)")
        } else if summary.emails.isEmpty {
            parts.append("No unread emails.")
        } else {
            let count = summary.emails.count
            let names = listNames(summary.emails.map { $0.from })
            parts.append("You have \(count) unread email\(count == 1 ? "" : "s"), from \(names).")
        }

        // Teams
        if summary.teamsEnabled {
            if let error = summary.chatError {
                parts.append("Could not load Teams messages. \(error)")
            } else if summary.chats.isEmpty {
                parts.append("No pending Teams messages.")
            } else {
                let count = summary.chats.count
                let names = listNames(summary.chats.map { $0.from })
                parts.append("You have \(count) pending Teams message\(count == 1 ? "" : "s"), from \(names).")
            }
        }

        speak(parts.joined(separator: " "))
    }

    /// "Tony, Sarah, and Mike" or "Tony and Sarah" or "Tony"
    private func listNames(_ names: [String]) -> String {
        switch names.count {
        case 0: return "unknown"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            let allButLast = names.dropLast().joined(separator: ", ")
            return "\(allButLast), and \(names.last!)"
        }
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
