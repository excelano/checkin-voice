// app.js — CheckIn Voice (Web)
// Port of the iOS app to Web Speech API + MSAL.js + Microsoft Graph
//
// Author: David M. Anderson
// Built with AI assistance (Claude, Anthropic)

// ---------------------------------------------------------------------------
// Configuration
// ---------------------------------------------------------------------------

const CONFIG = {
    clientId: "0ce3820d-db53-4b2e-9621-6c4ccc086d5a",
    authority: "https://login.microsoftonline.com/common",
    // Update this to match your Azure AD SPA redirect URI
    redirectUri: window.location.origin + window.location.pathname,
    graphBaseURL: "https://graph.microsoft.com/v1.0",
    baseScopes: ["User.Read", "Mail.ReadWrite", "Mail.Send", "Calendars.Read"],
    teamsScopes: ["Chat.ReadWrite"],
};

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

const state = {
    // Auth
    account: null,
    userID: "",

    // Summary
    summary: null,
    items: [],         // [{type: "email"|"chat", data: {...}}, ...]
    isLoading: false,
    error: null,

    // Detail
    selectedItem: null,
    lastViewedItem: null,  // context for follow-up commands
    detailContent: null,
    isLoadingDetail: false,

    // Reply
    replyItem: null,
    replyMode: null,  // null | "dictating" | "confirming"
    isSending: false,

    // Pending command: managed via Object.defineProperty below so that
    // every assignment (re)starts an idle timeout. See setter.
    // Shape: { action, itemType, name, qualifier, candidates, awaitingConfirmation }

    // Settings (persisted in localStorage)
    enableTeams: localStorage.getItem("enableTeams") === "true",
    voiceOnStart: localStorage.getItem("voiceOnStart") !== "false", // default true

    // Speech
    isSpeaking: false,
    isListening: false,
    userHasInteracted: false,
    pendingSpeech: null,
};

// Pending command with idle timeout. Assignments to state.pendingCommand go
// through this setter, which resets the 20-second timer. If the user never
// responds, the pending command is cleared and a soft audio cue is given.
const PENDING_TIMEOUT_MS = 20000;
let _pendingCommand = null;
let _pendingTimeoutID = null;
Object.defineProperty(state, "pendingCommand", {
    enumerable: true,
    get() { return _pendingCommand; },
    set(cmd) {
        if (_pendingTimeoutID) {
            clearTimeout(_pendingTimeoutID);
            _pendingTimeoutID = null;
        }
        _pendingCommand = cmd;
        if (cmd) {
            _pendingTimeoutID = setTimeout(() => {
                _pendingTimeoutID = null;
                if (_pendingCommand) {
                    _pendingCommand = null;
                    speechSpeak("Never mind, then.");
                }
            }, PENDING_TIMEOUT_MS);
        }
    },
});

// ---------------------------------------------------------------------------
// MSAL Authentication
// ---------------------------------------------------------------------------

const msalConfig = {
    auth: {
        clientId: CONFIG.clientId,
        authority: CONFIG.authority,
        redirectUri: CONFIG.redirectUri,
    },
    cache: {
        cacheLocation: "localStorage",
    },
};

const msalApp = new msal.PublicClientApplication(msalConfig);

function getScopes() {
    return state.enableTeams
        ? [...CONFIG.baseScopes, ...CONFIG.teamsScopes]
        : CONFIG.baseScopes;
}

async function signIn() {
    try {
        const response = await msalApp.loginPopup({ scopes: getScopes() });
        state.account = response.account;
        showApp();
        await fetchSummary();
    } catch (err) {
        showSignInError(err.message);
    }
}

async function getAccessToken() {
    if (!state.account) throw new Error("Not signed in");

    try {
        const response = await msalApp.acquireTokenSilent({
            scopes: getScopes(),
            account: state.account,
        });
        return response.accessToken;
    } catch {
        // Silent failed, try popup
        const response = await msalApp.acquireTokenPopup({
            scopes: getScopes(),
            account: state.account,
        });
        return response.accessToken;
    }
}

function signOut() {
    speechStop();
    hideReply();
    hideSettings();
    hideHelp();
    state.pendingCommand = null;
    state.selectedItem = null;
    state.lastViewedItem = null;
    state.replyItem = null;
    state.replyMode = null;
    msalApp.logoutPopup({ account: state.account });
    state.account = null;
    state.summary = null;
    state.items = [];
    showSignIn();
}

// ---------------------------------------------------------------------------
// Microsoft Graph API Client
// ---------------------------------------------------------------------------

async function graphGet(path, query = {}) {
    const token = await getAccessToken();
    const params = new URLSearchParams(query);
    const sep = Object.keys(query).length ? "?" : "";
    const url = CONFIG.graphBaseURL + path + sep + params.toString();

    const resp = await fetch(url, {
        headers: { Authorization: "Bearer " + token },
    });

    if (!resp.ok) {
        const body = await resp.text();
        throw new Error("Graph GET " + path + " returned " + resp.status + ": " + body);
    }
    return resp.json();
}

async function graphPatch(path, body) {
    const token = await getAccessToken();
    const resp = await fetch(CONFIG.graphBaseURL + path, {
        method: "PATCH",
        headers: {
            Authorization: "Bearer " + token,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
    });
    if (!resp.ok) {
        const text = await resp.text();
        throw new Error("Graph PATCH " + path + " returned " + resp.status + ": " + text);
    }
}

async function graphPost(path, body) {
    const token = await getAccessToken();
    const resp = await fetch(CONFIG.graphBaseURL + path, {
        method: "POST",
        headers: {
            Authorization: "Bearer " + token,
            "Content-Type": "application/json",
        },
        body: JSON.stringify(body),
    });
    if (!resp.ok) {
        const text = await resp.text();
        throw new Error("Graph POST " + path + " returned " + resp.status + ": " + text);
    }
}

// --- Calendar ---

async function fetchNextMeeting() {
    const now = new Date();
    const end = new Date(now.getTime() + 24 * 3600 * 1000);

    const data = await graphGet("/me/calendarView", {
        startDateTime: now.toISOString(),
        endDateTime: end.toISOString(),
        $top: "1",
        $orderby: "start/dateTime",
        $select: "subject,organizer,location,start,end,isOnlineMeeting",
    });

    if (!data.value || data.value.length === 0) return null;

    const event = data.value[0];
    return {
        subject: event.subject,
        organizer: (event.organizer && event.organizer.emailAddress && event.organizer.emailAddress.name) || "",
        location: (event.location && event.location.displayName) || "",
        start: parseGraphDate(event.start.dateTime, event.start.timeZone),
        end: parseGraphDate(event.end.dateTime, event.end.timeZone),
        isOnline: event.isOnlineMeeting,
    };
}

// --- Email ---

async function fetchUnreadEmails() {
    const data = await graphGet("/me/messages", {
        $filter: "isRead eq false",
        $orderby: "receivedDateTime desc",
        $top: "10",
        $select: "id,subject,from,bodyPreview,receivedDateTime",
    });

    return (data.value || []).map(e => ({
        id: e.id,
        subject: e.subject,
        from: e.from.emailAddress.name,
        preview: e.bodyPreview,
        received: new Date(e.receivedDateTime),
    }));
}

async function fetchEmailBody(id) {
    const data = await graphGet("/me/messages/" + id, { $select: "body" });
    let text = data.body.content;
    if (data.body.contentType.toLowerCase() === "html") {
        text = stripHTML(text);
    }
    return stripEmailQuotes(text);
}

async function markEmailRead(id) {
    await graphPatch("/me/messages/" + id, { isRead: true });
}

async function replyToEmail(id, comment) {
    await graphPost("/me/messages/" + id + "/replyAll", { comment });
}

// --- Teams ---

async function fetchPendingChats() {
    const data = await graphGet("/me/chats", {
        $select: "id,topic,chatType,lastMessagePreview",
        $expand: "lastMessagePreview",
        $top: "50",
    });

    const cutoff = new Date(Date.now() - 24 * 3600 * 1000);
    const messages = [];

    for (const chat of data.value || []) {
        const preview = chat.lastMessagePreview;
        if (!preview) continue;
        if (preview.messageType && preview.messageType !== "message") continue;

        const from = preview.from && preview.from.user;
        if (!from) continue;
        if (from.id === state.userID) continue;

        const sent = new Date(preview.createdDateTime);
        if (sent < cutoff) continue;

        let topic = chat.topic || "";
        if (!topic) topic = from.displayName;
        if (!topic) topic = "Chat";

        messages.push({
            chatID: chat.id,
            topic: topic,
            from: from.displayName,
            preview: stripHTML(preview.body.content),
            sent: sent,
        });
    }

    return messages;
}

async function fetchChatMessages(chatID, count = 5) {
    const data = await graphGet("/me/chats/" + chatID + "/messages", { $top: "" + count });

    return (data.value || [])
        .filter(m => m.messageType === "message")
        .map(m => ({
            chatID: chatID,
            topic: "",
            from: (m.from && m.from.user && m.from.user.displayName) || "",
            preview: stripHTML(m.body.content),
            sent: new Date(m.createdDateTime),
        }))
        .reverse(); // oldest first
}

async function sendChatMessage(chatID, text) {
    await graphPost("/me/chats/" + chatID + "/messages", {
        body: { content: text },
    });
}

// ---------------------------------------------------------------------------
// Fetch Summary (orchestration)
// ---------------------------------------------------------------------------

async function fetchSummary() {
    state.isLoading = true;
    state.error = null;
    state.selectedItem = null;
    state.lastViewedItem = null;
    state.detailContent = null;
    renderSummaryLoading();

    // Fetch user ID for Teams heuristic
    try {
        const user = await graphGet("/me", { $select: "id" });
        state.userID = user.id;
    } catch (err) {
        state.error = "Failed to fetch user profile: " + err.message;
        state.isLoading = false;
        renderSummaryError();
        return;
    }

    let meeting = null;
    let emails = [];
    let chats = [];
    let emailError = null;
    let chatError = null;

    try { meeting = await fetchNextMeeting(); } catch {}
    try { emails = await fetchUnreadEmails(); } catch (err) { emailError = err.message; }

    if (state.enableTeams) {
        try { chats = await fetchPendingChats(); } catch (err) { chatError = err.message; }
    }

    state.summary = { meeting, emails, chats, emailError, chatError, teamsEnabled: state.enableTeams };
    state.items = [
        ...emails.map(e => ({ type: "email", data: e })),
        ...chats.map(c => ({ type: "chat", data: c })),
    ];
    state.isLoading = false;

    renderSummary();

    if (state.voiceOnStart) {
        speakSummary(state.summary);
    }
}

// ---------------------------------------------------------------------------
// Speech — Text-to-Speech
// ---------------------------------------------------------------------------

function speechSpeak(text, onComplete) {
    if (!state.userHasInteracted) {
        state.pendingSpeech = text;
        return;
    }
    speechStop();

    // Chromium may not have voices loaded yet. Wait for them.
    function doSpeak() {
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = 1.0;
        utterance.onstart = () => { state.isSpeaking = true; updateSpeechButton(); };
        utterance.onend = () => {
            state.isSpeaking = false;
            updateSpeechButton();
            if (onComplete) onComplete();
        };
        utterance.onerror = () => {
            state.isSpeaking = false;
            updateSpeechButton();
            if (onComplete) onComplete();
        };
        speechSynthesis.speak(utterance);
    }

    if (speechSynthesis.getVoices().length > 0) {
        doSpeak();
    } else {
        speechSynthesis.addEventListener("voiceschanged", doSpeak, { once: true });
    }
}

function speechStop() {
    speechSynthesis.cancel();
    state.isSpeaking = false;
    updateSpeechButton();
}

function updateSpeechButton() {
    const btn = document.getElementById("stop-speech-btn");
    if (state.isSpeaking) {
        btn.classList.remove("hidden");
    } else {
        btn.classList.add("hidden");
    }
}

function speakSummary(summary) {
    const parts = [];

    if (summary.meeting) {
        const time = untilTime(summary.meeting.start);
        let location = "";
        if (summary.meeting.location) {
            location = ", at " + summary.meeting.location;
        } else if (summary.meeting.isOnline) {
            location = ", online";
        }
        parts.push("Your next meeting is " + summary.meeting.subject + ", " + time + location + ".");
    } else {
        parts.push("No upcoming meetings.");
    }

    if (summary.emailError) {
        parts.push("Could not load emails. " + summary.emailError);
    } else if (summary.emails.length === 0) {
        parts.push("No unread emails.");
    } else {
        const count = summary.emails.length;
        const names = listNames(summary.emails.map(e => e.from));
        parts.push("You have " + count + " unread email" + (count === 1 ? "" : "s") + ", from " + names + ".");
    }

    if (summary.teamsEnabled) {
        if (summary.chatError) {
            parts.push("Could not load Teams messages. " + summary.chatError);
        } else if (summary.chats.length === 0) {
            parts.push("No pending Teams messages.");
        } else {
            const count = summary.chats.length;
            const names = listNames(summary.chats.map(c => c.from));
            parts.push("You have " + count + " pending Teams message" + (count === 1 ? "" : "s") + ", from " + names + ".");
        }
    }

    speechSpeak(parts.join(" "));
}

function listNames(names) {
    if (names.length === 0) return "unknown";

    // Count occurrences, preserving first-seen order
    const counts = new Map();
    for (const name of names) {
        counts.set(name, (counts.get(name) || 0) + 1);
    }

    // Format: "Tony, Sarah, Mike three times, Lisa twice"
    // (Placed after the name so the caller can safely prepend "from".)
    const parts = [];
    for (const [name, count] of counts) {
        if (count === 1) {
            parts.push(name);
        } else if (count === 2) {
            parts.push(name + " twice");
        } else {
            parts.push(name + " " + count + " times");
        }
    }

    if (parts.length === 1) return parts[0];
    if (parts.length === 2) return parts[0] + " and " + parts[1];
    return parts.slice(0, -1).join(", ") + ", and " + parts[parts.length - 1];
}

// ---------------------------------------------------------------------------
// Speech — Speech Recognition (Dictation)
// ---------------------------------------------------------------------------

let recognition = null;
let finalTranscript = "";

function initRecognition() {
    const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
    if (!SpeechRecognition) {
        disableMic("Voice input is not supported in this browser.");
        return;
    }

    recognition = new SpeechRecognition();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = "en-US";

    recognition.onstart = () => {
        console.log("Recognition started");
    };

    recognition.onaudiostart = () => {
        console.log("Audio capturing started");
    };

    recognition.onresult = (event) => {
        for (let i = event.resultIndex; i < event.results.length; i++) {
            if (event.results[i].isFinal) {
                finalTranscript += event.results[i][0].transcript;
            }
        }
        console.log("Recognition result:", finalTranscript || "(interim only)");
    };

    recognition.onend = () => {
        console.log("Recognition ended, transcript:", finalTranscript || "(empty)");
        state.isListening = false;
        document.getElementById("mic-btn").classList.remove("listening");
        if (finalTranscript.trim()) {
            const transcript = finalTranscript.trim();
            finalTranscript = "";
            if (state.replyMode) {
                handleReplyVoiceInput(transcript);
            } else {
                handleVoiceCommand(transcript);
            }
        } else if (state.replyMode === "dictating") {
            // User clicked mic but said nothing while dictating — trigger confirm
            confirmReply();
        }
    };

    recognition.onerror = (event) => {
        console.warn("Speech recognition error:", event.error);
        state.isListening = false;
        document.getElementById("mic-btn").classList.remove("listening");
        finalTranscript = "";

        if (event.error === "network" || event.error === "service-not-allowed") {
            recognition = null;
            disableMic("Voice input is not available. This browser cannot reach the speech recognition service.");
        } else if (event.error === "not-allowed") {
            recognition = null;
            disableMic("Microphone access was denied.");
        }
    };
}

function disableMic(message) {
    const btn = document.getElementById("mic-btn");
    btn.disabled = true;
    btn.title = message;
    // Show message briefly above the mic button
    const notice = document.getElementById("mic-notice");
    if (notice) {
        notice.textContent = message;
        notice.classList.remove("hidden");
    }
}

function startListening() {
    if (!recognition) return;
    if (state.isListening) return;
    speechStop();
    finalTranscript = "";
    state.isListening = true;
    document.getElementById("mic-btn").classList.add("listening");
    try {
        recognition.start();
    } catch {
        state.isListening = false;
        document.getElementById("mic-btn").classList.remove("listening");
    }
}

function stopListening() {
    if (!recognition) return;
    recognition.stop();
}

// ---------------------------------------------------------------------------
// Voice Command System
//
// Inspired by Pike's regex: a single recursive function (resolveCommand)
// that progressively fills in a command structure, asking questions to
// fill gaps. Each user response feeds back into the same function.
//
// Command shape:
//   { action, itemType, name, number, qualifier, target, candidates }
//
//   action:    "read" | "reply" | "markRead" — what to do
//   itemType:  "email" | "chat" | null       — narrows the item type
//   name:      string | null                 — sender name to match
//   number:    int | null                    — item number from the list
//   qualifier: "latest" | "oldest" | null    — time-based selection
//   target:    resolved item | null          — filled when resolved
//   candidates: [items] | null               — filled when ambiguous
//
// resolveCommand is called:
//   1. When a new voice command is parsed (initial call)
//   2. When the user answers a clarifying question (continuation)
//   3. From the detail page with target pre-filled (no questions needed)
// ---------------------------------------------------------------------------

// Simple commands: exact match, no target needed
const SIMPLE_COMMANDS = {
    "send":           "send",
    "send it":        "send",
    "cancel":         "cancel",
    "never mind":     "cancel",
    "refresh":        "refresh",
    "check again":    "refresh",
    "check in":       "refresh",
    "stop":           "stop",
    "be quiet":       "stop",
    "shut up":        "stop",
    "go back":        "back",
    "back":           "back",
    "mark all read":       "markAllRead",
    "mark all as read":    "markAllRead",
    "mark all done":       "markAllRead",
    "help":                "help",
    "help me":             "help",
    "what can i do":       "help",
    "what can i say":      "help",
    "commands":            "help",
};

// Time qualifiers extracted from anywhere in the transcript
const LATEST_WORDS = ["latest", "newest", "most recent", "last one", "recent"];
const OLDEST_WORDS = ["oldest", "earliest", "first one"];

// Pattern table: ordered by specificity (longest prefixes first).
// Each pattern extracts action, itemType, and the remaining text as a name.
const COMMAND_PATTERNS = [
    // Read — with explicit type and qualifier
    { prefixes: ["read latest email from", "read most recent email from"],
      action: "read", itemType: "email", qualifier: "latest" },
    { prefixes: ["read oldest email from", "read earliest email from"],
      action: "read", itemType: "email", qualifier: "oldest" },

    // Read — with explicit type
    { prefixes: ["read email from", "open email from", "email from"],
      action: "read", itemType: "email" },
    { prefixes: ["read chat from", "open chat from", "chat from",
                  "read message from", "open message from", "message from"],
      action: "read", itemType: "chat" },

    // Read — infer type, with qualifier
    { prefixes: ["read latest from", "read most recent from", "read newest from"],
      action: "read", qualifier: "latest" },
    { prefixes: ["read oldest from", "read earliest from"],
      action: "read", qualifier: "oldest" },

    // Read — infer type
    { prefixes: ["read from", "open from"],
      action: "read" },

    // Reply — with explicit type and qualifier
    { prefixes: ["reply to latest email from"],
      action: "reply", itemType: "email", qualifier: "latest" },

    // Reply — with explicit type
    { prefixes: ["reply to email from", "respond to email from",
                  "reply all to email from"],
      action: "reply", itemType: "email" },
    { prefixes: ["reply to chat from", "respond to chat from",
                  "reply to message from", "respond to message from"],
      action: "reply", itemType: "chat" },

    // Reply — infer type, with qualifier
    { prefixes: ["reply to latest from"],
      action: "reply", qualifier: "latest" },

    // Reply — infer type
    { prefixes: ["reply to", "respond to", "reply all to"],
      action: "reply" },

    // Mark read — explicit
    { prefixes: ["mark email from", "mark email as read from"],
      action: "markRead", itemType: "email" },
    { prefixes: ["mark as read from", "mark read from", "mark done from",
                  "done with"],
      action: "markRead", itemType: "email" },

    // Read/Reply — bare (just "reply" or "read 4")
    { prefixes: ["read number", "open number", "read item", "open item",
                  "number"],
      action: "read", extractNumber: true },
    { prefixes: ["read", "open"],
      action: "read", extractNumber: true },
    { prefixes: ["reply"],
      action: "reply" },
    { prefixes: ["mark as read", "mark read"],
      action: "markRead", itemType: "email" },
];

function normalizeTranscript(transcript) {
    let text = transcript.toLowerCase().trim()
        .replace(/[.,!?]/g, "")
        .replace(/e-mail/g, "email")
        .replace(/\b(the|a|an)\b/g, "");

    // Normalize possessives: "Mark's email" → "email from Mark"
    // "David Anderson's latest email" → "latest email from David Anderson"
    // "Reply to Tony's chat" → "reply to chat from Tony"
    const possMatch = text.match(/(.*?)'s\s+(.*?\b)(email|chat|message)\b(.*)/);
    if (possMatch) {
        const beforePoss = possMatch[1].trim();
        const between = possMatch[2].trim();
        const typeWord = possMatch[3];
        const after = possMatch[4].trim();

        const verbs = new Set(["read", "open", "reply", "respond", "done"]);
        let actionPart, name;

        const toIdx = beforePoss.lastIndexOf(" to ");
        if (toIdx >= 0) {
            actionPart = beforePoss.slice(0, toIdx) + " to";
            name = beforePoss.slice(toIdx + 4).trim();
        } else {
            const words = beforePoss.split(/\s+/);
            let i = 0;
            while (i < words.length && verbs.has(words[i])) i++;

            if (i > 0 && i < words.length) {
                actionPart = words.slice(0, i).join(" ");
                name = words.slice(i).join(" ");
            } else if (i === 0) {
                actionPart = "";
                name = beforePoss;
            } else {
                actionPart = words.slice(0, i - 1).join(" ");
                name = words[i - 1];
            }
        }

        const parts = [actionPart, between, typeWord, "from", name, after];
        text = parts.filter(Boolean).join(" ");
    }

    // Apostrophe-less form: "marks email" → "email from mark"
    if (!text.includes("'")) {
        text = text.replace(/\b(\w+)s\s+(email|chat|message)\b/, "$2 from $1");
    }

    return text.replace(/\s+/g, " ").trim();
}

function extractAfterPrefix(text, prefixes) {
    for (const prefix of prefixes) {
        if (text === prefix) return "";
        if (text.startsWith(prefix + " ")) {
            return text.slice(prefix.length + 1).trim();
        }
    }
    return null;
}

function parseNumber(text) {
    const words = {
        one: 1, two: 2, three: 3, four: 4, five: 5,
        six: 6, seven: 7, eight: 8, nine: 9, ten: 10,
    };
    if (words[text]) return words[text];
    const n = parseInt(text, 10);
    return isNaN(n) ? null : n;
}

function extractQualifier(text) {
    if (LATEST_WORDS.some(w => text.includes(w))) return "latest";
    if (OLDEST_WORDS.some(w => text.includes(w))) return "oldest";
    return null;
}

// Parse a transcript into a partial command object
function parseVoiceCommand(transcript) {
    const text = normalizeTranscript(transcript);

    // Simple commands (no target)
    if (SIMPLE_COMMANDS[text]) {
        return { action: SIMPLE_COMMANDS[text] };
    }

    // Pattern matching
    for (const pattern of COMMAND_PATTERNS) {
        const remainder = extractAfterPrefix(text, pattern.prefixes);
        if (remainder === null) continue;

        const cmd = {
            action: pattern.action,
            itemType: pattern.itemType || null,
            qualifier: pattern.qualifier || null,
        };

        const cleaned = remainder.replace(/\s+as\s+read$/, "").trim();

        if (pattern.extractNumber && cleaned) {
            const num = parseNumber(cleaned);
            if (num !== null) {
                cmd.number = num;
                return cmd;
            }
        }

        if (cleaned) {
            // Check for inline qualifier in the name portion
            if (!cmd.qualifier) cmd.qualifier = extractQualifier(cleaned);
            // Strip qualifier words from name
            let name = cleaned;
            [...LATEST_WORDS, ...OLDEST_WORDS].forEach(w => {
                name = name.replace(new RegExp("\\b" + w + "\\b", "g"), "");
            });
            name = name.replace(/\s+/g, " ").trim();
            if (name) cmd.name = name;
        }

        return cmd;
    }

    return { action: "unknown", text };
}

// ---------------------------------------------------------------------------
// Command Resolution (the recursive core)
//
// Takes a partial command and tries to fill in the target. If it can't
// determine a unique target, it asks the user and saves the partial
// command as state.pendingCommand for the next voice input to continue.
// ---------------------------------------------------------------------------

function resolveCommand(cmd, transcript = "") {
    console.log("Resolving command:", JSON.stringify(cmd));

    // If target is already set (e.g., from detail page), execute
    if (cmd.target) {
        executeCommand(cmd);
        return;
    }

    // By number — direct index, always unambiguous
    if (cmd.number) {
        const idx = cmd.number - 1;
        if (idx >= 0 && idx < state.items.length) {
            cmd.target = state.items[idx];
            executeCommand(cmd);
        } else {
            logUnrecognized(transcript, JSON.stringify(cmd), "number_out_of_range");
            speechSpeak("There is no item " + cmd.number + ".");
        }
        return;
    }

    // Find candidates
    let candidates;
    if (cmd.name) {
        const nameLower = cmd.name.toLowerCase();
        candidates = state.items.filter(i => {
            if (cmd.itemType && i.type !== cmd.itemType) return false;
            return i.data.from.toLowerCase().includes(nameLower);
        });
    } else if (cmd.itemType) {
        candidates = state.items.filter(i => i.type === cmd.itemType);
    } else {
        candidates = null; // no name, no type — need context
    }

    // No name and no candidates — try context
    if (!candidates) {
        const ctx = state.lastViewedItem || state.selectedItem;
        if (ctx) {
            cmd.target = ctx;
            executeCommand(cmd);
        } else {
            // Ask who
            state.pendingCommand = cmd;
            speechSpeak("Who would you like to " + actionVerb(cmd.action) + "?");
        }
        return;
    }

    // No matches
    if (candidates.length === 0) {
        logUnrecognized(transcript, JSON.stringify(cmd), "no_match");
        speechSpeak("I didn't find a match for that.");
        return;
    }

    // Exactly one — done
    if (candidates.length === 1) {
        cmd.target = candidates[0];
        executeCommand(cmd);
        return;
    }

    // Multiple matches — try qualifier to narrow
    if (cmd.qualifier) {
        const sorted = [...candidates].sort((a, b) => {
            const timeA = (a.data.received || a.data.sent).getTime();
            const timeB = (b.data.received || b.data.sent).getTime();
            return timeB - timeA;
        });
        cmd.target = cmd.qualifier === "latest" ? sorted[0] : sorted[sorted.length - 1];
        executeCommand(cmd);
        return;
    }

    // Multiple matches — try context
    if (state.lastViewedItem) {
        const exact = candidates.find(c =>
            c.type === state.lastViewedItem.type &&
            c.data.id === state.lastViewedItem.data.id
        );
        if (exact) {
            cmd.target = exact;
            executeCommand(cmd);
            return;
        }
    }

    // Still ambiguous — ask the user
    cmd.candidates = candidates;
    state.pendingCommand = cmd;
    speechSpeak(askWhichOne(candidates));
}

// Choose a disambiguation prompt based on what distinguishes the candidates.
// - Multiple senders: list sender names.
// - Single sender, distinct subjects: list subjects.
// - Single sender, identical subjects (e.g. duplicate emails): prompt by position.
function askWhichOne(candidates) {
    const senders = [...new Set(candidates.map(c => c.data.from))];
    if (senders.length > 1) {
        return "Which one? " + listNames(senders) + "?";
    }
    const labels = candidates.map(c =>
        c.type === "email" ? cleanSubject(c.data.subject) : c.data.topic
    );
    const allSame = new Set(labels).size === 1;
    if (allSame) {
        if (candidates.length === 2) {
            return "There are two of those. Say first or second?";
        }
        return "There are " + candidates.length + " of those. Say a number from one to "
            + candidates.length + "?";
    }
    const descriptions = candidates.map(c => describeCandidate(c));
    return "Which one? " + descriptions.join("? Or ") + "?";
}

function actionVerb(action) {
    switch (action) {
        case "read": return "read";
        case "reply": return "reply to";
        case "markRead": return "mark as read";
        default: return "do that to";
    }
}

function describeCandidate(item) {
    if (item.type === "email") {
        return "the email about " + cleanSubject(item.data.subject);
    }
    return "the chat with " + item.data.topic;
}

// Handle a voice response to a pending command's question
function continuePendingCommand(transcript) {
    const text = normalizeTranscript(transcript);
    const cmd = state.pendingCommand;

    // Confirmation dialog for destructive actions (yes / no)
    if (cmd.awaitingConfirmation) {
        const CONFIRM = ["yes", "confirm", "send", "send it", "ok", "okay",
                         "go ahead", "do it", "yep", "yeah"];
        const DENY = ["cancel", "never mind", "no", "nope", "stop"];
        if (DENY.includes(text)) {
            state.pendingCommand = null;
            speechSpeak("Cancelled.");
            return;
        }
        if (CONFIRM.includes(text)) {
            state.pendingCommand = null;
            cmd.confirmed = true;
            cmd.awaitingConfirmation = false;
            executeCommand(cmd);
            return;
        }
        speechSpeak("Say yes to confirm, or cancel.");
        return;
    }

    // Cancel (disambiguation context)
    if (text === "cancel" || text === "never mind") {
        state.pendingCommand = null;
        return;
    }

    // Check for qualifier
    const qualifier = extractQualifier(text);
    if (qualifier && cmd.candidates && cmd.candidates.length > 1) {
        cmd.qualifier = qualifier;
        state.pendingCommand = null;
        resolveCommand(cmd, transcript);
        return;
    }

    // Check for ordinal or number
    const ordinals = { "first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5,
                       "the first one": 1, "the second one": 2, "the third one": 3,
                       "1st": 1, "2nd": 2, "3rd": 3, "4th": 4, "5th": 5 };
    const num = parseNumber(text) || ordinals[text];
    if (num && cmd.candidates && num >= 1 && num <= cmd.candidates.length) {
        cmd.target = cmd.candidates[num - 1];
        state.pendingCommand = null;
        executeCommand(cmd);
        return;
    }

    // Check for type narrowing ("the email", "the chat")
    if (!cmd.itemType) {
        if (text.includes("email") || text.includes("mail")) {
            cmd.itemType = "email";
        } else if (text.includes("chat") || text.includes("message")) {
            cmd.itemType = "chat";
        }
    }

    // Check for name in the response
    // The user might say a full name, a partial name, or a subject keyword
    if (cmd.candidates && cmd.candidates.length > 1) {
        const scored = cmd.candidates.map(item => {
            let score = 0;
            const from = item.data.from.toLowerCase();
            const subject = (item.type === "email" ?
                cleanSubject(item.data.subject) : item.data.topic).toLowerCase();

            if (text.includes(from)) score += 3;
            from.split(/\s+/).forEach(w => { if (w.length > 2 && text.includes(w)) score += 1; });
            subject.split(/\s+/).forEach(w => { if (w.length > 2 && text.includes(w)) score += 1; });
            if (item.type === "email" && (text.includes("email") || text.includes("mail"))) score += 2;
            if (item.type === "chat" && (text.includes("chat") || text.includes("message"))) score += 2;

            return { item, score };
        });

        const maxScore = Math.max(0, ...scored.map(s => s.score));
        if (maxScore > 0) {
            const topMatches = scored
                .filter(s => s.score === maxScore)
                .map(s => s.item);

            if (topMatches.length === 1) {
                cmd.target = topMatches[0];
                state.pendingCommand = null;
                executeCommand(cmd);
                return;
            }

            // Tied at the top — narrow the candidate list and fall through
            // to re-prompt. The narrower prompt will use askWhichOne to pick
            // the right disambiguation strategy (sender / subject / ordinal).
            if (topMatches.length < cmd.candidates.length) {
                cmd.candidates = topMatches;
                state.pendingCommand = cmd;
            }
        }
    }

    // If we didn't have candidates before but now have a name, try resolving again
    if (!cmd.candidates || cmd.candidates.length === 0) {
        // The response is probably a name
        const cleaned = text.replace(/\s+/g, " ").trim();
        if (cleaned) {
            cmd.name = cleaned;
            state.pendingCommand = null;
            resolveCommand(cmd, transcript);
            return;
        }
    }

    // Still can't tell — repeat using the shared prompt builder
    if (cmd.candidates && cmd.candidates.length > 1) {
        speechSpeak(askWhichOne(cmd.candidates));
    } else {
        speechSpeak("Who would you like to " + actionVerb(cmd.action) + "?");
    }
}

// ---------------------------------------------------------------------------
// Command Execution
// ---------------------------------------------------------------------------

async function executeCommand(cmd) {
    state.pendingCommand = null;

    switch (cmd.action) {
        case "read":
            await viewDetail(cmd.target, true);
            break;
        case "reply":
            showReply(cmd.target, true);
            break;
        case "markRead":
            if (cmd.target.type !== "email") {
                speechSpeak("Only emails can be marked as read.");
                return;
            }
            if (!cmd.confirmed) {
                cmd.awaitingConfirmation = true;
                state.pendingCommand = cmd;
                speechSpeak(
                    "Mark " + cmd.target.data.from + "'s email as read? " +
                    "Say yes to confirm, or cancel."
                );
                return;
            }
            await performMarkRead(cmd.target);
            break;
        case "markAllRead":
            await performMarkAllRead();
            break;
    }
}

async function performMarkAllRead() {
    if (!state.summary) return;
    for (const email of state.summary.emails) {
        try { await markEmailRead(email.id); } catch {}
    }
    state.lastViewedItem = null;
    await fetchSummary();
    speechSpeak("All emails marked as read.");
}

async function performMarkRead(target) {
    await markEmailRead(target.data.id);
    state.items = state.items.filter(i => i.data.id !== target.data.id);
    state.summary.emails = state.summary.emails.filter(e => e.id !== target.data.id);
    if (state.lastViewedItem && state.lastViewedItem.data.id === target.data.id) {
        state.lastViewedItem = null;
    }
    showSummaryView();
    renderSummary();
    speechSpeak("Marked as read.");
}

function speakHelp() {
    const lines = [
        "You can say: read email from a name, or reply to chat from a name.",
        "To pick one when there are several, say latest or oldest, or give a number.",
        "Other commands: mark as read, reply, send, cancel, refresh, go back, and stop.",
    ];
    speechSpeak(lines.join(" "));
    showHelp();
}

function showHelp() {
    document.getElementById("help-panel").classList.remove("hidden");
}

function hideHelp() {
    document.getElementById("help-panel").classList.add("hidden");
}

function logUnrecognized(original, normalized, reason = "no_pattern_match") {
    console.warn("Unrecognized command:", { original, normalized, reason });
    try {
        const key = "unrecognizedUtterances";
        const existing = JSON.parse(localStorage.getItem(key) || "[]");
        existing.push({
            timestamp: new Date().toISOString(),
            original: original,
            normalized: normalized,
            reason: reason,
        });
        localStorage.setItem(key, JSON.stringify(existing.slice(-200)));
    } catch (err) {
        console.warn("Failed to log unrecognized utterance:", err);
    }
}

async function handleVoiceCommand(transcript) {
    console.log("Voice transcript:", transcript);

    // If there's a pending command waiting for clarification, continue it
    if (state.pendingCommand) {
        continuePendingCommand(transcript);
        return;
    }

    const command = parseVoiceCommand(transcript);
    console.log("Parsed command:", JSON.stringify(command));

    // Simple commands — no target needed
    switch (command.action) {
        case "send":
            return;
        case "cancel":
            state.pendingCommand = null;
            hideReply();
            return;
        case "back":
            showSummaryView();
            renderSummary();
            return;
        case "refresh":
            await fetchSummary();
            return;
        case "markAllRead":
            if (!state.summary || state.summary.emails.length === 0) {
                speechSpeak("No unread emails to mark.");
                return;
            }
            state.pendingCommand = {
                action: "markAllRead",
                awaitingConfirmation: true,
            };
            speechSpeak(
                "Mark all " + state.summary.emails.length + " unread emails as read? " +
                "Say yes to confirm, or cancel."
            );
            return;
        case "stop":
            speechStop();
            state.pendingCommand = null;
            return;
        case "help":
            speakHelp();
            return;
        case "unknown":
            logUnrecognized(transcript, command.text || "");
            speechSpeak(
                "I heard: " + transcript + ". " +
                "I'm not sure what to do with that. " +
                "Say help to hear what you can say."
            );
            return;
    }

    // Target-based commands — resolve through the recursive resolver
    resolveCommand(command, transcript);
}

// ---------------------------------------------------------------------------
// Detail View
// ---------------------------------------------------------------------------

async function viewDetail(item, speak = false) {
    state.selectedItem = item;
    state.lastViewedItem = item;
    state.isLoadingDetail = true;
    showDetailView();

    if (item.type === "email") {
        renderDetailHeader(item.data.subject, "From: " + item.data.from, relativeTime(item.data.received));
        renderDetailLoading();
        try {
            const body = await fetchEmailBody(item.data.id);
            state.detailContent = body;
            renderDetailBody(body);
            if (speak) {
                speechSpeak("Email from " + item.data.from + " about " + cleanSubject(item.data.subject) + ". " + body);
            }
        } catch (err) {
            renderDetailBody("Failed to load email: " + err.message);
        }
    } else {
        renderDetailHeader(item.data.topic, "", relativeTime(item.data.sent));
        renderDetailLoading();
        try {
            const messages = await fetchChatMessages(item.data.chatID);
            state.detailContent = messages;
            renderChatMessages(messages);
            if (speak) {
                const script = messages.map(m => m.from + " said: " + m.preview).join(". ");
                speechSpeak("Chat with " + item.data.topic + ". " + script);
            }
        } catch {
            renderDetailBody("Failed to load chat messages.");
        }
    }

    state.isLoadingDetail = false;
}

// ---------------------------------------------------------------------------
// Reply
// ---------------------------------------------------------------------------

function showReply(item, autoStartMic = false) {
    state.replyItem = item;
    state.replyMode = "dictating";
    const label = document.getElementById("reply-to-label");
    label.textContent = "Replying to " + item.data.from;
    document.getElementById("reply-draft").value = "";
    document.getElementById("reply-send-btn").disabled = true;
    document.getElementById("reply-modal").classList.remove("hidden");
    document.getElementById("reply-draft").focus();

    if (autoStartMic) {
        speechSpeak(
            "Dictate your reply. Press the microphone when you are done.",
            () => {
                if (state.replyMode === "dictating" && !state.isListening) {
                    startListening();
                }
            }
        );
    } else {
        speechSpeak("Press the microphone to dictate, or type your reply.");
    }
}

function hideReply() {
    state.replyItem = null;
    state.replyMode = null;
    document.getElementById("reply-modal").classList.add("hidden");
}

function confirmReply() {
    const draft = document.getElementById("reply-draft").value.trim();
    if (!draft) {
        speechSpeak("Your message is empty. Dictate your reply, or say cancel.");
        state.replyMode = "dictating";
        return;
    }
    state.replyMode = "confirming";
    speechSpeak(
        "Your message says: " + draft + ". Ready to send it? Or cancel?",
        () => {
            if (state.replyMode === "confirming" && !state.isListening) {
                startListening();
            }
        }
    );
}

function handleReplyVoiceInput(transcript) {
    if (state.replyMode === "dictating") {
        // Append dictated text to the draft, then auto-advance to confirmation
        const textarea = document.getElementById("reply-draft");
        const current = textarea.value;
        textarea.value = current ? current + " " + transcript : transcript;
        document.getElementById("reply-send-btn").disabled = false;
        confirmReply();
        return;
    }

    if (state.replyMode === "confirming") {
        const text = transcript.toLowerCase().trim()
            .replace(/[.,!?]/g, "");

        if (text === "send" || text === "send it") {
            sendReply();
        } else if (text === "cancel") {
            speechSpeak("Reply cancelled.");
            hideReply();
        } else {
            speechSpeak("Ready to send it? Or cancel?");
        }
    }
}

async function sendReply() {
    const draft = document.getElementById("reply-draft").value.trim();
    if (!draft || !state.replyItem) return;

    state.isSending = true;
    document.getElementById("reply-send-btn").disabled = true;
    speechSpeak("Sending.");

    try {
        if (state.replyItem.type === "email") {
            await replyToEmail(state.replyItem.data.id, draft);
        } else {
            await sendChatMessage(state.replyItem.data.chatID, draft);
        }
        hideReply();
        speechSpeak("Reply sent.");
        await fetchSummary();
    } catch (err) {
        speechSpeak("Failed to send. " + err.message);
    }

    state.isSending = false;
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

function showSignIn() {
    document.getElementById("sign-in-screen").classList.remove("hidden");
    document.getElementById("app-screen").classList.add("hidden");
}

function showApp() {
    document.getElementById("sign-in-screen").classList.add("hidden");
    document.getElementById("app-screen").classList.remove("hidden");
}

function showSignInError(msg) {
    const el = document.getElementById("sign-in-error");
    el.textContent = msg;
    el.classList.remove("hidden");
}

function showSummaryView() {
    document.getElementById("summary-view").classList.remove("hidden");
    document.getElementById("detail-view").classList.add("hidden");
    document.getElementById("back-btn").classList.add("hidden");
    state.selectedItem = null;
    state.detailContent = null;
}

function showDetailView() {
    document.getElementById("summary-view").classList.add("hidden");
    document.getElementById("detail-view").classList.remove("hidden");
    document.getElementById("back-btn").classList.remove("hidden");
}

function renderSummaryLoading() {
    document.getElementById("loading").classList.remove("hidden");
    document.getElementById("summary-content").innerHTML = "";
    document.getElementById("error-display").classList.add("hidden");
}

function renderSummaryError() {
    document.getElementById("loading").classList.add("hidden");
    document.getElementById("error-text").textContent = state.error;
    document.getElementById("error-display").classList.remove("hidden");
}

function renderSummary() {
    document.getElementById("loading").classList.add("hidden");
    document.getElementById("error-display").classList.add("hidden");

    const s = state.summary;
    if (!s) return;

    let html = "";

    // Meeting section
    if (s.meeting) {
        const time = untilTime(s.meeting.start);
        const urgencyClass = meetingUrgencyClass(s.meeting.start);
        let locationText = "";
        if (s.meeting.location) {
            locationText = s.meeting.location;
        } else if (s.meeting.isOnline) {
            locationText = "Online";
        }
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128197;</span>';
        html += '<span class="section-title">' + esc(s.meeting.subject) + "</span>";
        html += "</div>";
        html += '<div style="padding-left: 30px; font-size: 12px;">';
        html += '<span class="' + urgencyClass + '">' + esc(time) + "</span>";
        if (locationText) html += ' <span class="muted">' + esc(locationText) + "</span>";
        html += "</div>";
    } else {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128197;</span>';
        html += '<span class="muted">No upcoming meetings</span>';
        html += "</div>";
    }
    html += '<hr class="divider">';

    // Email section
    if (s.emailError) {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#9993;</span>';
        html += '<span class="error">Could not load emails: ' + esc(s.emailError) + "</span>";
        html += "</div>";
    } else if (s.emails.length === 0) {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#9993;</span>';
        html += '<span class="muted">No unread emails</span>';
        html += "</div>";
    } else {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#9993;</span>';
        html += '<span class="section-title">unread emails (' + s.emails.length + "):</span>";
        html += "</div>";
        s.emails.forEach((email, i) => {
            html += itemRowHTML(i + 1, email.from, truncate(email.subject, 40), relativeTime(email.received), "email", i);
        });
    }
    html += '<hr class="divider">';

    // Teams section
    if (!s.teamsEnabled) {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128172;</span>';
        html += '<span class="muted">Teams disabled</span>';
        html += "</div>";
    } else if (s.chatError) {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128172;</span>';
        html += '<span class="error">Could not load chats: ' + esc(s.chatError) + "</span>";
        html += "</div>";
    } else if (s.chats.length === 0) {
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128172;</span>';
        html += '<span class="muted">No pending chats</span>';
        html += "</div>";
    } else {
        const offset = s.emails.length;
        html += '<div class="section-header">';
        html += '<span class="section-icon">&#128172;</span>';
        html += '<span class="section-title">pending chats (' + s.chats.length + "):</span>";
        html += "</div>";
        s.chats.forEach((chat, i) => {
            html += itemRowHTML(offset + i + 1, chat.topic, truncate(chat.preview, 40), relativeTime(chat.sent), "chat", i);
        });
    }

    document.getElementById("summary-content").innerHTML = html;

    // Attach click handlers to item rows
    document.querySelectorAll("[data-item-type]").forEach(el => {
        el.addEventListener("click", () => {
            const type = el.dataset.itemType;
            const idx = parseInt(el.dataset.itemIndex, 10);
            const source = type === "email" ? state.summary.emails : state.summary.chats;
            const data = source[idx];
            if (data) viewDetail({ type, data });
        });
    });
}

function itemRowHTML(number, from, detail, time, type, index) {
    return '<div class="item-row" data-item-type="' + type + '" data-item-index="' + index + '">'
        + '<span class="item-number">' + number + ". </span>"
        + '<div class="item-detail">'
        + '<div class="item-from">' + esc(from) + ': "' + esc(detail) + '"</div>'
        + '<div class="item-time">' + esc(time) + "</div>"
        + "</div></div>";
}

function renderDetailHeader(title, meta, time) {
    let html = "<h2>" + esc(title) + "</h2>";
    if (meta) html += '<div class="detail-meta">' + esc(meta) + "</div>";
    html += '<div class="detail-time">' + esc(time) + "</div>";

    // Action buttons
    html += '<div style="margin-top: 8px;">';
    if (state.selectedItem && state.selectedItem.type === "email") {
        html += '<button class="btn-link" id="detail-mark-read-btn" style="margin-right: 16px;">Mark Read</button>';
    }
    html += '<button class="btn-link" id="detail-reply-btn">Reply</button>';
    html += "</div>";

    document.getElementById("detail-header").innerHTML = html;

    // Attach handlers after rendering
    const markReadBtn = document.getElementById("detail-mark-read-btn");
    if (markReadBtn) {
        markReadBtn.addEventListener("click", async () => {
            const item = state.selectedItem;
            if (item && item.type === "email") {
                await markEmailRead(item.data.id);
                state.items = state.items.filter(i => i.data.id !== item.data.id);
                state.summary.emails = state.summary.emails.filter(e => e.id !== item.data.id);
                showSummaryView();
                renderSummary();
            }
        });
    }

    const replyBtn = document.getElementById("detail-reply-btn");
    if (replyBtn) {
        replyBtn.addEventListener("click", () => {
            if (state.selectedItem) showReply(state.selectedItem);
        });
    }
}

function renderDetailLoading() {
    document.getElementById("detail-body").innerHTML = '<p class="accent">Loading...</p>';
}

function renderDetailBody(text) {
    document.getElementById("detail-body").textContent = text;
}

function renderChatMessages(messages) {
    let html = "";
    for (const msg of messages) {
        html += '<div class="chat-message">';
        html += '<div class="chat-message-from">' + esc(msg.from) + "</div>";
        html += '<div class="chat-message-text">' + esc(msg.preview) + "</div>";
        html += '<div class="chat-message-time">' + esc(relativeTime(msg.sent)) + "</div>";
        html += "</div>";
    }
    document.getElementById("detail-body").innerHTML = html;
}

function meetingUrgencyClass(start) {
    const until = start.getTime() - Date.now();
    if (until < 0) return "error";
    if (until < 15 * 60 * 1000) return "warning";
    return "accent";
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

function showSettings() {
    document.getElementById("setting-teams").checked = state.enableTeams;
    document.getElementById("setting-voice").checked = state.voiceOnStart;
    document.getElementById("settings-panel").classList.remove("hidden");
}

function hideSettings() {
    document.getElementById("settings-panel").classList.add("hidden");
}

function saveSettings() {
    const teamsChanged = document.getElementById("setting-teams").checked !== state.enableTeams;
    state.enableTeams = document.getElementById("setting-teams").checked;
    state.voiceOnStart = document.getElementById("setting-voice").checked;
    localStorage.setItem("enableTeams", state.enableTeams);
    localStorage.setItem("voiceOnStart", state.voiceOnStart);
    hideSettings();

    // If Teams toggle changed, re-authenticate to get the right scopes and refresh
    if (teamsChanged) {
        msalApp.acquireTokenPopup({ scopes: getScopes(), account: state.account })
            .then(() => fetchSummary())
            .catch(() => {});
    }
}

// ---------------------------------------------------------------------------
// Utility Functions
// ---------------------------------------------------------------------------

function cleanSubject(subject) {
    // Strip RE:, FW:, FWD: and variations (case-insensitive, repeated)
    return subject.replace(/^(\s*(re|fw|fwd)\s*:\s*)+/i, "").trim() || subject;
}

function relativeTime(date) {
    const seconds = (Date.now() - date.getTime()) / 1000;
    if (seconds < 60) return "just now";
    if (seconds < 3600) {
        const m = Math.floor(seconds / 60);
        return m === 1 ? "1 min ago" : m + " min ago";
    }
    if (seconds < 86400) {
        const h = Math.floor(seconds / 3600);
        return h === 1 ? "1 hour ago" : h + " hours ago";
    }
    const d = Math.floor(seconds / 86400);
    return d === 1 ? "yesterday" : d + " days ago";
}

function untilTime(date) {
    const seconds = (date.getTime() - Date.now()) / 1000;
    if (seconds < 60) return "now";

    const totalMinutes = Math.floor(seconds / 60);
    const hours = Math.floor(totalMinutes / 60);
    const minutes = totalMinutes % 60;

    if (hours === 0) return minutes === 1 ? "in 1 min" : "in " + minutes + " min";
    if (minutes === 0) return hours === 1 ? "in 1 hour" : "in " + hours + " hours";
    return "in " + hours + "h" + minutes + "m";
}

function truncate(s, maxLen) {
    const cleaned = s.replace(/\n/g, " ").replace(/\r/g, "");
    if (cleaned.length <= maxLen) return cleaned;
    return cleaned.slice(0, maxLen - 1) + "\u2026";
}

function esc(s) {
    const el = document.createElement("span");
    el.textContent = s;
    return el.innerHTML;
}

function parseGraphDate(dateString, timeZone) {
    // Graph returns naive datetime + timezone name.
    // The browser's Date constructor handles ISO strings, but we need to
    // account for the timezone. For simplicity, treat as UTC-like and let
    // the browser's Intl handle display. This matches the iOS behavior
    // closely enough for an MVP.
    // Strip trailing fractional seconds beyond ms precision
    const cleaned = dateString.replace(/(\.\d{3})\d*/, "$1");
    // If no Z or offset, append Z (Graph datetimes are in the stated timezone,
    // but for display purposes the relative time calculation is close enough)
    if (!cleaned.endsWith("Z") && !cleaned.match(/[+-]\d{2}:\d{2}$/)) {
        return new Date(cleaned + "Z");
    }
    return new Date(cleaned);
}

function stripHTML(html) {
    let s = html;
    // Remove style and script blocks
    s = s.replace(/<style[^>]*>[\s\S]*?<\/style>/gi, "");
    s = s.replace(/<script[^>]*>[\s\S]*?<\/script>/gi, "");
    // Remove HTML comments
    s = s.replace(/<!--[\s\S]*?-->/g, "");
    // Replace block elements with newlines
    s = s.replace(/<\/?(p|div|tr|br)\s*\/?>/gi, "\n");
    // Strip remaining tags
    s = s.replace(/<[^>]*>/g, "");
    // Decode common entities
    const entities = { "&amp;": "&", "&lt;": "<", "&gt;": ">", "&nbsp;": " ", "&#39;": "'", "&quot;": '"', "&apos;": "'" };
    for (const [entity, replacement] of Object.entries(entities)) {
        s = s.split(entity).join(replacement);
    }
    // Collapse excessive newlines
    s = s.replace(/\n{3,}/g, "\n\n");
    return s.trim();
}

function stripEmailQuotes(text) {
    const lines = text.split("\n");
    const result = [];

    for (const line of lines) {
        const trimmed = line.trim();

        if (trimmed.startsWith("From:")) break;
        if (trimmed.includes(" From:")) {
            const before = trimmed.slice(0, trimmed.indexOf(" From:")).trim();
            if (before) result.push(before);
            break;
        }
        if (trimmed.startsWith("On ") && trimmed.includes(" wrote:")) break;
        if (trimmed.includes("________________________________")) break;
        if (trimmed.startsWith("-----Original Message-----")) break;
        if (trimmed.startsWith("----- Forwarded Message -----")) break;
        if (trimmed.startsWith("Sent:")) break;
        if (trimmed.startsWith("Subject:") && result.length > 0) break;
        if (trimmed === "--" || trimmed === "-- ") break;

        const lower = trimmed.toLowerCase();
        if (["regards,", "best regards,", "thanks,", "thank you,", "cheers,", "best,", "sincerely,"].includes(lower)) break;
        if (lower.startsWith("sent from my ") || lower.startsWith("get outlook for")) break;

        result.push(line);
    }

    return result.join("\n").trim();
}

// ---------------------------------------------------------------------------
// Event Wiring
// ---------------------------------------------------------------------------

document.addEventListener("DOMContentLoaded", async () => {
    initRecognition();

    // Gate TTS on user interaction (browser policy)
    function onFirstInteraction() {
        if (state.userHasInteracted) return;
        state.userHasInteracted = true;
        document.removeEventListener("click", onFirstInteraction);
        document.removeEventListener("keydown", onFirstInteraction);
        if (state.pendingSpeech) {
            speechSpeak(state.pendingSpeech);
            state.pendingSpeech = null;
        }
    }
    document.addEventListener("click", onFirstInteraction);
    document.addEventListener("keydown", onFirstInteraction);

    // Check for existing session
    const accounts = msalApp.getAllAccounts();
    if (accounts.length > 0) {
        state.account = accounts[0];
        showApp();
        await fetchSummary();
    } else {
        showSignIn();
    }

    // Sign in
    document.getElementById("sign-in-btn").addEventListener("click", signIn);

    // Toolbar
    document.getElementById("back-btn").addEventListener("click", () => {
        showSummaryView();
        renderSummary();
    });
    document.getElementById("stop-speech-btn").addEventListener("click", speechStop);
    document.getElementById("settings-btn").addEventListener("click", showSettings);
    document.getElementById("help-btn").addEventListener("click", showHelp);

    // Retry
    document.getElementById("retry-btn").addEventListener("click", fetchSummary);

    // Mic button — click to toggle
    document.getElementById("mic-btn").addEventListener("click", () => {
        // Interrupt rule: pressing the mic while TTS is speaking always
        // silences it and begins listening, regardless of prior state.
        if (state.isSpeaking) {
            startListening();
            return;
        }
        if (state.isListening) {
            stopListening();
        } else {
            startListening();
        }
    });

    // Reply
    document.getElementById("reply-cancel-btn").addEventListener("click", hideReply);
    document.getElementById("reply-send-btn").addEventListener("click", sendReply);
    document.getElementById("reply-draft").addEventListener("input", () => {
        const hasText = document.getElementById("reply-draft").value.trim().length > 0;
        document.getElementById("reply-send-btn").disabled = !hasText;
    });

    // Settings
    document.getElementById("settings-close-btn").addEventListener("click", saveSettings);
    document.getElementById("help-close-btn").addEventListener("click", hideHelp);
    document.getElementById("sign-out-btn").addEventListener("click", signOut);
});
