# DRINKS, races vs AI, leaderboards and track notes

How this part of the phone apps behaves. Read it before changing this area; keep it up to date when the behaviour changes. The PC and web behaviour it mirrors is in Pitwall-test's `docs/spec/`.

- DRINKS mode (formerly Friday night mode, admins only): friends drive on the owner's PC and their laps
  go to the community under their name. Switched on the PC or from the phone (Settings → DRINKS
  mode) through the encrypted live link ("drinks" event); the PC checks the account is an admin.
- A race against iRacing's AI (`ai` on the race) has no iRating: no change in the race rows or the summary, no
  iRating in its results, nothing in the licence summary. A session the server has no `ai` flag for is against the AI when it
  is an iRacing session without a subsession (id "t-…" after the account's "acct_…:" prefix) that is not a test
  (`offlineAI` when the sessions are parsed),
  so My sessions, Laps and the Coach show "vs AI" on it like the PC and the web.
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
- Home (like the web's): Your last race (place, places gained, the track with its RACE tag, the car with its
  discipline's dot, the position by lap, iRating, incidents and best; Le Mans Ultimate shows contacts and best, never
  an iRating), then Recent sessions: races, qualifying and practice together, newest first, each with its kind badge
  (Race amber, Qualifying purple, Practice blue) and the fastest lap in the last column (races too, never the
  iRating). The licences: pressing one marks it in amber and opens its card under the list (iRating, class and SR,
  what its last races gave and its iRating line, which follows the finger); Sports Car is open to start.
- A Le Mans Ultimate race summary shows Start, Finish, Drivers, Contacts, Positions and Best lap (no iRating nor SOF).
