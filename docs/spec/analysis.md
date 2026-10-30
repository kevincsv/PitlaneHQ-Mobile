# Analysis: the shared analysis engine, laps, coach, maps

How this part of the phone apps behaves. Read it before changing this area; keep it up to date when the behaviour changes. The PC and web behaviour it mirrors is in Pitwall-test's `docs/spec/`.

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
