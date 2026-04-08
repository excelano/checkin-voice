// CheckInApp.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import SwiftUI
import MSAL

@main
struct CheckInApp: App {
    @State private var authService = AuthService()

    var body: some Scene {
        WindowGroup {
            ContentView(authService: authService)
        }
    }

    // Handle the MSAL redirect callback when the browser returns after sign-in
    init() {
        // No additional setup needed — AuthService configures MSAL in its init
    }
}
