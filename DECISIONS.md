# HealthyMonitor — Architecture Decision Records

> Each ADR documents a key architecture choice: the context that led to it, the decision made, and the consequences. Before proposing to change any of these, read the ADR — the trade-offs were intentional.

---

## ADR-001: Native SwiftUI over Flutter or React Native

**Date:** 2026-05-11  
**Status:** Accepted  

**Context:**  
The app requires deep integration with Apple-specific system APIs:
- `NSStatusBar` / `NSStatusItem` for macOS menu bar (no clean Flutter equivalent)
- `WatchConnectivity` for iPhone ↔ Apple Watch communication (native Swift only)
- `HealthKit` for reading/writing health data (native only)
- `EventKit` for calendar awareness (native only)
- `WKUserNotificationHostingController` for watchOS notification UI

**Decision:**  
Use native SwiftUI 6 across all targets (macOS, iOS, watchOS). Shared business logic lives in a `HealthyMonitorCore` Swift Package consumed by all three app targets.

**Consequences:**  
- (+) Full access to all Apple system APIs, no bridging complexity
- (+) Best performance and native feel on all platforms
- (+) watchOS support is natural (WKInterfaceController / SwiftUI)
- (+) User already has Swift experience — no ramp-up cost
- (-) No Android path (acceptable: product is Apple-ecosystem-only by design)
- (-) Three Xcode targets to maintain vs one Flutter project

---

## ADR-002: Direct Claude API Calls from iOS (No Custom Backend for MVP)

**Date:** 2026-05-11  
**Status:** Accepted for MVP; revisit before App Store distribution  

**Context:**  
Building a backend server (e.g., FastAPI, Node.js) would add infrastructure setup, hosting costs, authentication, and deployment complexity before a single health reminder fires. The target user is also the only user for MVP.

**Decision:**  
Call the Claude API (`api.anthropic.com`) directly from the iOS app. Store the API key in iOS Keychain — the most secure on-device storage available. Never hardcode, log, or transmit the key outside of HTTPS to Anthropic.

**Consequences:**  
- (+) Zero infrastructure for MVP — no server to build, deploy, or maintain
- (+) App works fully offline except for LLM coaching sessions
- (+) Fastest path to a working product
- (-) API key exposure risk if the device is compromised (mitigated by Keychain encryption)
- (-) Cannot distribute to other users without exposing a shared key or building a backend proxy
- (-) No server-side analytics or monitoring
- **Trigger to revisit:** Any intent to submit to App Store or share with other users → add a thin Cloudflare Worker or AWS Lambda as a proxy.

---

## ADR-003: CloudKit via Swift Data for Cross-Device Sync

**Date:** 2026-05-11  
**Status:** Accepted  

**Context:**  
The app needs to sync `HealthProfile` and `ActivityLog` between the user's Mac and iPhone (and Watch). Options considered:
1. **Custom backend** (PostgreSQL + REST API) — high complexity, hosting cost
2. **Firebase** — cross-platform but introduces a Google dependency, no native Swift Data integration
3. **CloudKit via Swift Data** — Apple-native, zero infrastructure, built-in E2E encryption

**Decision:**  
Use Swift Data's built-in CloudKit integration. Models that need sync declare `@Model` with CloudKit configuration. `ReminderConfig` is local-only (each device schedules its own notifications independently).

**Consequences:**  
- (+) Zero server cost — stored in user's own iCloud
- (+) End-to-end encrypted by default
- (+) Conflict resolution handled by CloudKit (last-write-wins with field-level merging)
- (+) No migration scripts needed for schema changes in development (auto-migrated)
- (-) Apple ecosystem only — no web dashboard, no Android
- (-) CloudKit quota limits (generous for personal use; irrelevant at MVP scale)
- (-) Requires Apple Developer account for entitlements

---

## ADR-004: Local Notifications Only (No APNS) for MVP

**Date:** 2026-05-11  
**Status:** Accepted for MVP; revisit for multi-user distribution  

**Context:**  
Apple Push Notification Service (APNS) requires a backend server to send push notifications. Local notifications are scheduled directly on-device via `UNUserNotificationCenter`.

**Decision:**  
Use local notifications on each device. The macOS menu bar app is the authoritative scheduler — it is always running as an `NSStatusItem` process, so it can reliably schedule and reschedule reminders. iOS schedules its own independent set of local notifications.

**Consequences:**  
- (+) No server infrastructure required
- (+) Works completely offline
- (+) Zero cost for notification delivery
- (+) Simpler code path — no APNS certificates, no device token management
- (-) If the Mac app is quit, Mac notifications stop (acceptable — user controls when to run the app)
- (-) Cross-device notification deduplication is approximate (each device fires independently)
- (-) No ability to push notifications from a server (e.g., "your doctor has a message for you")
- **Trigger to revisit:** Multi-user product, server-initiated coaching messages, or APNS-based features.

---

## ADR-005: Prompt Caching on System Prompt + Health Profile

**Date:** 2026-05-11  
**Status:** Accepted  

**Context:**  
Claude API costs scale with token usage. The system prompt (coaching persona + instructions) and the user's health profile (pain points, schedule, goals) are static or nearly static — changing at most weekly. Sending them in full on every API call wastes tokens.

**Decision:**  
Structure every API request with two cache breakpoints:
1. **Cache block 1:** System prompt (coaching persona, instructions, tone guidelines) — rarely changes
2. **Cache block 2:** Health profile snapshot — updated at most weekly
3. **Dynamic:** Last 10 conversation messages
4. **Dynamic:** Current user message

**Consequences:**  
- (+) ~80% cache hit rate for daily coaching conversations → ~80% cost reduction on cached tokens
- (+) Faster responses (cache hits return faster than full processing)
- (-) Health profile must be serialized to a string for inclusion in the prompt (handled by `PromptBuilder`)
- (-) Cache block 2 becomes stale if profile changes and cache is not invalidated — `PromptBuilder` must include a profile version hash to force invalidation

---

## ADR-006: macOS Menu Bar as Phase 1 Primary Platform

**Date:** 2026-05-11  
**Status:** Accepted  

**Context:**  
The target user (a programmer) spends their entire workday at a Mac. Platform options for Phase 1:
- **macOS menu bar:** always visible, zero friction, most relevant during work hours
- **iOS first:** portable but requires phone to be nearby; no persistent background process
- **All platforms simultaneously:** fastest to full feature coverage but longest time to first working product

**Decision:**  
Build macOS menu bar app first. It delivers 80% of the product value (reminders during work hours) in ~4 weeks. iOS and watchOS follow in Phase 2 as the compliance confirmation surfaces improve.

**Consequences:**  
- (+) Fastest path to a working, daily-use product
- (+) The menu bar app can run 24/7 without user action — it is the authoritative reminder scheduler
- (+) Testing and iteration happen against real usage immediately
- (-) No mobile reminders until Phase 2 (acceptable for a desk-worker use case)
- (-) No Watch confirmation until Phase 2 (use Mac notification action buttons in the interim)

---

## ADR-007: DeepSeek as LLM Provider (Replacing Claude API)

**Date:** 2026-05-11  
**Status:** Accepted  

**Context:**  
Claude API (Anthropic) has two significant barriers for this project's target audience:
1. **Cost:** Significantly higher per-token pricing than alternatives
2. **Accessibility:** Difficult to obtain API access for users in China; payment methods limited

DeepSeek (deepseek.com) is a Chinese AI company offering:
- OpenAI-compatible REST API (same request/response format, same tool-calling schema)
- Much lower cost (~90% cheaper than Claude for comparable capability)
- Easy API access and payment for China-based users
- `deepseek-chat` (DeepSeek-V3) is competitive with Claude Sonnet for conversational tasks
- Built-in disk cache that automatically caches long common prefixes — no explicit cache_control markers needed

**Decision:**  
Use DeepSeek API (`deepseek-chat` model) as the LLM provider. Implement `LLMService` as a URLSession-based OpenAI-compatible HTTP client (no official Swift SDK needed). Store `DEEPSEEK_API_KEY` in iOS/macOS Keychain.

**Consequences:**  
- (+) ~90% cost reduction vs Claude API
- (+) Accessible and easy to pay for in China
- (+) OpenAI-compatible format means tool calling, streaming, and response parsing are standard
- (+) No SDK dependency — plain URLSession reduces package complexity
- (+) Automatic prompt caching (disk cache) without any code changes
- (-) No official Swift SDK — must maintain URLSession client code manually
- (-) DeepSeek's API availability outside China depends on their infrastructure (CDN/routing); latency may be higher for non-China users
- (-) Smaller community/ecosystem vs OpenAI or Anthropic SDKs
- **Trigger to revisit:** If DeepSeek API has reliability issues or the project targets non-China users who prefer Claude/OpenAI
