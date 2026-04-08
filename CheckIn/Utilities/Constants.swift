// Constants.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation

enum Constants {
    // Replace with your Application (client) ID from Azure Portal
    static let clientID = "ee5d84b1-d8b0-48f9-afcd-23b34e9eba79"

    // Single tenant for testing. Change to /common before App Store release.
    static let authority = "https://login.microsoftonline.com/571183c9-5f75-495d-b3f8-b98a334341ea"
    static let redirectURI = "msauth.com.excelano.checkin://auth"
    static let graphBaseURL = "https://graph.microsoft.com/v1.0"

    // Note: MSAL for iOS automatically requests openid, profile, and offline_access.
    // Do not include them here or MSAL will throw an error.
    static let baseScopes = [
        "User.Read",
        "Mail.ReadWrite",
        "Mail.Send",
        "Calendars.Read"
    ]

    static let teamsScopes = [
        "Chat.ReadWrite"
    ]

    static func scopes(enableTeams: Bool) -> [String] {
        enableTeams ? baseScopes + teamsScopes : baseScopes
    }
}
