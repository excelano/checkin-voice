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
