# The Planner (phones)

In development, like on the PC and the web: only an admin with admin mode on sees it, and only with iRacing chosen.
It is left out of the changelog and the release notes while it is in development.

## Where it is

- Home has a Planner card (after the PC line) with "In development". It shows the next race in the plan (series,
  short track name, day and time, "in 2 h 51 min"), or that the plan is empty. Tapping it opens the Planner.
- Android `ui/Planner.kt` (routes `planner` and `pseries`, tab Home), iOS `Planner.swift` (`Route.planner`,
  `Route.plannerSeries`). The maths is the web planner's, in `data/Season.kt` and `Season.swift`.

## Data

- `GET /community/season` (iRacing's series, their weeks, tracks, cars and classes, and `seen`, the start times the
  PCs saw) and `GET /api/sessions-owned` (the tracks and cars the account raced). Both are saved for offline use.
- Race starts: every `repeat_minutes` from `first_session_time` (UTC) on `day_offset` days from the descriptor's
  `start_date`, or the set `session_times`. `seen` corrects the first time or the gap when the PCs saw other starts
  (the web's applySeen and seenFix).
- Owned marks come only from what the account raced: names are matched by shared words (score 0.6 or more), and a
  track counts with all its layouts.
- The stars and the plan stay on the phone (`plannerFav`, `plannerPlan`). Races more than 3 hours old leave the plan.

## Screens

- Two sub-tabs, Weeks and My season, with the same filters: All series (on by default while nothing is starred,
  else the starred series), the disciplines and the licences R to A.
- Weeks: the season's weeks as a strip (this week outlined, past weeks faded), the number of series and how many are on
  tracks you raced, the dates, and one card per series with its licence, star, short track name and layout, ✓ Track,
  length, the gap between races, rain and a Times button that opens the week sheet.
- My season: per series its weeks as blocks (green on a track you raced, this week outlined amber, past faded), "X of Y
  weeks left on tracks you raced", this week's track and the next start with a + to plan it. Then the tracks you have
  not raced, by how many of the remaining weeks they bring.
- Week sheet: track, layout and dates, ✓ Track and ✓ Car, length, gap, rain, the start times (tap to plan), your
  sessions there with their Race, Qualifying or Practice badge, and Open series.
- Series page: star, licence, discipline, fixed or open setup, multiclass, the description, this week (length,
  sessions, rain, incident limit, drop weeks), the starts of the next 3 days with + Plan, the cars with ✓ for the ones
  you raced, your sessions at this week's track, and the season's schedule (each week opens the week sheet).
