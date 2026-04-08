// AuthService.swift — CheckIn Voice
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

import Foundation
import MSAL

@Observable
final class AuthService {
    private(set) var isAuthenticated = false
    private var msalApp: MSALPublicClientApplication?
    private var currentAccount: MSALAccount?

    init() {
        configureMSAL()
        checkExistingAccount()
    }

    // MARK: - Configuration

    private func configureMSAL() {
        guard let authorityURL = URL(string: Constants.authority) else { return }

        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: Constants.clientID,
                redirectUri: Constants.redirectURI,
                authority: authority
            )
            msalApp = try MSALPublicClientApplication(configuration: config)
        } catch {
            print("Failed to configure MSAL: \(error.localizedDescription)")
        }
    }

    private func checkExistingAccount() {
        guard let msalApp else { return }

        do {
            let accounts = try msalApp.allAccounts()
            if let account = accounts.first {
                currentAccount = account
                isAuthenticated = true
            }
        } catch {
            print("Failed to check accounts: \(error.localizedDescription)")
        }
    }

    // MARK: - Sign In (interactive browser flow)

    func signIn(enableTeams: Bool) async throws -> String {
        guard let msalApp else {
            throw AuthError.notConfigured
        }

        let scopes = Constants.scopes(enableTeams: enableTeams)

        // Get the root view controller for presenting the auth browser
        guard let windowScene = await MainActor.run(body: {
            UIApplication.shared.connectedScenes.first as? UIWindowScene
        }),
        let viewController = await MainActor.run(body: {
            windowScene?.keyWindow?.rootViewController
        }) else {
            throw AuthError.noViewController
        }

        let webviewParams = MSALWebviewParameters(authPresentationViewController: viewController)
        let params = MSALInteractiveTokenParameters(scopes: scopes, webviewParameters: webviewParams)

        let result = try await msalApp.acquireToken(with: params)
        currentAccount = result.account
        isAuthenticated = true
        return result.accessToken
    }

    // MARK: - Silent Token Refresh

    func acquireTokenSilently(enableTeams: Bool) async throws -> String {
        guard let msalApp, let account = currentAccount else {
            throw AuthError.notAuthenticated
        }

        let scopes = Constants.scopes(enableTeams: enableTeams)
        let params = MSALSilentTokenParameters(scopes: scopes, account: account)

        do {
            let result = try await msalApp.acquireTokenSilent(with: params)
            return result.accessToken
        } catch let error as NSError where error.domain == MSALErrorDomain
            && error.code == MSALError.interactionRequired.rawValue {
            // Token expired and can't refresh silently — need interactive sign-in
            return try await signIn(enableTeams: enableTeams)
        }
    }

    // MARK: - Sign Out

    func signOut() {
        guard let msalApp, let account = currentAccount else { return }

        do {
            try msalApp.remove(account)
        } catch {
            print("Failed to sign out: \(error.localizedDescription)")
        }

        currentAccount = nil
        isAuthenticated = false
    }
}

// MARK: - Errors

enum AuthError: LocalizedError {
    case notConfigured
    case noViewController
    case notAuthenticated
    case adminConsentRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "MSAL is not configured. Check your client ID."
        case .noViewController:
            return "Could not find a view controller to present sign-in."
        case .notAuthenticated:
            return "No signed-in account. Please sign in first."
        case .adminConsentRequired:
            return "Your organization requires admin consent for Teams access. "
                + "Ask your IT administrator to approve the Chat.ReadWrite permission "
                + "for the CheckIn app. You can still use email and calendar by "
                + "disabling Teams in Settings."
        }
    }
}
