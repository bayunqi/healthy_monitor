# HealthyMonitor — Project Bible

> This file is the single source of truth for any AI agent or developer picking up this project.
> Read this before touching any code. Keep it up to date as decisions change.

## Project Purpose

LLM-powered personal health assistant for Apple ecosystem users (programmers / desk workers).

**Core problem:** Programmers suffer from back/waist pain due to prolonged sitting. Existing reminder apps are generic and become background noise.

**Solution:** A native Apple app that reminds users to stand, drink water, and stretch — and uses DeepSeek API to act as an adaptive personal health coach. It builds a user health profile through conversation, adjusts reminder behavior based on compliance patterns, and tracks whether the user's pain actually improves.

**North star metric:** Self-reported pain score (1–10, asked weekly by the LLM coach) trending down over 8 weeks with >60% reminder compliance.

---

## Architecture

### Platform Build Order
1. **macOS menu bar app** (Phase 1 — current) — always-on NSStatusItem, local notifications
2. **iOS companion app** (Phase 2) — health profile, history charts, LLM chat
3. **watchOS app** (Phase 2) — haptic quick-confirm + compliance complication

### Tech Stack

| Layer | Technology | Notes |
|-------|-----------|-------|
| All UI | SwiftUI 6 | native; user has Swift experience |
| Shared logic | Swift Package `HealthyMonitorCore` | shared across all targets |
| Data | Swift Data + CloudKit | zero-cost cross-device sync, no backend server |
| LLM | DeepSeek API (`deepseek-chat`) | OpenAI-compatible; automatic disk cache; tool use; China-accessible, low cost |
| Notifications | `UNUserNotificationCenter` (local only) | no APNS for MVP |
| Watch sync | `WatchConnectivity` | iPhone ↔ Watch message passing |
| Future | HealthKit, EventKit | Phase 2 |

### Critical Architecture Decisions

See `DECISIONS.md` for full ADRs. Summary:

- **No custom backend server** — DeepSeek API called directly from macOS/iOS, key in Keychain. Revisit at Phase 2 if distributing to other users.
- **macOS app is authoritative scheduler** — it's always running; schedules all local notifications.
- **Local notifications only** — eliminates APNS server infrastructure entirely for MVP.
- **CloudKit via Swift Data** — transparent cross-device sync, end-to-end encrypted, zero cost.
- **DeepSeek automatic disk cache** — frequently-accessed prefixes (system prompt + health profile) are cached automatically; no explicit `cache_control` markers needed.
- **Tool use** for structured LLM outputs: `update_health_profile`, `adjust_reminder_schedule`, `log_observation`.

---

## Repository Structure

```
healthy_monitor/
├── HealthyMonitorCore/                ← Swift Package (shared logic)
│   ├── Package.swift
│   └── Sources/HealthyMonitorCore/
│       ├── Models/
│       │   ├── HealthProfile.swift
│       │   ├── ReminderConfig.swift
│       │   ├── ActivityLog.swift
│       │   └── DailyStats.swift
│       ├── Services/
│       │   ├── ReminderEngine.swift       ← heartbeat scheduler (core logic)
│       │   ├── ActivityLogger.swift       ← log writes + daily stats queries
│       │   ├── LLMService.swift           ← Claude API client + prompt caching
│       │   ├── HealthProfileService.swift
│       │   └── NotificationService.swift
│       ├── Persistence/
│       │   ├── SwiftDataContainer.swift   ← ModelContainer + CloudKit config
│       │   └── CloudKitSync.swift
│       └── Utilities/
│           ├── DateHelpers.swift
│           └── PromptBuilder.swift        ← assembles LLM system prompt from profile
│   └── Tests/HealthyMonitorCoreTests/    ← unit tests
│
├── HealthyMonitorMac/                 ← macOS target (Phase 1 active)
│   └── Sources/
│       ├── App/HealthyMonitorMacApp.swift ← @main + NSStatusBar bootstrapper
│       ├── MenuBar/
│       │   ├── StatusBarController.swift
│       │   ├── MenuBarView.swift
│       │   └── QuickActionsView.swift
│       ├── Windows/SettingsView.swift
│       └── Notifications/MacNotificationDelegate.swift
│
├── HealthyMonitor/                    ← iOS target (Phase 2)
├── HealthyMonitorWatch/               ← watchOS target (Phase 2)
│
├── Scripts/
│   ├── test-notifications.sh          ← fire test notification, verify log entry
│   ├── test-llm-integration.sh        ← LLM quality tests (run weekly, costs tokens)
│   ├── build-all-targets.sh           ← build Mac + iOS + Watch, report errors
│   └── seed-test-data.sh              ← populate 7 days synthetic ActivityLog data
│
├── docs/plan.html                     ← visual product/architecture plan (open in browser)
├── CLAUDE.md                          ← this file
├── PROGRESS.md                        ← development progress + weekly KPI tracker
├── DECISIONS.md                       ← architecture decision records
└── README.md
```

---

## Environment Setup

### Requirements
- **Xcode 16+**
- **macOS 15+ (Sequoia)**
- **iOS 18+ SDK** (for iOS/Watch targets)
- **Apple Developer Account** (for CloudKit entitlements and device testing)
- **DeepSeek API key** for LLM features (get at platform.deepseek.com)

### Environment Variables
```bash
DEEPSEEK_API_KEY=sk-...    # DeepSeek API key; stored in Keychain in production
```

For development/scripts, export in your shell or `.env.local` (never commit).

### CloudKit Setup
- Container ID: `iCloud.com.[yourname].healthymonitor`
- Enable CloudKit in Xcode → Signing & Capabilities → iCloud → CloudKit
- Schema auto-created from Swift Data models on first run (development environment)

### Build Commands
```bash
# Build macOS target
xcodebuild -scheme HealthyMonitorMac -destination "platform=macOS"

# Build iOS target
xcodebuild -scheme HealthyMonitor -destination "platform=iOS Simulator,name=iPhone 16"

# Run unit tests
xcodebuild test -scheme HealthyMonitorCoreTests

# Build all targets
./Scripts/build-all-targets.sh

# Run LLM quality tests (costs tokens — run weekly)
./Scripts/test-llm-integration.sh --weekly-report

# Seed 7 days of synthetic test data
./Scripts/seed-test-data.sh

# Fire a test notification and verify the log cycle
./Scripts/test-notifications.sh
```

---

## Key Constraints (Never Violate)

| Constraint | Value | Reason |
|-----------|-------|--------|
| Minimum reminder interval | 15 minutes | Shorter intervals become overwhelming and ignored |
| Maximum reminder interval | 120 minutes | Doctor's recommendation; never longer than 2 hours |
| LLM conversation history cap | 50 messages | Prevent context overflow; older messages summarized |
| Quiet hours | Always enforced | User-configured; violating breaks trust |
| DND respect | Always check `UNNotificationSettings` | Never fire during Do Not Disturb |
| API key storage | iOS Keychain only | Never log, never transmit, never hardcode |
| LLM tone | No guilt language | User confirmed this preference; coach is curious, not scolding |

---

## Data Models (Quick Reference)

```swift
// The three core Swift Data models:

HealthProfile       // pain points, schedule, goals, LLM conversation history
ReminderConfig      // type, intervalMinutes, isEnabled, lastFiredAt (local only)
ActivityLog         // reminderType, scheduledAt, response (.completed/.skipped/.snoozed/.missed)

// Computed (not stored):
DailyStats          // derived from ActivityLog queries; complianceRate = completed/total
```

---

## LLM Integration (PromptBuilder Pattern)

Provider: **DeepSeek API** — OpenAI-compatible format. Base URL: `https://api.deepseek.com/v1`. Model: `deepseek-chat` (DeepSeek-V3). No official Swift SDK; use `LLMService` (URLSession-based, in `Services/LLMService.swift`).

The `PromptBuilder` utility in `Utilities/PromptBuilder.swift` assembles the full prompt from:
1. Static system prompt: coaching persona + instructions (cached automatically by DeepSeek disk cache)
2. Current `HealthProfile` snapshot (cached as part of the long system prefix)
3. Today's `DailyStats` summary (dynamic)
4. Last 10 conversation messages (dynamic)

Always use `PromptBuilder` — never construct prompts inline.

DeepSeek caches long common prefixes automatically (disk cache). No explicit `cache_control` markers needed. Cache hits are reflected in `prompt_cache_hit_tokens` in the usage response — log these in development to verify caching is working.

---

## Testing Requirements

- **All PRs:** unit tests + integration tests must pass
- **Every reminder-logic change:** run `./Scripts/test-notifications.sh`
- **LLM quality tests:** weekly only (not per-PR; they cost real tokens)
- **New LLM tool:** add a golden-set test to `LLMQualityTests`
- **CloudKit changes:** run `CloudKitSyncTests` on device (not simulator)

### Core E2E Test (always must pass)
```
Schedule reminder → wait for delivery → simulate "Done" tap
→ assert ActivityLog entry with .completed → assert next reminder scheduled
→ assert DailyStats compliance rate updated
```

---

## Data Privacy

- Health profile stored locally on-device + user's own iCloud (CloudKit)
- No analytics or telemetry without explicit user consent
- Anthropic API receives only conversation text — no device identifiers
- Conversation history stored only on-device + user's iCloud; never on Anthropic's storage
- API key never logged or transmitted outside HTTPS to `api.anthropic.com`

---

## Handoff Checklist (for new sessions/agents)

1. Read `CLAUDE.md` (this file) — understand the full architecture
2. Read `PROGRESS.md` — understand current phase, what's done, what's next, what's blocked
3. Read `DECISIONS.md` — understand why key choices were made (prevents re-litigating)
4. Run `./Scripts/build-all-targets.sh` — verify environment is working
5. Run `xcodebuild test -scheme HealthyMonitorCoreTests` — verify tests pass
6. Check `PROGRESS.md → Known Issues` section before starting new work
