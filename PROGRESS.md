# HealthyMonitor — Development Progress

> Handoff document. A new agent should read CLAUDE.md first, then this file to understand where things stand.

## Current Phase: Phase 1 MVP — "Does it actually remind me?"

**Last Updated:** 2026-05-21  
**Next Milestone:** First build + run in Xcode → 7-day self-use period  
**Target Milestone Date:** 2026-05-25 (Week 2)

---

## Phase 1 Roadmap

| Week | Deliverable | Status | Notes |
|------|------------|--------|-------|
| 1–2 | `HealthyMonitorCore`: ReminderEngine, ActivityLogger, Swift Data models, unit tests | 🔲 Pending | Start here |
| 3–4 | macOS menu bar app: NSStatusItem, local notifications, action buttons, compliance ring | 🔲 Pending | |
| 5 | LLM onboarding: LLMService with Claude API + prompt caching + tool use | 🔲 Pending | |
| 6 | Integration tests + 7-day self-use period | 🔲 Pending | |

**Phase 1 Success Criteria:**
- [ ] Reminders fire reliably for 7 consecutive days
- [ ] Confirmation takes under 3 seconds
- [ ] Activity log persists across restarts
- [ ] Daily compliance rate tracked and displayed
- [ ] User (self) stands up more than before (qualitative)

---

## Completed ✓

- [2026-05-11] Project scaffolding: docs/plan.html, CLAUDE.md, PROGRESS.md, DECISIONS.md, Scripts/
- [2026-05-11] Architecture design and all key decisions documented in DECISIONS.md (incl. ADR-007: DeepSeek)
- [2026-05-11] **HealthyMonitorCore Swift Package** — all models, services, utilities, 41 unit tests (all passing)
  - Models: `HealthProfileData`, `ReminderConfigData`, `ActivityLogEntry`, `DailyStats` (plain Codable structs — no SwiftData macro)
  - Services: `ReminderEngine`, `ActivityLogger`, `LLMService` (DeepSeek/OpenAI-compatible), `NotificationService`, `HealthProfileService`
  - Storage: `JSONFileActivityLogRepository`, `JSONFileHealthProfileRepository` (file-based, no Xcode needed)
  - Test coverage: ReminderEngine (intervals, quiet hours), ActivityLogger (CRUD, stats, stale-miss), LLMService (init, encoding, tool schemas), PromptBuilder (structure, history cap, profile version)
- [2026-05-11] **HealthyMonitorMac app source files**
  - `AppDelegate`, `AppState`, `HealthyMonitorMacApp` (SwiftUI @main, menu-bar-only)
  - `StatusBarController` (NSStatusItem + NSPopover)
  - `MenuBarView` (compliance rings per type + quick actions)
  - `SettingsView` (intervals, schedule, DeepSeek API key)
  - `MacNotificationDelegate` (action button handling)
  - `KeychainHelper` (API key storage)
- [2026-05-11] **XcodeGen project** generated at `HealthyMonitorMac.xcodeproj`
- [2026-05-21] **v1 tagged** — pushed to `origin/main` and `origin/v1`. Xcode 26.3 confirmed installed locally. README rewritten in Apple product-introduction style. `.gitignore` added.

---

## In Progress

- First build + run in Xcode on the development Mac
- Setup on second Mac: clone → Xcode build → re-enter DeepSeek API key in Settings (Keychain is local, not iCloud-synced)

---

## Blocked

*(none)*

## Architecture Note

`@Model` (SwiftData macro) requires Xcode's SwiftDataMacros plugin — not available with CLI tools only. The Core package uses plain `Codable` structs + file-based JSON repositories (fully portable, no Xcode needed). When Xcode is installed, the app target can optionally add `@Model` wrappers for CloudKit sync (Phase 2).

---

## Weekly Behavioral KPI Tracker

Start tracking once Phase 1 MVP is running (self-use begins Week 6).

| Date | Daily Compliance % | Stand % | Water % | Snooze Rate | Miss Rate | Pain Score (1–10) | LLM Engagement % | Notes |
|------|--------------------|---------|---------|-------------|-----------|-------------------|------------------|-------|
| — | — | — | — | — | — | — | — | Pre-MVP baseline |

**KPI Targets (by Day 30 of use):**
- Daily Compliance: >65%
- Stand Compliance: >70%
- Notification Response Time: <60s median
- Snooze Rate: <25%
- Miss Rate: <20%
- LLM Engagement Rate: >40%
- Pain Score: Trending down over 8 weeks

---

## Weekly LLM Quality Metrics

Run `./Scripts/test-llm-integration.sh --weekly-report` each Sunday. Costs tokens — do not run per-PR.

| Date | Profile Extraction Accuracy | Coaching Relevance (1–5) | Tool Use Success Rate | Notes |
|------|----------------------------|--------------------------|----------------------|-------|
| — | — | — | — | Pre-baseline |

---

## Known Issues

*(none yet — log bugs here as discovered)*

Format: `[date] [severity: low/med/high] Description. Workaround: ...`

---

## Architecture Deviations from Plan

*(none yet — log any intentional changes from DECISIONS.md here)*

Format: `[date] ADR-XXX: What changed and why.`

---

## Phase 2 Preview (Weeks 7–12)

- iOS companion app (dashboard, history, LLM chat)
- CloudKit sync Mac ↔ iPhone
- watchOS quick-confirm + complication
- Adaptive reminder intervals (LLM tool calls)
- Sunday evening weekly coaching summary
- HealthKit write-back + EventKit meeting suppression

## Phase 3 Preview (Weeks 13–20)

- Watch accelerometer posture/movement detection
- Personalized exercise library
- 8-week pain score trend visualization
- Weekly PDF health report
