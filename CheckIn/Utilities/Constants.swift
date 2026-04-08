// Constants.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum Constants {
    // Replace with your Application (client) ID from Azure Portal
    static let clientID = "ee5d84b1-d8b0-48f9-afcd-23b34e9eba79"

    static let authority = "https://login.microsoftonline.com/common"
    static let redirectURI = "msauth.com.excelano.checkin://auth"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    static let baseScopes = [
        "User.Read",
        "Mail.ReadWrite",
        "Mail.Send",
        "Calendars.Read",
        "offline_access"
    ]

    static let teamsScopes = [
        "Chat.ReadWrite"
    ]

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }
}
