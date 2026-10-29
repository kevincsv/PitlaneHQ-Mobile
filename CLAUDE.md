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
- Admin mode is off by default on every phone: an admin of the server sees the app exactly as everyone does until
  they turn on "Admin mode" (Settings, and the same switch at the top of the admin panel, which closes the panel when
  turned off; `adminMode` on the device, `setAdminMode` on Android, `Account.adminMode` on iOS; `admin` = the server's
  admin and admin mode on). With it off nothing for admins or in development shows, and demo data goes off.
- The admin panel (Settings → Admin panel) has the PC's sections, each with one short line saying what it is (admins
  only, the owner asked for an explained panel): Summary (the key numbers of `/community/admin/status` and the analytics
  of GET `/community/admin/analytics?days=7|14|30`: active users per day as bars that follow the finger, devices, the
  most used screens and actions, games, versions), Users (every account with its devices, last seen and top features
  from the analytics' `users`, and every account tool), Feedback (GET `/community/admin/feedback`: what drivers wrote
  from the PC and the web, with stars, device, version and screen), Content (the shared items), Sessions, Coach (GET
  `/community/admin/coach`: the buckets kind × corner speed with cases, gains, thumbs, turning a kind off, the confidence
  switch) and Server (the emails, the tools with what each does, the blocked sign-ins). The phones have no feedback
  pop-up and no "Send feedback" entry (the owner's choice: those are the PC's and the web's).
- What the drivers use, for the admin panel (`Usage`: `use`/`sendUsage` in AccountRepository.kt, `vm.track`; `Usage` in
  Account.swift): the phone counts "view:<screen>" with the PC's view names (home, laps, coach, cloudlaps, races, live,
  standings, tyres, community, leagues, me, admin, session, profile, notes, drinks), "act:<action>" (compare,
  race_summary, leaderboard, track_page, plan_to_overlay, connect, watch_code, share_code, drinks) and "game:iracing" /
  "game:lmu", keys matching ^(view|act|game):[a-z0-9_.-]{1,40}$, kept on the device until the server has them and sent
  (POST `/community/usage` {device, v, counts}) every 5 minutes while the app is on the screen and when it goes to the
  background; never in demo data, only signed in, cleared at sign-out.
- The admin panel's account card has "Link a DRINKS driver" (the driver's name; `adminAccount(id, "link-guest", name)`)
  and "Unlink DRINKS driver …" for each one joined (`guestLinked` in the accounts list, "gid|name,…").
  Its own driver is linked per game: "Unlink iRacing driver" and "Unlink Le Mans Ultimate driver", one for each game
  linked (`driverGames` in the accounts list, "iracing,lmu"; `adminAccount(id, "unlink-driver", game)`).
- This repository is only the Android app (`app/`) and the iOS app (`ios/`). The PC app and the
  web/server (Cloudflare) live in the Pitwall-test repository; the apps talk to that server and
  must keep its protocol: account keys (PBKDF2 600 000 + HKDF, AES-GCM with "pitlanehq-v1"),
  live relay (`/live`, "e:" messages with "pitlanehq-live-v1", gzip JSON [event, data]). The data key also goes once to
  the server (POST /account/escrow with the account's email, `escrowUp`, after a sync that opened the account), which keeps
  it sealed with its own secret so Steam and Discord sign in without the password (the owner's choice): their answer
  brings `dataKey` and `email`; the password is asked (`needKey`, POST /account/key) only when the server keeps none or its
  copy does not open the account, and then this key goes up instead.
- Android and iOS stay the same app: same screens, same features, same wording, and the PC's: Telemetry has the PC's
  Telemetry, Standings and Tyres (`Live` in PitlaneApp.kt, `LiveTabs.swift`, fed by `LiveField`); Analysis has Laps,
  Coach, My sessions and My races (`Analysis` in PitlaneApp.kt, `AnalysisView` and `Analysis.swift`), lap B is your own
  best, the model's next level or its record (`modelRefs`, asked for lap A's tyre compound, `Trace.cmp` from its
  "cmp:<n>" flag: the server gives that compound's references when it has them apart), and each driver is measured
  against their own laps.
  The lap analysis and the coach are the web's own file, `web/dist/pitwall-analysis.js` of the Pitwall-test repository,
  run on the phone (Android's JavaScriptSandbox, `data/AnalysisJs.kt`; iOS's JavaScriptCore, `AnalysisJs.swift`): the
  phones turn both laps into the web's shape (`JsAnalysis.lap`), hand it the official turns, the coach's weights and
  habits and the model's corner cards (`JsAnalysis.ctx`), and show its corners, tips, plan and sectors in their own
  screens (`js`/`jsNow` in `LapAnalysis`, the tip as `text` on `Corner`, `PlanItem`), in the three languages from one
  run. They download pitlanehq.app/pitwall-analysis.js at most every six hours (its ETag) and keep it on disk; the
  copy in the app (`app/src/main/assets/` and `ios/Resources/`, refreshed with `tools/sync-analysis.sh` whenever the
  file changes in Pitwall-test) runs until a download succeeds. The phones feed it what the web feeds it: lap B's path is
  the web's (a model reference's own, else the model's fastest line `lineXY` with its origin g, `recXY`/`lvlXY` in
  `modelRefs`; never the driver's own path, which only draws the fallback's line), and the coach hands it the session's
  laps (`sessionTraces`, /api/sessions/:id?traces=1, as `ctx.laps`, one call each on Android), so the plan's consistency
  steps and the "same braking point every lap" tip are the PC's. Only a copy whose `VERSION` and answer's `v` are the
  ones the app was built for (`JsAnalysis.VERSION`/`version`, 1) is kept and read. LapMath.kt and Models.swift are only
  the fallback, when the engine cannot run (a WebView without the sandbox) or a trace is not one point every 5 m (the
  demo data's), and the charts' own grid.
  The corner tips (the fallback's `corners` in LapMath.kt and Models.swift, texts `tip_*`) follow the measured facts like the PC's
  and the web's: braking later than the reference and arriving slower at the apex is one mistake whatever phase pays
  for it (`tip_brake_late_apex`); with the same braking point the tip is about the brake (harder at first, trail,
  `tip_brake_same`), never "brake later"; an apex reached as fast as the reference's says the time goes before it
  (`tip_entry_before`) or in a longer slow part (`tip_apex_longer`); a throttle picked up earlier but a slower apex
  says to carry the speed (`tip_exit_speed`); only a generic tip (`GENERIC_TIPS`) gives way to the gear, the lifts
  and the line. Every map's road is the track's layout drawn by the community (`trackLayout`, `layout` in
  `LapAnalysis`), else the lap's own path only for the road's shape (the owner's choice): no lap's line is drawn on a
  map (no A or B line, no "Line A / B" switch); the braking points, the coach's corners, the incidents, the sectors,
  the start/finish line, the direction arrow and the point chosen sit on it by their lap distance. The line tips stay.
  Like the web's analyzer, a session's lap list has a column per official sector (S1, S2, S3…, only the sectors that add
  up to the lap's time, `lapSecs`/`secs`, as the web's `lapSecsOf`; purple the session's best, green a valid lap's one better
  than your best lap's), the lap analysis has the braking points table of lap A against lap B per corner (`BrakeTable`: the
  turn, where each brakes, Δ m, red when A brakes 3 m or more before B, the speed at each apex, the gear, the loss and what
  to do, the module's `todo` on each corner, else `tipShort` of the fallback's own tip, the tips an admin turned off
  giving way like everywhere; a row reads that corner on the map and the charts), and the coach's plan has "Take the plan
  to the coach overlay" (`setCoachTurns`: the turns of the plan's first four steps, the module's `turns` on each
  `PlanItem` like the web's `planTurns`, else the fallback's four corners that lose the most, as `ui.coach.turns` with the track as `turnsTrack` in the account's settings.json, only when a PC has
  synced it and never in demo data; an error says its translated text).
- A Le Mans Ultimate leaderboard has "This car / Whole class" like the PC and the web (`boardWhole`/`boardCls` in the
  view model and `Account`, `classBoard`: GET /community/laps?cls= with the class the car board's answer names): the
  class view is each driver's best lap of any car of that class on the track, with their car; the per-car boards, the
  coach and the reference laps stay per car. iRacing has none. Every leaderboard, record and track page row shows what
  its lap was driven in beside the time (`WetBadges`, the server's `wet` bits: 1 rain "Rain", 2 a wet track "Wet", 4 a
  damp one "Damp"; rain goes with either), in every game; the lap labels say "damp track" and "rain" too. Only "wet"
  keeps a lap from the model.
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
