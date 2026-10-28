# Pitlane HQ phone apps: rules for working on this project

- Reply to the owner in Spanish.
- Android and iOS are one app: the same screens, texts, layout and features on both. Every change the owner asks
  for in one of them (even when they only name Android or only iOS) is made in both in the same commit, and both
  builds are checked before it goes up. No explanatory subtitles under the screen titles.
- Push only when the owner says so ("súbelo", "sube todo"…). Never create pull requests unless asked.
- Anything sensitive that goes to GitHub is encrypted or kept in GitHub secrets (signing keys,
  passwords); never paste tokens or keys anywhere.
- Real data by default. Invented data only behind Settings → Demo data, which only the server's
  admins see (off by default, a DEMO banner on every screen, only on the phone, never uploaded).
- DRINKS mode (formerly Friday night mode, admins only): friends drive on the owner's PC and their laps
  go to the community under their name. Switched on the PC or from the phone (Settings → DRINKS
  mode) through the encrypted live link ("drinks" event); the PC checks the account is an admin.
- A race against iRacing's AI (`ai` on the race) has no iRating: no change in the race rows or the summary, no
  iRating in its results, nothing in the licence summary. A session the server has no `ai` flag for is against the AI when it
  is an iRacing session without a subsession (id "t-…" after the account's "acct_…:" prefix) that is not a test
  (`offlineAI` when the sessions are parsed),
  so My sessions, Laps and the Coach show "vs AI" on it like the PC and the web.
- The admin panel's account card has "Link a DRINKS driver" (the driver's name; `adminAccount(id, "link-guest", name)`)
  and "Unlink DRINKS driver …" for each one joined (`guestLinked` in the accounts list, "gid|name,…").
  Its own driver is linked per game: "Unlink iRacing driver" and "Unlink Le Mans Ultimate driver", one for each game
  linked (`driverGames` in the accounts list, "iracing,lmu"; `adminAccount(id, "unlink-driver", game)`).
- This repository is only the Android app (`app/`) and the iOS app (`ios/`). The PC app and the
  web/server (Cloudflare) live in the Pitwall-test repository; the apps talk to that server and
  must keep its protocol: account keys (PBKDF2 600 000 + HKDF, AES-GCM with "pitlanehq-v1"),
  live relay (`/live`, "e:" messages with "pitlanehq-live-v1", gzip JSON [event, data]).
- Android and iOS stay the same app: same screens, same features, same wording, and the PC's: Telemetry has the PC's
  Telemetry, Standings and Tyres (`Live` in PitlaneApp.kt, `LiveTabs.swift`, fed by `LiveField`); Analysis has Laps,
  Coach, My sessions and My races (`Analysis` in PitlaneApp.kt, `AnalysisView` and `Analysis.swift`), lap B is your own
  best, the model's next level or its record (`modelRefs`, asked for lap A's tyre compound, `Trace.cmp` from its
  "cmp:<n>" flag: the server gives that compound's references when it has them apart), and each driver is measured
  against their own laps.
  The corner tips (`corners` in LapMath.kt and Models.swift, texts `tip_*`) follow the measured facts like the PC's
  and the web's: braking later than the reference and arriving slower at the apex is one mistake whatever phase pays
  for it (`tip_brake_late_apex`); with the same braking point the tip is about the brake (harder at first, trail,
  `tip_brake_same`), never "brake later"; an apex reached as fast as the reference's says the time goes before it
  (`tip_entry_before`) or in a longer slow part (`tip_apex_longer`); a throttle picked up earlier but a slower apex
  says to carry the speed (`tip_exit_speed`); only a generic tip (`GENERIC_TIPS`) gives way to the gear, the lifts
  and the line. The track map's road is the reference's path when both laps have one (`c.bx`/`c.by`: B dashed along
  the middle, A beside it by `c.lat`), else the lap's own, else the track's layout drawn by the community
  (`trackLayout`, `layout` in `LapAnalysis`), like the web: a lap without a path still has its map.
- Track notes (`notes.json` in the account, the same the PC and the web keep): the track page shows the general note
  and the corner notes and writes the general one (`TrackNotesPanel`, `setTrackNote`: the bundle is read, only
  notes.json changes, sealed with the account's key, like driver notes); Account → Track notes lists them all. A
  driver's profile shows their leaderboards, records (P1) and top 3 places, and a recent record opens its driver's
  profile when they have one (`prof`).
- The look (the owner's choice, "Muro de boxes"): one dark theme, never switched, with the amber accent (#FFB02E):
  background #0D1116, cards #161C24 with a #263140 edge and 12 rounded corners, a floating tab bar (#1E2631, the
  chosen tab a #2E3846 pill with the amber icon; `BottomBar` on Android, `MainView.bar` on iOS) and the sub-tabs as
  blocks (the chosen one amber, `Tabs`). Every chart follows the finger and says the values under it.
- One version for Pitlane HQ everywhere: `version.txt` (the same number as PitlaneHQ.exe and the
  web), shown with "beta" until 1.0.0. Raise it slowly (PATCH for fixes, MINOR for a set of
  features) and add the version to CHANGELOG.md: its section becomes the release notes.
- `master` is the main branch the builds come from. Running both workflows by hand with `release` ticked
  (or a `v…` tag) builds both apps and attaches the APK, AAB and IPA to the GitHub release (notes in `.github/release-notes.md`).
- Strings: Android `ui/I18n.kt` is the source; `ios/PitlaneHQ/I18n.swift` is generated from it.
- The notices the apps show in their inbox come from the server (`web/dist/app-news.json` in the PC and web
  repository): never add or change one without asking the owner first, even when they say "sube todo".
