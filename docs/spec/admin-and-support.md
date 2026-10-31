# Admin mode, admin panel, usage and the support button

How this part of the phone apps behaves. Read it before changing this area; keep it up to date when the behaviour changes. The PC and web behaviour it mirrors is in Pitwall-test's `docs/spec/`.

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
  switch) and Server (the emails, the tools with what each does, the blocked sign-ins). Each Feedback row has "Open the support chat" for
  that driver. The phones have no feedback pop-up of their own; the small round feedback button floating at the bottom
  right above the tab bar on every screen (signed in, never in demo data; `SupportFab`/`SupportSheet` on Android,
  `MainView`'s overlay on iOS) opens a small menu (a DropdownMenu on Android, a Menu on iOS, like the web's `fbMenu`)
  with "Send feedback" ("Enviar tu opinión", "Enviar sua opinião", a star) and "Chat with support" ("Chat con soporte",
  "Chat com o suporte", a speech bubble, with the unread count beside it). Send feedback is `FeedbackSheet`: "Share your
  feedback" with the line "What do you like, what is missing and what gets in your way? Every answer is read.", 1 to 5
  optional stars, a text box (up to 4000), Cancel and Send, POST `/community/feedback` {text, rating?, device
  android|ios, v, view "menu:<view>", lang}, "Thank you. Your feedback was sent." when it went (a toast), the server's
  message in the sheet when not, as often as the driver likes; `act:feedback_sent`. Chat with support is
  `SupportSheet`, the support chat, "Support" ("Soporte", "Suporte"): the driver's
  messages on the right, Support's on the left as "Pitlane HQ Support" (never an admin's name), their times, the newest
  at the bottom, a text box and Send, no stars (an old feedback's stars show on its message), "Write to us. We answer
  here." while empty. GET `/community/support` {msgs [{id, me, text, created, kind, rating?}], unread} when it opens and
  every 30 s while open (reading marks Support's messages read), POST `/community/support` {text, device android|ios, v,
  view "menu:<view>", lang}. GET `/community/support/unread` {n, last?} every 2 minutes while the app is on the screen
  and right after sending: the button carries the count of Support's messages not read (an amber circle on its top-right
  corner, "1"… "9+") and the Info inbox a "Support replied" item with the line that opens the chat, until the chat is
  opened; never a system notification. For an admin in admin mode the button skips the menu and opens the support inbox instead (GET
  `/community/admin/support` {items [{accountId, nick, last, lastAt, lastSupport, unread}]}: nick, last line, time,
  unread; a row opens its thread, GET `/community/admin/support/:accountId` {msgs [{id, support, text, created,
  rating…}]}, with a reply box, POST `/community/admin/support/:accountId` {text}, the reply going as Support, and back
  to the list), and its count is GET `/community/admin/support/unread` {n}. Usage `act:feedback_button`, `act:feedback_sent`,
  `act:support_open`, `act:support_sent`, `act:support_reply`.
- What the drivers use, for the admin panel (`Usage`: `use`/`sendUsage` in AccountRepository.kt, `vm.track`; `Usage` in
  Account.swift): the phone counts "view:<screen>" with the PC's view names (home, laps, coach, cloudlaps, races, live,
  standings, tyres, community, leagues, me, admin, session, profile, notes, drinks), "act:<action>" (compare,
  race_summary, leaderboard, track_page, plan_to_overlay, connect, watch_code, share_code, drinks, feedback_button,
  support_open, support_sent, support_reply) and "game:iracing" /
  "game:lmu", keys matching ^(view|act|game):[a-z0-9_.-]{1,40}$, kept on the device until the server has them and sent
  (POST `/community/usage` {device, v, counts}) every 5 minutes while the app is on the screen and when it goes to the
  background; never in demo data, only signed in, cleared at sign-out.
- The admin panel's account card has "Link a DRINKS driver" (the driver's name; `adminAccount(id, "link-guest", name)`)
  and "Unlink DRINKS driver …" for each one joined (`guestLinked` in the accounts list, "gid|name,…").
  Its own driver is linked per game: "Unlink iRacing driver" and "Unlink Le Mans Ultimate driver", one for each game
  linked (`driverGames` in the accounts list, "iracing,lmu"; `adminAccount(id, "unlink-driver", game)`).
- Crashes (`data/Reports.kt`, `Reports.swift`): a crash is written to the app's files as it happens (Android's
  uncaught-exception handler; iOS's uncaught exception and crash signals) and sent the next time the app opens
  (POST `/community/crash` {app "android"/"ios", v, os, where, msg, stack}, with the account when signed in), for the
  Health section of the PC and web admin page.
- The support chat's "Send the app's logs" (drivers only) sends the end of this run's own log (Android's logcat for its
  own process, iOS's OSLogStore) with a line naming the app, the version and the phone (POST
  `/community/support/logs`); the server adds "Logs sent" to the chat. An admin's thread shows "Open the logs" under
  that line (GET `/community/admin/support/logs/:id`), the log in a window with Copy.
- Account → Notifications (its own section before Discord; `data/Notify.kt`, `Notify.swift`), off until the driver
  turns it on (Android 13 and later and iOS ask for the permission first) and never by email. On, the phone tells the
  server (POST `/community/alerts/on` {on, lang}, so Monday's summary of the week is written for the account) and reads
  GET `/community/alerts?since=` in the background (Android every 30 minutes with a network, `AlertJob`; iOS when it
  gives the app a background refresh, `com.pitlanehq.ios.alerts`, and each time the app opens): "Your record at Spa was
  beaten" (who, the time, the car and the gap; "Another driver" for an anonymous one) and the week's summary as the
  server wrote it. The Planner's races get a reminder 15 minutes before (`docs/spec/planner.md`). Off stops all of it.
