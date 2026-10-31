import BackgroundTasks
import Foundation
import UserNotifications

/// The phone's notifications, only with Account → Notifications on (never by email): a record of yours another driver
/// beat and the summary of your week (the server's alerts.js, read when iOS gives the app a background refresh and each
/// time the app opens), and a reminder 15 minutes before each race in the Planner's plan (a notification set for its time).
/// The same as Android's data/Notify.kt.
enum Notify {
    static let task = "com.pitlanehq.ios.alerts"
    static let lead: Double = 15 * 60_000
    private static let d = UserDefaults.standard

    static var on: Bool { d.bool(forKey: "notifyOn") }

    /// On (after iOS's permission): the background check and the plan's reminders start; off: both stop.
    static func setOn(_ v: Bool, plan: [PlannedRace]) async -> Bool {
        var ok = v
        if v { ok = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false }
        d.set(ok, forKey: "notifyOn")
        if ok && d.object(forKey: "notifySince") == nil { d.set(Date().timeIntervalSince1970 * 1000, forKey: "notifySince") }
        if ok { schedule() } else { BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: task) }
        await self.plan(ok ? plan : [])
        return ok
    }

    /// Once, when the app starts (before it finishes launching): what runs when iOS gives the app a background refresh.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: task, using: nil) { t in
            schedule()
            let job = Task { await check(); t.setTaskCompleted(success: true) }
            t.expirationHandler = { job.cancel() }
        }
    }

    static func schedule() {
        guard on else { return }
        let r = BGAppRefreshTaskRequest(identifier: task)
        r.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }

    private static func post(_ id: String, _ title: String, _ text: String) async {
        let c = UNMutableNotificationContent()
        c.title = title; c.body = text; c.sound = .default
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: c, trigger: nil))
    }

    /// The server's alerts since the last check, as notifications.
    static func check() async {
        guard on, let tok = Vault.get("token").flatMap({ String(data: $0, encoding: .utf8) }) else { return }
        let since = Int64(d.double(forKey: "notifySince"))
        guard let url = URL(string: server.absoluteString + "/community/alerts?since=\(since)") else { return }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.setValue("Bearer " + tok, forHTTPHeaderField: "authorization")
        r.setValue(pitlaneClient, forHTTPHeaderField: "X-Pitlane-Client")
        guard let got = try? await URLSession.shared.data(for: r), (got.1 as? HTTPURLResponse)?.statusCode == 200,
              let j = try? JSONSerialization.jsonObject(with: got.0) as? [String: Any] else { return }
        for a in (j["alerts"] as? [[String: Any]] ?? []).reversed() {
            let id = "alert:" + (a["id"] as? String ?? UUID().uuidString)
            switch a["kind"] as? String {
            case "record_beaten":
                let by = (a["by"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? t("notify_someone")
                let time = (a["time"] as? NSNumber)?.doubleValue ?? 0, was = (a["was"] as? NSNumber)?.doubleValue ?? 0
                await post(id, t("notify_record_title", a["track"] as? String ?? ""), t("notify_record_text", by, lapTime(time), a["car"] as? String ?? "", String(format: "%.3f", was - time)))
            case "week":
                await post(id, a["title"] as? String ?? "", a["text"] as? String ?? "")
            default: break
            }
        }
        d.set((j["now"] as? NSNumber)?.doubleValue ?? Date().timeIntervalSince1970 * 1000, forKey: "notifySince")
    }

    /// A notification 15 minutes before each race of the plan still to come (the ones set before are taken away).
    static func plan(_ plan: [PlannedRace]) async {
        let c = UNUserNotificationCenter.current()
        let old = await c.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix("race:") }
        c.removePendingNotificationRequests(withIdentifiers: old)
        guard on else { return }
        let now = Date().timeIntervalSince1970 * 1000
        for r in plan where r.t - lead > now {
            let n = UNMutableNotificationContent()
            n.title = t("notify_race_title", r.name); n.body = r.track; n.sound = .default
            let trig = UNTimeIntervalNotificationTrigger(timeInterval: (r.t - lead - now) / 1000, repeats: false)
            try? await c.add(UNNotificationRequest(identifier: "race:\(r.sid):\(Int64(r.t))", content: n, trigger: trig))
        }
    }
}
