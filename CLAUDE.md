# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Stash is a macOS menu bar app for fast capture of tasks/questions/goals/reminders. It is pure Swift with **zero third-party dependencies**, built by shell script (no Xcode project, no SwiftPM manifest), and **all runtime logic lives in one file**: `Stash.swift` (~8.8k lines). Storage is a plain text file (`my_tasks.txt`); reminders are mirrored into Apple Reminders via EventKit.

## Commands

```bash
./build.sh                                      # full build: icons + .lproj + Info.plist + codesign -> Stash.app
swiftc Stash.swift -framework Cocoa -o Stash    # quick compile check, no bundle/icons/signing (~2 min; autolinking covers the other frameworks)
open Stash.app                                  # run
cp -r Stash.app /Applications/                  # install
CODE_SIGN_IDENTITY="Developer ID Application: ..." ./build.sh   # signed build (default is ad-hoc "-")
```

A full compile takes ~2 minutes on the single 8.8k-line file, so batch edits before checking.

**There is no test suite and no linter** — no `swift test` target, no SwiftLint/SwiftFormat config. There is therefore no "run a single test" command. Verification is: compile cleanly, then `./build.sh && open Stash.app` and exercise the flow by hand. Do not invent a test command; if a change needs proof, build and drive the app.

## Architecture

`Stash.swift` is organized by `// MARK:` blocks. Approximate map (line numbers drift — grep the MARK names):

| Region | Contents |
| --- | --- |
| Configuration (top) | every `UserDefaults` key, Keychain account name, backend URL, default model, hotkey code, `kIcons` task-type table, embedded Ed25519 public key |
| `AI + Secrets` | `KeychainStore`, `LicenseManager`, `CreditsManager`, `CloudSyncManager`, `AppleRemindersHelper`, `ReminderAIParser`, `ReminderTrackingRegistry` |
| `Review Models` | `StashEntry` / `DayBlock` / `ReviewPeriod`, dashboard data model + `DashboardDataBuilder` + `DashboardHTMLRenderer` |
| `StashFileParser` | the only code that reads/writes the task file |
| `RewindScheduler` | daily-review notification, snooze counter, reviewed-state |
| Window controllers | `ReviewWindowController`, `SearchWindowController`, `DashboardWindowController`, `OnboardingWindowController`, `PreferencesWindowController`, `HelpWindowController` |
| `AppDelegate` | status item, popover, global hotkey, context menu, notification delegate, cloud-sync automation, `CompletedRemindersSyncController` |
| `TaskViewController` | the capture popover and the save flow |
| Entry point (bottom) | manual `NSApplication` bootstrap — `LSUIElement`, no main.swift, no storyboard |

Almost everything is `private` + file-scoped, and managers are `enum` namespaces with `static` methods. That is deliberate: it is how a single-file app keeps boundaries. Keep new code in the matching MARK section rather than adding files, unless there is a strong reason to split.

### Capture flow (the core path)

`TaskViewController.saveTask()`:
- Non-reminder icons (📥 ❓ 🎯) → append to the task file, done.
- Reminder (🔔) → `ReminderAIParser.parse()` for title+due date, **then** write the local line, **then** create the `EKReminder`. Local file first, EventKit second; status label reports which step failed.
- Every write goes through `writeTask()`, which calls `StashFileParser.appendTaskLine` and then `CloudSyncManager.scheduleDebouncedLocalPushSync()` (30s debounce).

### AI parsing routing

`ReminderAIParser.parse()` branches on `CreditsManager.shouldUseStashCoins()`:
- STASH Coins mode → licensing-service proxy (`CreditsManager.parseReminder`), balance is a signed snapshot in Keychain.
- Personal-key mode → direct call to Google / OpenAI / Anthropic, key resolved **Keychain first, then env var**.

Both paths record structured failures into `AIDiagnosticsStore` / `ReminderAIDebugLog`, surfaced in Preferences > AI. When adding a provider, update `AIProvider` (model default + defaults key + endpoint) and the Preferences pane together.

### Paid layer

Free/Premium gating is `SubscriptionPlan` (`allowsDashboard`, `allowsTaskSearch`, `allowsStashCoins`, `allowsCloudSync`). The plan comes from `LicenseManager.currentPlan()`, which reads an **Ed25519-signed entitlement verified locally** against `kEntitlementPublicKeyPEM` — never trust a raw `UserDefaults` plan value as the source of truth. The backend is a separate private Cloudflare Worker repo (`stash-licensing`); this repo only consumes `POST /licenses/activate`, `POST /licenses/refresh`, credits and top-up endpoints at `kLicenseServicePrimaryBaseURL` with `kLicenseServiceFallbackBaseURL`. That backend's contracts, schema, and operational parameters are documented in the private repo — deliberately not here. Do not reintroduce them into this public repository.

### Cloud sync

Google Drive only, via Service Account JSON stored in Keychain. `CloudSyncManager.triggerAutomaticSync` is called on launch, app-active, wake-from-sleep, and a periodic timer, throttled by `kCloudSyncAutoCheckInterval` and gated by a Drive `changes.list` delta check before doing a full sync. Imported reminders are deduped by stable fingerprint written into the reminder notes as `stash-sync-id:<fingerprint>` (`ReminderTrackingRegistry`).

### Dashboard

`DashboardWindowController` renders a `WKWebView` from an HTML string produced in Swift by `DashboardHTMLRenderer.render(summary:)`. All user text must go through `htmlEscaped()`. Root-level `stash-dashboard.html` is a standalone design mock (loads Chart.js from a CDN) — it is **not** shipped in the bundle and is not the code path the app uses.

## Contracts you must not break

**Task file format** — `StashFileParser` owns it; day-grouped, emoji-prefixed, four-space indent, and hand-editable by users:

```
📅 20/02/2026 🌅                                  <- day header; trailing 🌅 = "reviewed"
    🔔 Take medicine ⏰ 20/02/2026 16:30 ✅ 20/02/2026
    📥 Buy coffee [carryover-to:21/02/2026]
    📥 Send email [carried-from:19/02/2026]
```

Order of suffixes is fixed: `[carried-from:…]` / `[carryover-to:…]` → `⏰ dd/MM/yyyy HH:mm` → `✅ dd/MM/yyyy`. All these formats use `en_US_POSIX` with `dd/MM/yyyy`; do not localize them. Route every read/write through `StashFileParser` rather than touching the file directly.

**Localization** — all user-facing strings use `L("key")` / `LF("key", args…)`, and every new key must be added to **both** `en-US.lproj/Localizable.strings` and `pt-BR.lproj/Localizable.strings` (they are kept at equal key counts). Language is runtime-switchable (`stash.language`: system / en-US / pt-BR) via `Localizer` + the `stashLanguageDidChange` notification — window controllers rebuild their labels on that notification, so new UI needs a `refreshLocalizedUI()`-style path too. `AppLanguage.activeBCP47()` is also passed to the AI as parsing context.

**Task types** — centralized in `kIcons` (symbol + tooltip/placeholder/description keys). Adding or reordering a type means updating `kIcons`, the `Cmd+1…4` segment shortcuts, the tooltips, and the reminder special-case check (`selectedIcon != "🔔"`) together.

**Persistence namespaces** — `UserDefaults` keys are all `stash.*` and declared as `k…DefaultsKey` constants at the top of the file. Secrets live in Keychain service `com.robsonferreira.stash` (accounts: `google_api_key`, `openai_api_key`, `anthropic_api_key`, `stash_license_key`, `stash_license_entitlement`, `stash_license_device_id`, `stash_credits_balance`, `stash_sync_google_credentials_json`), with env fallbacks `GOOGLE_API_KEY` / `OPENAI_API_KEY` / `ANTHROPIC_API_KEY`. No key or Service Account JSON ever lands in a tracked file.

## Releasing

Version lives in three places and they must move together: `build.sh` (`CFBundleShortVersionString` **and** `CFBundleVersion`), the fallback literal in `appShortVersion()` in `Stash.swift`, and `README.md`. Add the entry to `CHANGELOG.md` (Keep a Changelog + SemVer; recent entries are written in Portuguese with `Adicionado`/`Alterado`/`Corrigido`).

Git flow: `main` + `develop`, work on `feature/*`, ship through `release/*` merges. Commit subjects are Conventional Commits (`feat:`, `fix:`, `chore(release):`).

## Gotchas

- `kDefaultTaskDirectory` is a hardcoded absolute path to the author's `~/Documents`. It only applies before onboarding sets `stash.taskFilePath`, but treat it as a known wart, not a pattern to copy.
- `.github/`, `.agents/`, and `forge/` are in `.gitignore` — `.github/copilot-instructions.md` (an older, still largely accurate summary of these same conventions) and `forge/knowledge/releases/*.md` are local-only.
- `docs/` is the published GitHub Pages site (`CNAME` → `stash.simplificandoproduto.com.br`), including the `/pro/` pricing page and `/billing/{success,cancel}/` Stripe redirect targets. Editing it changes the public site, not the app.
- The global hotkey needs Accessibility permission; without it `Cmd+Shift+Space` silently does nothing, so hotkey changes can't be verified from a build alone.
- Build artifacts (`Stash.app/`, ad-hoc verification binaries) have been committed to this repo by accident before. `.gitignore` covers them now — check `git status` before committing after a build.
