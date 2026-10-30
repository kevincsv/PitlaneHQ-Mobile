# Pitlane HQ phone apps: rules for working on this project

These rules apply to every task. How the phone-only features behave is in `docs/spec/` (index at the end); the PC and
web behaviour the phones mirror is in the Pitwall-test repository's `docs/spec/`. Read the file for the area you are
changing first, and update it in the same commit when the behaviour changes.

## Talking to the owner

- Reply to the owner in Spanish.

## Git, pushing and releases (the same rules as Pitwall-test)

- Push only when the owner says so ("súbelo", "sube todo"…). Never create pull requests unless asked. When they say
  so, push every pending change, never only part of it.
- Changes are released in big batches, never one by one. Every change is committed and pushed to the working branch
  only (never master), tested together, and goes to master in one push when the owner asks for the batch. A fix that
  cannot wait (the app broken for people) is the one exception, and only when the owner says so.
- `master` is the main branch the builds come from. Pushing (branches, tags or PRs) never builds: `android.yml` and
  `ios.yml` run only when started by hand (Actions → Run workflow, or `gh workflow run <file> --ref master`), and
  never unless the owner says "build"/"compila"; "sube"/"push" means push only. Running both with `release` ticked
  builds both apps and attaches the APK, AAB and IPA to the GitHub release (notes in
  `.github/release-notes.md`).
- The notices the apps show in their inbox come from the server (`web/dist/app-news.json` in Pitwall-test): never add
  or change one without asking the owner first, even when they say "sube todo".
- Anything sensitive that goes to GitHub is encrypted or kept in GitHub secrets (signing keys, passwords); never paste
  tokens or keys anywhere.

## Versions and release notes

- One version for Pitlane HQ everywhere: `version.txt`, the same number as PitlaneHQ.exe and the web, shown with "beta"
  until 1.0.0. Raise it rarely: a MINOR version for a big set of features; fixes and small changes go into the current
  version (or a PATCH only when a fix must reach phones that already have it), never one version per build.
- Add the version to CHANGELOG.md: its section becomes the release notes. List only what users notice; internal and
  small fixes are one "Fixes and improvements" line. Plain short sentences: no "Title: text" headings and never a ";"
  or a ":".

## Product rules

- Android and iOS are one app: the same screens, texts, layout and features on both, and the PC's (the phones'
  sub-tabs and labels are the PC's, never shortened). Every change the owner asks for in one of them (even when they
  only name Android or only iOS) is made in both in the same commit, and both builds are checked before it goes up.
- No explanatory subtitles under the screen titles, no text that explains what a chart or list shows, no text about
  encryption. The admin panel is the one exception: each section has one short line saying what it is.
- Real data by default. Invented data only behind Settings → Demo data, which only the server's admins see (off by
  default, a DEMO banner on every screen, only on the phone, never uploaded).
- Admin mode is off by default on every phone: an admin sees the app exactly as everyone does until they turn it on
  (`docs/spec/admin-and-support.md`).
- The look (the owner's choice, "Muro de boxes"): one dark theme, never switched, with the amber accent (#FFB02E):
  background #0D1116, cards #161C24 with a #263140 edge and 12 rounded corners, a floating tab bar (#1E2631, the
  chosen tab a #2E3846 pill with the amber icon; `BottomBar` on Android, `MainView.bar` on iOS) and the sub-tabs as
  blocks (the chosen one amber, `Tabs`). Every chart follows the finger and says the values under it.
- Strings: Android `ui/I18n.kt` is the source; `ios/PitlaneHQ/I18n.swift` follows it with the same keys and texts.
  English, Spanish and Portuguese (Brazil) only.
- The owner's name never appears in the code, the documents or the tests.

## Server protocol (Pitwall-test owns the server; never break it)

- Account keys: PBKDF2 600 000 + HKDF, AES-GCM with "pitlanehq-v1". Live relay: `/live`, "e:" messages with
  "pitlanehq-live-v1", gzip JSON [event, data].
- The data key also goes once to the server (POST /account/escrow with the account's email, `escrowUp`, after a sync
  that opened the account), which keeps it sealed with its own secret so Steam and Discord sign in without the
  password (the owner's choice): their answer brings `dataKey` and `email`; the password is asked (`needKey`, POST
  /account/key) only when the server keeps none or its copy does not open the account, and then this key goes up
  instead.
- The lap analysis and coach are Pitwall-test's `web/dist/pitwall-analysis.js`, run on the phone. When that file
  changes there, run `tools/sync-analysis.sh [path to Pitwall-test]` to refresh the copies in the apps
  (`docs/spec/analysis.md`).

## Where things are

- `app/src/main/java/com/pitlanehq/android/`: `ui/` (Compose screens in `PitlaneApp.kt`, `I18n.kt`), `viewmodel/`,
  `data/` (account, sync, crypto, `AnalysisJs.kt`, demo data), `model/` (`LapMath.kt` fallback, `JsAnalysis.kt`,
  live field).
- `ios/`: `project.yml` (XcodeGen), `PitlaneHQ/` (SwiftUI: `Account.swift`, `Analysis.swift`, `AnalysisJs.swift`,
  `Models.swift`, `Live*.swift`, `Views.swift`, `I18n.swift`), `Resources/`.

## Checks before committing (both, every change)

- Android: `gradle :app:assembleDebug` (CI uses Gradle 8.13).
- iOS (on a Mac): `cd ios && xcodegen generate && xcodebuild -project PitlaneHQ.xcodeproj -scheme PitlaneHQ
  -sdk iphoneos -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build`. Without a Mac, the iOS workflow
  on the working branch is the check.

## Spec index (`docs/spec/`)

| File | Read it when you touch |
| --- | --- |
| `analysis.md` | Telemetry and Analysis tabs, the shared analysis engine, lap list, maps, brake table, corner tips |
| `admin-and-support.md` | Admin mode, the admin panel, usage counting, the floating support and feedback button |
| `races-and-community.md` | DRINKS mode, races vs AI, LMU class leaderboards, wet badges, track notes, profiles |
