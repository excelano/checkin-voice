# CheckIn Voice — Go-Forward Plan

Updated 2026-04-20.

## Where we are

**iOS app** (`CheckIn/`): Complete through auth, Graph API, UI shell, Siri Shortcut scaffolding, TTS, and a v1 voice command parser. Voice layer predates the dialog patterns we later discovered — no slot filling, confirmation, disambiguation, or echo-back. Roughly 2,200 lines of Swift across services, views, and models. Solid foundation.

**Web app** (`web/`): Frozen as a voice prototype. Developed further than needed, because it was the only platform we could experiment on while iOS was blocked by enrollment. Learned a lot; will not be developed further as a voice product. Will be reduced to text/click/type after iOS voice layer is built.

**Blockers:** Apple Developer enrollment pending D&B address update. Expected timeline: up to 7 days for D&B, then 1-5 business days for Apple. Real device testing unavailable until then. This plan is designed to use that waiting window productively.

## What we learned from the web prototype

Worth carrying forward as design decisions:

- **Command shape:** action + optional slots (itemType, name, qualifier, number, target, candidates).
- **Resolver priority:** number → name+type match → context (lastViewedItem) → ask clarifying question.
- **Single-slot dialog state:** `pendingCommand` with idle timeout (20s), cleared via setter side effect.
- **Narrow-on-tie:** when clarification has tied top scorers, they become the new candidate set — don't throw narrowing away.
- **Disambiguation prompt selection:** multiple senders → list senders; single sender with distinct subjects → list subjects; identical labels → prompt by ordinal.
- **Destructive action confirmation:** markRead, markAllRead, send all confirm before acting (yes/no dialog).
- **Echo-back on failure:** "I heard X. I'm not sure what to do with that. Say help."
- **Help is both spoken and visual:** short voice summary plus visual panel grouped by category.
- **Unrecognized utterance logging:** local log for learning what real usage looks like (original + normalized + reason).
- **Auto-start mic after TTS:** voice prompt completes → mic auto-starts.
- **Interrupt rule:** pressing mic while TTS is speaking always silences and starts listening.

Deliberately rebuild rather than port:

- Substring name matching → NLEmbedding cosine similarity (solves Anthony/Tony).
- Prefix-pattern table → NLTagger-based intent classification or much smaller rule set.
- Manual ordinal/number parsing → Foundation's `NumberFormatter(style: .spellOut)`.
- Scoring hacks → use SFSpeechRecognizer's per-word confidence scores.

## Work plan

### Tier 1: Voice dialog state machine (primary focus while blocked)

Pure Swift logic, no device APIs, unit-testable on MacInCloud without Apple enrollment.

- `VoiceDialog` class holding `pendingCommand` and handling state transitions.
- `Command` struct with optional slots (action, itemType, name, qualifier, number, target, candidates, awaitingConfirmation).
- `resolveCommand` function matching the web pattern.
- Confirmation state machine for destructive actions.
- Narrowing on tied clarifications.
- Pending-command idle timeout.
- Unit tests feeding transcripts and asserting state transitions, covering all branches.

### Tier 2: iOS-native matching behind protocols

- Define `NameMatcher` and `IntentClassifier` protocols.
- Stub implementations for deterministic unit testing.
- Real implementations using NLEmbedding and NLTagger — testable in simulator.
- Real implementations swap in with no change to dialog state machine.

### Tier 3: Non-voice polish

- Port `listNames` "twice / N times" fix to `SpeechService`.
- Add Help view (SwiftUI, previewable).
- Add markRead/markAllRead/send confirmation to non-voice button actions (consistency across modalities).
- Unrecognized utterance logging persisted to UserDefaults or app-local file.

### Blocked on device testing

- Real SFSpeechRecognizer behavior (simulator has no mic).
- Real TTS voice quality and timing.
- Siri Shortcuts trigger ("Hey Siri, check in").
- TestFlight distribution.

## Decisions to preserve

- Web app voice layer frozen. Do not add features. Reduce to text/click/type once iOS voice layer ships.
- No direct port of JS code to Swift. Use decisions, not code.
- Client ID in `Constants.swift` reflects `excelano.onmicrosoft.com` tenant (for publisher verification).
- Bundle ID: `com.excelano.checkin`.
- Brand colors: dark navy `#0f2233`, teal `#2ab8d0`, muted `#6a8899`.
- App icon still placeholder (Xcode default). Needs 1024x1024 before App Store submission — deferred.
