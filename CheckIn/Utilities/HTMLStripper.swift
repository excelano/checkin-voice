// HTMLStripper.swift — CheckIn Voice
// Port of Go stripHTML() from nursery/checkin/mail.go
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

func stripHTML(_ html: String) -> String {
    var s = html

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
