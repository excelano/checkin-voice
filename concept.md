# Email Summary iOS App — Concept Document

## Overview

A native iOS app that delivers a voice-first summary of your work day: next calendar event, unread emails, pending Teams messages, and the ability to send quick voice replies. Audio is the primary interface; visual display mirrors the command-line tool aesthetic but takes a backseat to voice interaction.

## Core Purpose

Stay informed whilst driving or otherwise unable to look at a screen. No need to open Outlook, Teams, or Calendar separately. One app, one voice, everything you need to know right now.

## Scope

### Data Pulled

- One work Microsoft 365 account (architecture allows multiple accounts later)
- Three data sources:
  - Next calendar event
  - Unread emails
  - Pending Teams messages from the last 24 hours (where you didn't send the final message in the thread)

### User Interaction Model

1. **Listen to summary**: Next appointment, count of unread emails with sender names, count of pending chats with sender names
2. **Drill down by voice**: "Read email from Tony" → app reads subject plus last message in thread
3. **Teams messages**: Read just the last message
4. **Send quick replies**: App reads back what you said, you confirm with "send" or "cancel"

## Technical Stack

- **Language**: Swift
- **Platform**: iOS only
- **API**: Microsoft Graph API
- **Authentication**: OAuth authorization code flow with PKCE
- **Token Storage**: Secure local storage on device (Keychain)
- **Backend**: None — direct API calls from app
- **Distribution**: App Store

## Key Constraints

- Lean and minimal — no feature creep
- Voice replies: confirm and send, or cancel and retry (no correction flows)
- Summary is a fast, scannable list by ear
- First iOS app build — learning exercise with clear documentation
- Single account MVP (multi-account architecture planned for later)

## Next Steps

1. Set up Microsoft app registration
2. Build Swift project structure
3. Implement OAuth flow with MSAL for Swift
4. Connect to Microsoft Graph endpoints
5. Build summary interface
6. Add speech input (dictation) and text-to-speech output
7. Implement reply sending logic
8. Test thoroughly
9. Prepare for App Store submission

## Success Criteria

- App authenticates to work M365 account
- Pulls and summarizes next calendar event, unread emails, and pending Teams messages
- Reads summary aloud via TTS
- Accepts voice input for replies
- Confirms reply text before sending
- Runs on iOS, distributable via App Store

