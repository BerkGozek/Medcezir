# Development progress

Last updated: 2026-11-18.

2026-11-18: **renamed GitPad → Medcezir and added iPhone support.** Bundle ID (`com.berkgozek.GitPad`) and Keychain service kept, so it updates the existing iPad install in place with its repos and tokens.

Current phase: **3 (Remote Sync) complete and verified on the iPad**: private clone, external edit → Changes, commit, push, Files integration.
Next: Phase 4. GitHub sign-in via device flow (needs a Client ID from Berk), more UI tests, polish. README is done. TestFlight is blocked on a paid/education team.

## Verification summary

| Area | Command | Result |
|---|---|---|
| Git engine + storage + accounts (macOS) | `swift test --package-path Packages/MedcezirKit` | ✅ 35/35: clone, status, stage/unstage (incl. deletions), commit, diff, log, branches (create/switch/delete, safe checkout), fetch, fast-forward pull, pull refusing to overwrite local edits, non-fast-forward push rejected (not forced) then pull+push recovery, conflict → resolve → merge commit, abort merge, invalid repo, missing remote, outgoing commits, redaction, repository store (staging, cancel/fail leave nothing, persistence, name validation, safe delete), account store (token only in secret store, persistence, removal, host matching, refuses to guess between several accounts, lazy token read) |
| Live HTTPS against GitHub | `MEDCEZIR_LIVE_TESTS=1 MEDCEZIR_TEST_REPO=… MEDCEZIR_TEST_TOKEN=… swift test --filter LiveGitHubTests` | ✅ 1/1 against private sandbox `BerkGozek/gitpad-test-sandbox`: anonymous clone → auth error; wrong token → auth error with the token not in the message; private clone, commit, push, pull in a second clone; token not in `.git/config` |
| App build (simulator) | `xcodebuild -scheme Medcezir -destination 'generic/platform=iOS Simulator' build` | ✅ no errors, no warnings (Swift 6) |
| App launch (simulator) | `simctl install` + `launch` + screenshot | ✅ launches to the empty state (Phase 1 build) |
| App UI tests (simulator, iPad Pro 11" M5, iOS 26.5) | `xcodebuild -scheme Medcezir -destination 'id=<sim>' test` | ✅ 1/1: Settings → Add Account → type token → change service → form stays open → Cancel back to Settings |
| Package tests after rename (2026-11-18) | `swift test` in `Packages/MedcezirKit` | ✅ 38/38 |
| UI tests on iPhone (2026-11-18, iPhone 17 Pro sim) | `xcodebuild -scheme Medcezir -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test` (+ `TEST_RUNNER_SCREENSHOT_DIR`) | ✅ 2/2: add-account flow; clone → files → open subfolder → back → history → branches |
| UI tests on iPad (2026-11-18, iPad Pro 11" M5 sim) | same, iPad destination | ✅ 2/2 |
| Device build (2026-11-18) | `xcodebuild -destination generic/platform=iOS -allowProvisioningUpdates build` | ✅ signed; `UIDeviceFamily` [1,2], display name Medcezir, bundle ID com.berkgozek.GitPad |

## Verified on Berk's iPad Air (5th gen, iPadOS 26)
- Phase 1 build installed from Xcode; cloned `BerkGozek/Testing-Repository` over HTTPS ✅
- Repositories did **not** appear in Files at first ❌ → fixed (see below); **confirmed on the iPad: repositories now show in Files → On My iPad → Medcezir → Repositories** ✅
- 2026-11-11: added a GitHub fine-grained token, committed and **pushed to `Testing-Repository` from the iPad** ✅ (Phase 3 success criterion). First attempt got HTTP 403 because the new token had GitHub's read-only defaults; fixed on GitHub (Contents: Read and write), and the app now explains 403s.

## iPhone support (2026-11-18): bugs the tests caught and fixed
- Repository screen had **no nav bar on iPhone** (no back, no Fetch/Pull/Push): the file browser's nested `NavigationStack` hid the collapsed split view's bar. Compact width now pushes folders onto the outer stack.
- Tapping a folder on iPhone did nothing (value-based link had no destination in the collapsed stack) → view-destination links.
- Back from a subfolder popped to the repository list → compact detail column is wrapped in its own `NavigationStack`.
- Two `…` menus on the Branches tab → Refresh/Show in Files use the system `.secondaryAction` overflow on iPhone.
- Clone sheet: keyboard covered the progress/error rows on iPhone → keyboard is dismissed when a clone starts.

## Needs a real iPhone
- Install and a full clone/commit/push on a physical iPhone. Files → On My iPhone → Medcezir exposure.

## App Store / TestFlight readiness
- App icon: 1024×1024, no alpha ✅. 2026-11-18: new beach/starfish design, rendered from `design/app-icon-beach.svg` by `scripts/make-icon.swift`; dark-mode variant (moonlit) from `design/app-icon-beach-night.svg` → `icon-1024-dark.png`, verified on the iPhone simulator home screen
- `PrivacyInfo.xcprivacy`: no tracking/collection; UserDefaults CA92.1, FileTimestamp C617.1, SystemBootTime 35F9.1 ✅ (in the built app)
- `ITSAppUsesNonExemptEncryption = NO` (standard HTTPS only) ✅
- Archive + upload: ⏸ not possible yet. The project's team is `7WRYR7WZJR` "Berk Gozek (Personal Team)", a **free** team, which can't use TestFlight. Needs a paid Apple Developer Program membership.

## Docs and licensing
- `README.md` with screenshots captured by `ScreenshotUITests` (opt-in, `TEST_RUNNER_SCREENSHOT_DIR=…`).
- `THIRD_PARTY_NOTICES.md` + in-app Settings → Acknowledgements (full libgit2 license text bundled).
  libgit2 is GPL v2 + linking exception; bundled xdiff is **LGPL 2.1+** (statically linked; satisfied by the public source).

## Bugs caught and fixed
- Typing a clone URL froze the folder name at its first character (a repo got cloned as "h"). The name field's `onChange` counted the app's own auto-fill as a manual edit; caught by the screenshot UI test, which now asserts the name. Pasting a URL (as on the iPad) didn't trigger it.
- One simulator clone run failed without a visible error and didn't reproduce on the next run; cause not found (possibly network). Watch for it.
- Add Account closed itself (and Settings) right after opening, found by Berk on the iPad. The sheet was attached to a Form section inside the Settings sheet; SwiftUI tears such sections down on re-render. Now presented from the Settings screen; reproduced and verified with a UI test.
- `INFOPLIST_KEY_UIFileSharingEnabled` was silently dropped from the generated Info.plist, so the app's folder never showed in Files → On My iPad. Both Files keys now live in `Medcezir/Info.plist`; verified in the built app's Info.plist.
- Xcode showed "Missing package product 'MedcezirCore'" after the package had been opened in a separate window; fixed by restarting Xcode (stale package graph, project was fine).

## Needs a real iPad
Nothing open. Tested on Berk's iPad (2026-11-11, reported by Berk):
- Editing a repo file in another app, returning to Medcezir, and seeing it in Changes ✅
- Opening a whole repository folder in a third-party editor via Files ✅
