# CheckIn Voice — Go-Forward Plan

Updated 2026-05-07.

## Status

**iOS app** (`CheckIn/`): Foundation in place. MSAL auth, Graph API client, basic SwiftUI UI shell, TTS, AppIntents-based Siri shortcut scaffolding. Voice layer is the early intuition-driven version that predates the design audit; the full state machine, dialog context, persona, and the rest of the structures decided in `DESIGN.md` have not yet been implemented. About 2,200 lines of Swift, partly retained, partly rewritten.

**Web app** (`web/`): Frozen. Functioned as a voice prototype while iOS was blocked. Will be reduced to text/click/type once the iOS Day 1 voice layer ships. No further voice work.

**Apple Developer enrollment:** Submitted 2026-05-06 with corrected D&B profile. Awaiting Apple verification email (1-5 business days). Once approved, TestFlight distribution becomes available.

**App icon:** Custom CheckIn icon (single bold teal check on navy) created and shipping in `Assets.xcassets/AppIcon.appiconset/`.

## Architecture (per DESIGN.md)

The design audit (`DESIGN.md`, 33 decisions captured) sets the architecture. Highlights that shape this plan:

- **Single screen, deep-link** (D27). The app has one main screen showing the at-a-glance summary. Tap any item to deep-link to Outlook or Teams. No detail views, no reply flow, no email body display.
- **Voice as state machine** (D1, D33). Hierarchical states (`signedOut`, `onboarding`, `active`) with eight `active` substates; explicit transitions, dialog context, persona-shaped responses. See `STATES.md`.
- **Classical NLP, not LLM** (D14). `NLEmbedding` for semantic similarity, `NLTagger` for entity recognition, custom intent classifier behind a protocol. Foundation Models on the long-term backlog.
- **Privacy non-negotiable** (D9, D24). On-device speech recognition only, zero telemetry, zero analytics, zero data sharing with anyone except the user's own M365 service. M365 data never persisted to disk.
- **Augments not replaces** (D27). CheckIn is a voice-first M365 status panel; Outlook and Teams remain the apps for reading bodies, composing replies, and joining meetings.
- **Persona** (D32). Calm, capable, brief; warm without familiarity; first-person singular; light dry humor only on refusals and redirects. See `PERSONA.md`.
- **Multi-modal accessibility** (D22). Full core experience reachable without voice; voice-only conveniences (bulk operations, quick queries) need not have touch counterparts.
- **Self-hostable** (D25, D26). Custom Azure App Registration via Settings > Advanced, plus full fork-and-rebuild path documented in `SELF-HOSTING.md`.

## Iceberg scope (per D12 and D29)

The voice surface ships in three tiers. Day 1 ships first; Day 2 and Day 3 are the roadmap.

**Day 1 (above the waterline).** Summary spoken on demand with optional sender/topic filter; refresh; stop and repeat; help; voice-driven open of summary items via deep-link to Outlook or Teams; sign-in; settings; conversation mode entry and exit. D18 out-of-scope refusals and D19 in-scope-unsupported redirects handle anything else. The full set of foundational decisions (D1 through D33) is in place.

**Day 2 (next release after launch).** Quick queries with terse response (counts, times). Mark single email as read. Flag single email. Reply by voice via Outlook deep-link in reply mode.

**Day 3 (subsequent release).** Soft-delete single email with confirmation per D28. Bulk operations (mark-all-read, flag-all, delete-all, with the "except the latest" modifier and count confirmation). Join meeting by voice via Teams deep-link.

This plan focuses on shipping Day 1.

## Day 1 build sequence

Each phase is testable in isolation; later phases depend on earlier ones.

### Phase 1: Project scaffolding and design artifacts

- `DESIGN.md`, `PERSONA.md`, `STATES.md`, `CAPABILITIES.md` finalized at the repo root.
- `PRIVACY.md` describing the privacy posture from D9, D11, and D24.
- `SELF-HOSTING.md` per D26.
- `README.md` updated with the new positioning (voice-first M365 status panel that augments Outlook and Teams).
- App icon already in place.

### Phase 2: Architecture rebuild

The existing iOS code is partly reused, partly rewritten to match `STATES.md`.

- `DialogState` Swift enum with associated values (suspended intent in `disambiguating`, pending action in `confirming`, recent context in `helpDisplayed`).
- `DialogContext` struct (focused entity, summary slots, last utterance, last system response, recent turn history, pending confirmations, reprompt counter, recent refusal and redirect phrasings).
- `StateMachine` class with `currentState` and `transition(to:)`; debug-only logging.
- `IntentClassifier`, `EntityMatcher`, `ResponseGenerator` protocols (per D15) with deterministic stubs for tests.
- `DeepLinkService` constructing URLs for Outlook (open inbox, message, calendar event; reply mode) and Teams (open chat; join meeting). `LSApplicationQueriesSchemes` declares `ms-outlook` and `msteams`.
- `SpeechService`: `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` (D9), VAD on the audio engine input tap, `contextualStrings` for proper-noun biasing, `AVAudioSession` configured `.playAndRecord` + `.voiceChat` for echo cancellation per D8 barge-in.
- `TTSService`: `AVSpeechSynthesizer` with locale-matched voice default, delegate callbacks for barge-in tracking, response template registry for persona-shaped output.
- Audio assets: three earcons (listening, thinking, confirmation) per D13 and D33, each under 500 ms.

### Phase 3: Day 1 voice intelligence

- Day 1 intent classifier: summary, filter-by-name, refresh, repeat, stop, help, open (with entity), exit, settings.
- Real `NLEmbedding`-based intent classifier behind the protocol from D15.
- Real `NLTagger`-based entity matcher with `contextualStrings` priming and contact-list source-of-truth.
- Day 1 response template registry: summary phrasings, refusal pool (D18), redirect pool (D19), help short and long variants (D30), error pools per category (D21), onboarding invitations (D31). All reviewed against `PERSONA.md`.
- Custom language model from D10 implemented as opt-in but disabled by default (Settings only). Day 1 uses `contextualStrings` plus fuzzy matching.

### Phase 4: User-visible UI

- `ContentView` (auth gate per D33).
- `SummaryView` (the only main screen per D27).
- `HelpView` sheet per D30 (multimodal, structured, contextual).
- `SettingsView` sheet (Voice section per D5; Listening Mode per D17; Voice Recognition Tuning per D10; Advanced per D25).
- `OnboardingFlow` sequence per D31 (welcome, permissions, mode, first query).
- Listening indicator, thinking indicator, captioning view per D22.
- VoiceOver labels and Dynamic Type on every interactive element per D22.
- Reduced-motion variants per D22.

### Phase 5: Integration and on-device verification

- Wire state machine to UI via SwiftUI `@Observable`.
- End-to-end voice flow on simulator (limited by simulator audio per `CAPABILITIES.md`).
- On-device test loop on iPhone 15 once Apple Developer enrollment completes.
- Cross-state behavior: barge-in, conversation mode loop, disambiguation, confirmation, error recovery.
- Privacy audit: confirm no `URLSession` calls outside Microsoft Graph and login; confirm no analytics, crash reporters, or telemetry SDKs.

### Phase 6: Pre-TestFlight checklist

- Permission strings in `Info.plist` reviewed.
- App Store Connect App Privacy declaration set to "Data Not Collected."
- Persona drift check across the response template registry.
- Accessibility test pass: VoiceOver, Dynamic Type at largest size, reduced motion.
- Privacy posture documented in README and `PRIVACY.md`.
- Final smoke test on physical device.

## Phases that vanished

Several phases from the original plan are no longer needed:

- DetailView and ReplyView (D27 makes them unnecessary).
- Email body parsing or HTML stripping (no body display).
- Reply composition flow (deep-link to Outlook covers it).
- Voice list browsing (deep-link to Outlook covers it).

## Decisions to preserve from the prior plan

- Web app voice layer frozen. Reduce to text/click/type once iOS Day 1 ships.
- Client ID in `Constants.swift` reflects `excelano.onmicrosoft.com` tenant (publisher-verified). Now backed by `@AppStorage` per D25 to allow user override.
- Bundle ID: `com.excelano.checkin`.
- Brand colors: dark navy `#0f2233`, teal `#2ab8d0`, muted `#6a8899`.

## Reference

- `DESIGN.md` — 33 design decisions, the source of truth for what we are building and why.
- `PERSONA.md` — the working voice persona reference.
- `STATES.md` — the application state diagram and transitions.
- `CAPABILITIES.md` — Apple voice/audio API and Natural Language framework capability scan.
- `PRIVACY.md` — privacy posture statement (forthcoming).
- `SELF-HOSTING.md` — full self-hosting walkthrough (forthcoming).
