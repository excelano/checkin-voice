// HTMLStripper.swift — CheckIn Voice
// Port of Go stripHTML() from nursery/checkin/mail.go
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

func stripHTML(_ html: String) -> String {
    var s = html

    // Remove style and script blocks entirely (content and tags)
    if let styleRegex = try? NSRegularExpression(pattern: "<style[^>]*>.*?</style>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
        s = styleRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }
    if let scriptRegex = try? NSRegularExpression(pattern: "<script[^>]*>.*?</script>", options: [.caseInsensitive, .dotMatchesLineSeparators]) {
        s = scriptRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    // Remove HTML comments
    if let commentRegex = try? NSRegularExpression(pattern: "<!--.*?-->", options: .dotMatchesLineSeparators) {
        s = commentRegex.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "")
    }

    // Replace block elements with newlines
    let blockTags = ["</p>", "</div>", "</tr>", "<br>", "<br/>", "<br />"]
    for tag in blockTags {
        s = s.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
    }

    // Strip remaining HTML tags
    if let tagRegex = try? NSRegularExpression(pattern: "<[^>]*>") {
        s = tagRegex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: ""
        )
    }

    // Decode common HTML entities
    let entities: [String: String] = [
        "&amp;": "&",
        "&lt;": "<",
        "&gt;": ">",
        "&nbsp;": " ",
        "&#39;": "'",
        "&quot;": "\"",
        "&apos;": "'"
    ]
    for (entity, replacement) in entities {
        s = s.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
    }

    // Collapse excessive newlines
    if let newlineRegex = try? NSRegularExpression(pattern: "\\n{3,}") {
        s = newlineRegex.stringByReplacingMatches(
            in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "\n\n"
        )
    }

    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Strip quoted/previous messages and signature blocks from email text.
/// Call this AFTER stripHTML to work on plain text.
func stripEmailQuotes(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    var result: [String] = []

    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Stop at common reply/forward headers
        if trimmed.hasPrefix("From:") && trimmed.contains("@") { break }
        if trimmed.hasPrefix("On ") && trimmed.contains(" wrote:") { break }
        if trimmed == "________________________________" { break }
        if trimmed.hasPrefix("-----Original Message-----") { break }
        if trimmed.hasPrefix("----- Forwarded Message -----") { break }

        // Stop at common signature markers
        if trimmed == "--" { break }
        if trimmed == "-- " { break }
        if trimmed.lowercased() == "regards," { break }
        if trimmed.lowercased() == "best regards," { break }
        if trimmed.lowercased() == "thanks," { break }
        if trimmed.lowercased() == "thank you," { break }
        if trimmed.lowercased() == "cheers," { break }
        if trimmed.lowercased() == "best," { break }
        if trimmed.lowercased() == "sincerely," { break }
        if trimmed.lowercased().hasPrefix("sent from my ") { break }
        if trimmed.lowercased().hasPrefix("get outlook for") { break }

        result.append(line)
    }

    return result.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}
