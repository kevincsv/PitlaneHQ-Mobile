import AuthenticationServices
import Foundation
import Security
import UIKit

let server = URL(string: "https://pitlanehq.app")!
/// This app and its version for the server ("ios/0.6.0", the X-Pitlane-Client header of every request).
let pitlaneClient = "ios/" + ((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0").replacingOccurrences(of: "-beta", with: "")
let webApp = URL(string: "https://pitlanehq.app/")!
/// Support Pitlane HQ (Settings); empty: not shown.
let patreonURL = "https://www.patreon.com/c/PitlaneHQ/membership"
let supportEmail = "support@pitlanehq.app"
let feedbackURL = URL(string: "mailto:support@pitlanehq.app?subject=Pitlane%20HQ%20feedback")!
let changelogURL = "https://pitlanehq.app/changelog/phones"

/// Errors the screens show in the user's language: `key` is a key of I18n (or a server message).
struct AppError: LocalizedError {
    let key: String
    var errorDescription: String? { key }
    static let signedOut = AppError(key: "signed_out")
    static let offline = AppError(key: "no_internet")
    static let serverDown = AppError(key: "server_down")
}

/// Data from the server, or the copy saved on this phone when the server cannot be reached (`stale`).
struct Got<T> {
    let data: T
    var stale = false
}

// ---------- what the drivers use (the admin panel's analytics) ----------

/// Counted on this phone ("view:laps", "act:compare", "game:lmu") until the server has them (POST /community/usage);
/// never in demo data, only signed in.
enum Usage {
    private static let key = "usage"
    private static let lock = NSLock()
    private static let pattern = try? NSRegularExpression(pattern: "^(view|act|game):[a-z0-9_.-]{1,40}$")
    /// the screen on view, by the PC's view names: where the feedback button was pressed ("menu:<view>")
    static var view = "home"
    private static let actView = ["act:race_summary": "race", "act:leaderboard": "leaderboard", "act:track_page": "track", "act:compare": "lap"]
    static func count(_ k: String) {
        if k.hasPrefix("view:") { view = String(k.dropFirst(5)) } else if let v = actView[k] { view = v }
        guard !UserDefaults.standard.bool(forKey: "demo"), Vault.get("token") != nil,
              pattern?.firstMatch(in: k, range: NSRange(k.startIndex..., in: k)) != nil else { return }
        lock.lock(); defer { lock.unlock() }
        var c = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        c[k, default: 0] += 1
        UserDefaults.standard.set(c, forKey: key)
    }
    static var pending: [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return (UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]).filter { $0.value > 0 }
    }
    /// what the server got comes off (what was counted meanwhile stays)
    static func taken(_ sent: [String: Int]) {
        lock.lock(); defer { lock.unlock() }
        var c = UserDefaults.standard.dictionary(forKey: key) as? [String: Int] ?? [:]
        for (k, n) in sent { let left = (c[k] ?? 0) - n; c[k] = left > 0 ? left : nil }
        UserDefaults.standard.set(c, forKey: key)
    }
    static func clear() {
        lock.lock(); defer { lock.unlock() }
        UserDefaults.standard.removeObject(forKey: key)
    }
}

// ---------- Keychain ----------

enum Vault {
    private static let service = "com.pitlanehq.account"

    static func set(_ key: String, _ value: Data?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard let value else { return }
        var add = q
        add[kSecValueData as String] = value
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(_ key: String) -> Data? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: key,
            kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }
}

private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
private func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
private func str(_ v: Any?) -> String { v as? String ?? "" }
/// The car's class when the server sends one (Le Mans Ultimate: Hypercar, LMP2…).
private func clsOf(_ o: [String: Any]) -> String? { ["cls", "carClass", "class"].map { str(o[$0]) }.first { !$0.isEmpty && $0 != "null" } }
/// a positive whole number, or nil (missing, null or 0)
private func posInt(_ v: Any?) -> Int? { (v as? NSNumber).map(\.intValue).flatMap { $0 > 0 ? $0 : nil } }
private func orNull(_ v: Any?) -> Any { v ?? NSNull() }
private func pos(_ v: Any?) -> Double? { num(v).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
private func doubles(_ v: Any?) -> [Double] { (v as? [NSNumber] ?? []).map(\.doubleValue) }

/// One message of the support chat: `driver` the driver's own (else Support's), `rating` the stars of an old feedback.
struct SupportMsg: Identifiable {
    let id: String, driver: Bool, text: String, created: Double, rating: Int
}
/// One driver's conversation in the support inbox (admins): the last line, who wrote it, how many unread.
struct SupportConv: Identifiable {
    var id: String { accountId }
    let accountId: String, nick: String, text: String, created: Double, fromSupport: Bool, unread: Int
}

/// The Pitlane HQ account, exactly like the PC, the web app and Android: the password only
/// derives the keys on this phone; the session token and the data key stay in the Keychain,
/// and the copies saved for offline use are sealed with the data key.
@MainActor
final class Account: ObservableObject {
    @Published var signedIn = false
    @Published var email = ""
    @Published var display = ""
    @Published var verified = true
    /// one of the server's admins (ADMINS): only they can turn on demo data
    @Published var realAdmin = false {
        didSet { if !admin && demo { demo = false } }
    }
    /// admin mode, on this phone: off by default (an admin sees the app as everyone does), one switch turns it on
    @Published var adminMode = UserDefaults.standard.bool(forKey: "adminMode") {
        didSet { UserDefaults.standard.set(adminMode, forKey: "adminMode"); if !admin && demo { demo = false }; supportUnread = 0; Task { await checkSupport() } }
    }
    /// what the screens use: an admin of the server with admin mode on
    var admin: Bool { realAdmin && adminMode }
    @Published var busy = false
    @Published var error: String?
    @Published var needCode = false        // the password was right: the authenticator code comes next
    @Published var twoFactor = UserDefaults.standard.bool(forKey: "twoFactor")
    @Published var recoveryLeft = UserDefaults.standard.integer(forKey: "recoveryLeft")
    /// the supporter badge (donates), and whether its owner hid it
    @Published var supporter = UserDefaults.standard.bool(forKey: "supporter")
    @Published var supporterHidden = UserDefaults.standard.bool(forKey: "supporterHidden")
    private var pending: (token: String, email: String, wrap: Data)?
    @Published var syncedFiles = 0
    @Published var syncVersion = 0
    @Published var syncUpdated: Double = 0
    @Published var races: [Race] = []
    /// goes up after every read of the account (the app came back, the live room's nudge): the screens ask the server
    /// again for the sessions and the month's numbers, which are not in the bundle
    @Published var refreshTick = 0
    /// the thumbs the driver gave the coach's tips on this device, by session and corner ("sid:apexM" → 1 or -1)
    @Published var tipRatings: [String: Int] = [:]
    @Published var demo = UserDefaults.standard.bool(forKey: "demo") {
        didSet { UserDefaults.standard.set(demo, forKey: "demo"); loadRaces(); if demo { supportUnread = 0; supportOpen = nil } }
    }

    // ---------- the game you look at: iRacing or Le Mans Ultimate (Home, Analysis, Community) ----------
    // Only what this phone shows: never what your PC reads. Telemetry follows the PC's live game.
    /// the game chosen on this phone (remembered), else the one your PC reads live, else iRacing
    @Published private(set) var game: String = games.contains(UserDefaults.standard.string(forKey: "game") ?? "") ? UserDefaults.standard.string(forKey: "game")! : "iracing"
    /// whether the driver chose it on this phone (else it follows the game the PC reads live)
    var gameChosen: Bool { games.contains(defaults.string(forKey: "game") ?? "") }
    /// per game: how many sessions you have and the last one's date (the sheet that asks which game to see)
    @Published var gameStats: [String: (n: Int, last: Double)] = [:]
    /// "What do you want to see?": once when the app opens, with sessions of both games (MainView adds: the PC not live)
    @Published var askGame = false
    private var gameAsked = false
    private var allRaces: [Race] = []

    func setGame(_ g: String, remember: Bool = true) {
        guard games.contains(g) else { return }
        if remember { defaults.set(g, forKey: "game") }
        askGame = false
        guard g != game else { return }
        game = g
        Usage.count("game:" + g)
        races = allRaces.filter { $0.game == g }
    }

    private func noteStats(_ st: [String: (n: Int, last: Double)]) {
        gameStats = st
        if !gameAsked && !demo {
            gameAsked = true
            if st.values.filter({ $0.n > 0 }).count > 1 { askGame = true }
        }
    }

    private let defaults = UserDefaults.standard
    private let dir: URL = {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("saved", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }()

    init() {
        // a reinstall keeps the Keychain but not the settings: start signed out then
        if defaults.string(forKey: "email") == nil { Vault.set("token", nil); Vault.set("dataKey", nil) }
        signedIn = Vault.get("token") != nil && Vault.get("dataKey") != nil
        email = defaults.string(forKey: "email") ?? ""
        display = defaults.string(forKey: "display") ?? ""
        verified = defaults.object(forKey: "verified") as? Bool ?? true
        realAdmin = defaults.bool(forKey: "admin")
        if !admin && demo { demo = false }
        syncedFiles = defaults.integer(forKey: "syncedFiles")
        syncVersion = defaults.integer(forKey: "syncVersion")
        syncUpdated = defaults.double(forKey: "syncUpdated")
        loadRaces()
    }

    var token: String? { Vault.get("token").flatMap { String(data: $0, encoding: .utf8) } }
    var dataKey: Data? { Vault.get("dataKey") }

    /// Your iRating of every discipline as the PC last saw it (ratings.json): discipline → (iRating, licence, when ms).
    func ratings() -> [String: (ir: Int, lic: String, at: Double)] {
        guard !demo, let d = saved("ratings"), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [:] }
        var out: [String: (ir: Int, lic: String, at: Double)] = [:]
        // 1 / "R 0.01": an offline session's placeholder, nobody's rating
        for (k, v) in o { if let x = v as? [String: Any], int(x["ir"]) > 1 { out[k] = (int(x["ir"]), str(x["lic"]), (x["at"] as? NSNumber)?.doubleValue ?? 0) } }
        return out
    }

    /// Your Le Mans Ultimate Safety Rating and Driver Rank as the PC last saw them ("lmu" in ratings.json: sr, dr, at), as the game wrote them.
    func lmuRating() -> (sr: String, dr: String)? {
        guard !demo, let d = saved("ratings"), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let x = o["lmu"] as? [String: Any] else { return nil }
        func v(_ k: String) -> String {
            if let s = x[k] as? String { return s.trimmingCharacters(in: .whitespaces) }
            if let n = x[k] as? NSNumber { return n.stringValue }
            return ""
        }
        let sr = v("sr"), dr = v("dr")
        return sr.isEmpty && dr.isEmpty ? nil : (sr, dr)
    }

    // ---------- driver notes: your marks on other drivers (drivers.json in the account) ----------

    @Published var driverNotes: [String: DriverNote] = [:]

    func loadDriverNotes() {
        let raw = demo ? UserDefaults.standard.data(forKey: "demoDrivers") : saved("drivers")
        let o = raw.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        driverNotes = o.reduce(into: [:]) { acc, kv in
            if let v = kv.value as? [String: Any] { acc[kv.key] = DriverNote(name: str(v["name"]), tag: str(v["tag"]), note: str(v["note"])) }
        }
    }

    static func nameKey(_ name: String) -> String {
        let n = name.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return n.isEmpty ? "" : "n:" + n
    }

    func noteFor(_ key: String, _ name: String) -> DriverNote? {
        if !key.isEmpty, let n = driverNotes[key] { return n }
        return driverNotes[Account.nameKey(name)]
    }

    /// Saves your note on a driver (no tag and no note removes it) in the account's bundle, the same file the PC and
    /// the web keep: the bundle is read, only drivers.json changes, and it goes back sealed with your key.
    func setDriverNote(key: String, name: String, tag: String, note: String) async throws {
        let isKey = key.count == 32 && key.allSatisfy { "0123456789abcdef".contains($0) }
        let nk = Account.nameKey(name), k = isKey ? key : nk
        guard !k.isEmpty else { return }
        let t = ["danger", "careful", "clean", "friend"].contains(tag) ? tag : ""
        let n = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        func change(_ dv: inout [String: Any]) {
            if !nk.isEmpty && nk != k { dv.removeValue(forKey: nk) }
            if t.isEmpty && n.isEmpty { dv.removeValue(forKey: k) }
            else { dv[k] = ["name": String(name.prefix(80)), "tag": t, "note": n, "updated": Int(Date().timeIntervalSince1970 * 1000)] }
        }
        if demo {
            var dv = UserDefaults.standard.data(forKey: "demoDrivers").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            change(&dv)
            UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: dv), forKey: "demoDrivers")
            loadDriverNotes()
            return
        }
        guard let dk = dataKey else { throw AppError.signedOut }
        for attempt in 0..<3 {
            let j = try JSONSerialization.jsonObject(with: await call("GET", "/account/sync")) as? [String: Any] ?? [:]
            var all: [String: Any] = [:]
            if let blob = j["blob"] as? String, !blob.isEmpty {
                all = try JSONSerialization.jsonObject(with: PLCrypto.gunzip(PLCrypto.open(key: dk, sealed: blob, aad: PLCrypto.accountAAD))) as? [String: Any] ?? [:]
            }
            var dv = (all["drivers.json"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            change(&dv)
            let dvData = try JSONSerialization.data(withJSONObject: dv)
            all["drivers.json"] = dvData.base64EncodedString()
            let sealed = try PLCrypto.seal(key: dk, plain: PLCrypto.gzip(JSONSerialization.data(withJSONObject: all)), aad: PLCrypto.accountAAD)
            do {
                let r = try JSONSerialization.jsonObject(with: await call("PUT", "/account/sync", body: ["blob": sealed, "base": j["version"] ?? 0])) as? [String: Any] ?? [:]
                syncVersion = int(r["version"])
                defaults.set(syncVersion, forKey: "syncVersion")
                save("drivers", dvData)
                loadDriverNotes()
                return
            } catch let e as AppError where e.key.lowercased().contains("conflict") && attempt < 2 {
                // another device wrote the account meanwhile: read it again and redo the change on top
                continue
            }
        }
    }

    // ---------- track notes: yours on each track (notes.json in the account) ----------

    @Published var trackNotes: [Int64: TrackNote] = [:]

    func loadTrackNotes() {
        let raw = demo ? UserDefaults.standard.data(forKey: "demoNotes") : saved("notes")
        let o = raw.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        trackNotes = o.reduce(into: [:]) { acc, kv in
            guard let v = kv.value as? [String: Any] else { return }
            let id = Int64(int(v["trackId"])) == 0 ? Int64(kv.key) ?? 0 : Int64(int(v["trackId"]))
            guard id != 0 else { return }
            let cs = (v["corners"] as? [[String: Any]] ?? []).map { CornerNote(n: int($0["n"]), dist: num($0["dist"]) ?? 0, name: str($0["name"]), note: str($0["note"])) }
                .filter { !$0.note.isEmpty }.sorted { $0.dist < $1.dist }
            acc[id] = TrackNote(trackId: id, track: str(v["track"]), general: str(v["general"]), corners: cs, updated: str(v["updated"]))
        }
    }

    /// Saves your general note on a track in the account's bundle (its corner notes stay as they are; no note and no
    /// corner removes it), like the PC and the web: only notes.json changes, and it goes back sealed with your key.
    func setTrackNote(trackId: Int64, track: String, general: String) async throws {
        guard trackId != 0 else { return }
        let g = String(general.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000)), k = String(trackId)
        func change(_ nv: inout [String: Any]) {
            var cur = nv[k] as? [String: Any] ?? ["trackId": trackId, "track": String(track.prefix(120))]
            if g.isEmpty { cur.removeValue(forKey: "general") } else { cur["general"] = g }
            if str(cur["track"]).isEmpty { cur["track"] = String(track.prefix(120)) }
            cur["updated"] = ISO8601DateFormatter().string(from: Date())
            if g.isEmpty && (cur["corners"] as? [Any] ?? []).isEmpty { nv.removeValue(forKey: k) } else { nv[k] = cur }
        }
        if demo {
            var nv = UserDefaults.standard.data(forKey: "demoNotes").flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            change(&nv)
            UserDefaults.standard.set(try? JSONSerialization.data(withJSONObject: nv), forKey: "demoNotes")
            loadTrackNotes()
            return
        }
        guard let dk = dataKey else { throw AppError.signedOut }
        for attempt in 0..<3 {
            let j = try JSONSerialization.jsonObject(with: await call("GET", "/account/sync")) as? [String: Any] ?? [:]
            var all: [String: Any] = [:]
            if let blob = j["blob"] as? String, !blob.isEmpty {
                all = try JSONSerialization.jsonObject(with: PLCrypto.gunzip(PLCrypto.open(key: dk, sealed: blob, aad: PLCrypto.accountAAD))) as? [String: Any] ?? [:]
            }
            var nv = (all["notes.json"] as? String).flatMap { Data(base64Encoded: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
            change(&nv)
            let nvData = try JSONSerialization.data(withJSONObject: nv)
            all["notes.json"] = nvData.base64EncodedString()
            let sealed = try PLCrypto.seal(key: dk, plain: PLCrypto.gzip(JSONSerialization.data(withJSONObject: all)), aad: PLCrypto.accountAAD)
            do {
                let r = try JSONSerialization.jsonObject(with: await call("PUT", "/account/sync", body: ["blob": sealed, "base": j["version"] ?? 0])) as? [String: Any] ?? [:]
                syncVersion = int(r["version"])
                defaults.set(syncVersion, forKey: "syncVersion")
                save("notes", nvData)
                loadTrackNotes()
                return
            } catch let e as AppError where e.key.lowercased().contains("conflict") && attempt < 2 {
                continue // another device wrote the account meanwhile: read it again and redo the change on top
            }
        }
    }

    /// The coach's plan to the coach overlay of your PC, like the web: the overlay's chosen corners (`ui.coach.turns`, "T4")
    /// in the account's settings.json, the PC's own settings, which it takes at its next sync. Only that value changes and
    /// the bundle goes back sealed with your key. The corners are for the plan's track (`turnsTrack`): on another one the
    /// overlay speaks at the three that cost the most. False when the account has no settings from a PC yet (nothing to
    /// reach), and in demo data (nothing is written).
    func setCoachTurns(_ turns: [String], trackId: Int64) async throws -> Bool {
        if demo { return false }
        Usage.count("act:plan_to_overlay")
        guard let dk = dataKey else { throw AppError.signedOut }
        for attempt in 0..<3 {
            let j = try JSONSerialization.jsonObject(with: await call("GET", "/account/sync")) as? [String: Any] ?? [:]
            guard let blob = j["blob"] as? String, !blob.isEmpty else { return false }
            var all = try JSONSerialization.jsonObject(with: PLCrypto.gunzip(PLCrypto.open(key: dk, sealed: blob, aad: PLCrypto.accountAAD))) as? [String: Any] ?? [:]
            guard var st = (all["settings.json"] as? String).flatMap({ Data(base64Encoded: $0) }).flatMap({ try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }) else { return false }
            var ui = st["ui"] as? [String: Any] ?? [:]
            var coach = ui["coach"] as? [String: Any] ?? [:]
            coach["turns"] = turns
            coach["turnsTrack"] = trackId > 0 ? trackId : 0
            ui["coach"] = coach
            st["ui"] = ui
            all["settings.json"] = try JSONSerialization.data(withJSONObject: st).base64EncodedString()
            let sealed = try PLCrypto.seal(key: dk, plain: PLCrypto.gzip(JSONSerialization.data(withJSONObject: all)), aad: PLCrypto.accountAAD)
            do {
                let r = try JSONSerialization.jsonObject(with: await call("PUT", "/account/sync", body: ["blob": sealed, "base": j["version"] ?? 0])) as? [String: Any] ?? [:]
                syncVersion = int(r["version"])
                defaults.set(syncVersion, forKey: "syncVersion")
                return true
            } catch let e as AppError where e.key.lowercased().contains("conflict") && attempt < 2 {
                continue // another device wrote the account meanwhile: read it again and redo the change on top
            }
        }
        return false
    }

    // ---------- saved copies (sealed with the account's data key) ----------

    private func file(_ name: String) -> URL { dir.appendingPathComponent(String(name.map { $0.isLetter || $0.isNumber || "_.-".contains($0) ? $0 : "_" }.prefix(120))) }

    private func save(_ name: String, _ data: Data) {
        guard let key = dataKey, let s = try? PLCrypto.seal(key: key, plain: data, aad: PLCrypto.accountAAD) else { return }
        try? Data(s.utf8).write(to: file(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func saved(_ name: String) -> Data? {
        guard let key = dataKey, let d = try? Data(contentsOf: file(name)), let s = String(data: d, encoding: .utf8) else { return nil }
        return try? PLCrypto.open(key: key, sealed: s, aad: PLCrypto.accountAAD)
    }

    private func clear() {
        supportUnread = 0; supportLast = ""; supportOpen = nil
        Vault.set("token", nil)
        Vault.set("dataKey", nil)
        for k in ["email", "display", "verified", "admin", "syncedFiles", "syncVersion", "syncUpdated", "twoFactor", "recoveryLeft", "acctId"] { defaults.removeObject(forKey: k) }
        twoFactor = false
        recoveryLeft = 0
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        signedIn = false
        display = ""
        syncedFiles = 0
        syncVersion = 0
        syncUpdated = 0
        realAdmin = false
        Usage.clear()
        races = []
        allRaces = []
    }

    // ---------- server ----------

    /// `bearer`: a session of its own (a Steam sign-in waiting for the password); `pass`: the call checks the password
    /// (or a code), so a 401 is a wrong one and never signs this phone out.
    func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true, bearer: String? = nil, pass: Bool = false) async throws -> Data {
        guard let url = URL(string: server.absoluteString + path) else { throw AppError.serverDown }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = method
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if let bearer {
            r.setValue("Bearer " + bearer, forHTTPHeaderField: "authorization")
        } else if auth {
            guard let t = token else { throw AppError.signedOut }
            r.setValue("Bearer " + t, forHTTPHeaderField: "authorization")
        }
        // every call says which app and version it is ("ios/0.6.0"), for the admin page's Online tab
        r.setValue(pitlaneClient, forHTTPHeaderField: "X-Pitlane-Client")
        // admin mode on: the race rivals show by their name (the server checks the account is an admin's)
        if admin { r.setValue("1", forHTTPHeaderField: "X-Pitlane-Admin") }
        let pair: (Data, URLResponse)
        do {
            pair = try await URLSession.shared.data(for: r)
        } catch {
            throw AppError.offline
        }
        let (data, resp) = pair
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && (pass || bearer != nil) {
            throw AppError(key: ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String) ?? "wrong_pw")
        }
        if code == 401 && auth {
            clear()
            error = AppError.signedOut.key
            throw AppError.signedOut
        }
        guard (200..<300).contains(code) else {
            if code >= 500 { throw AppError.serverDown }
            let msg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            throw AppError(key: msg ?? "server_down")
        }
        return data
    }

    /// A GET whose answer is saved, so the screen still has it without a connection.
    private func cachedGet(_ path: String) async throws -> Got<Any> {
        do {
            let d = try await call("GET", path)
            save(path, d)
            return Got(data: try JSONSerialization.jsonObject(with: d))
        } catch let e as AppError where e.key == AppError.offline.key || e.key == AppError.serverDown.key {
            guard let d = saved(path) else { throw e }
            return Got(data: try JSONSerialization.jsonObject(with: d), stale: true)
        }
    }

    func login(email e: String, password: String) async {
        let em = e.trimmingCharacters(in: .whitespaces).lowercased()
        guard em.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else { error = "bad_email"; return }
        guard !password.isEmpty else { error = "enter_pw"; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let keys = try await Task.detached { try PLCrypto.derive(email: em, password: password) }.value
            let data = try await call("POST", "/account/login", body: ["email": em, "auth": keys.auth, "device": "iPhone"], auth: false)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.serverDown }
            if j["twoFactor"] as? Bool == true, let p = j["pending"] as? String {
                pending = (p, em, keys.wrap)
                needCode = true
                return
            }
            try finishLogin(j, email: em, wrap: keys.wrap)
            await sync()
        } catch {
            self.error = (error as? AppError)?.key ?? error.localizedDescription
        }
    }

    /// Second step of the sign-in: the 6-digit code of the authenticator app, or a recovery code.
    func loginCode(_ code: String) async {
        guard let p = pending else { needCode = false; error = "sign_in_again"; return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let data = try await call("POST", "/account/login/2fa", body: ["pending": p.token, "code": code.trimmingCharacters(in: .whitespaces)], auth: false)
            guard let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw AppError.serverDown }
            pending = nil
            needCode = false
            try finishLogin(j, email: p.email, wrap: p.wrap)
            await sync()
        } catch {
            self.error = (error as? AppError)?.key ?? error.localizedDescription
        }
    }

    func cancelCode() { pending = nil; needCode = false; error = nil }

    private func finishLogin(_ j: [String: Any], email em: String, wrap: Data) throws {
        guard let wrapped = j["wrappedKey"] as? String else { throw AppError.serverDown }
        try finishLogin(j, email: em, key: PLCrypto.open(key: wrap, sealed: wrapped, aad: PLCrypto.accountAAD))
    }

    private func finishLogin(_ j: [String: Any], email em: String, key: Data) throws {
        guard let token = j["token"] as? String, key.count == 32 else { throw AppError.serverDown }
        Vault.set("token", Data(token.utf8))
        Vault.set("dataKey", key)
        email = em
        display = str(j["display"])
        verified = j["verified"] as? Bool ?? true
        realAdmin = j["admin"] as? Bool ?? false
        twoFactor = j["twoFactor"] as? Bool ?? false
        defaults.set(realAdmin, forKey: "admin")
        defaults.set(em, forKey: "email")
        defaults.set(display, forKey: "display")
        defaults.set(verified, forKey: "verified")
        defaults.set(twoFactor, forKey: "twoFactor")
        defaults.set(j["escrow"] as? Bool ?? false, forKey: "escrow")
        escrowTried = false
        signedIn = true
    }

    // the data key goes to the server once (POST /account/escrow, with the account's email) after it opened the account's
    // copy, so a sign-in with Steam or Discord needs no password. Tried once while the app runs, while the server keeps none
    private var escrowTried = false
    private func escrowUp() async {
        guard !defaults.bool(forKey: "escrow"), !escrowTried, let key = dataKey, key.count == 32 else { return }
        escrowTried = true
        var body: [String: Any] = ["key": key.map { String(format: "%02x", $0) }.joined()]
        if !email.isEmpty { body["email"] = email }
        if (try? await call("POST", "/account/escrow", body: body)) != nil { defaults.set(true, forKey: "escrow") }
    }

    /// The server's copy of the data key in a sign-in's answer (dataKey), when it opens the account's data (or there is
    /// none yet). A check that cannot run is tried again a moment later; one that never runs leaves it not verified (nil:
    /// the password once, as without a copy).
    private func escrowKey(_ j: [String: Any]) async -> Data? {
        let hex = str(j["dataKey"])
        guard hex.count == 64, hex.allSatisfy({ "0123456789abcdef".contains($0) }), let tok = j["token"] as? String else { return nil }
        let chars = Array(hex)
        let key = Data((0..<32).map { UInt8(String(chars[$0 * 2...$0 * 2 + 1]), radix: 16)! })
        for n in 0..<3 {
            if n > 0 { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            guard let d = try? await call("GET", "/account/sync", bearer: tok), let o = try? obj(d) else { continue }
            let blob = str(o["blob"])
            return blob.isEmpty || (try? PLCrypto.open(key: key, sealed: blob, aad: PLCrypto.accountAAD)) != nil ? key : nil
        }
        return nil
    }

    /// Signed in by Steam or Discord: with the server's copy of the key when it opens the account, else the password comes next.
    private func socialSigned(_ r: [String: Any]) async throws {
        guard let key = await escrowKey(r) else { socialSession = r; socialNeedKey = true; return }
        var j = r
        j["escrow"] = true
        try finishLogin(j, email: str(r["email"]).trimmingCharacters(in: .whitespaces).lowercased(), key: key)
        socialSession = nil
        socialNeedKey = false
        await sync()
    }

    // ---------- Sign in with Steam or Discord (steam.js, discord.js), and linking them ----------
    // The sign-in sheet goes to Steam or Discord and closes on this app's own address (pitlanehq://steam?state=…&…,
    // pitlanehq://discord?…). The code each start gives stays here, in memory, with its state: a grant is only good with
    // it. Steam or Discord says who; the data key comes from the server's copy (dataKey), or from the password once on this
    // phone when it has none (POST /account/key).
    private var signupCode: String?               // the code a sign-up grant (sid) is redeemed with
    private var socialPending: String?            // the authenticator's code comes next (two-step sign-in on)
    private var socialSession: [String: Any]?     // signed in by Steam or Discord, waiting for the password
    private var authSheet: AuthSheet?
    /// the sign-in screen's state: which one ("steam", "discord"), and what comes next
    @Published var socialProv = ""
    @Published var socialBusy = false
    @Published var socialNeedCode = false
    @Published var socialNeedKey = false
    @Published var socialNew: SocialNew?
    @Published var socialError: String?

    private func obj(_ d: Data) throws -> [String: Any] { try JSONSerialization.jsonObject(with: d) as? [String: Any] ?? [:] }
    private func errKey(_ e: Error) -> String { (e as? AppError)?.key ?? e.localizedDescription }

    /// A start's answer (url, state, code), then the sign-in sheet until it closes on pitlanehq://<prov>: the answer's
    /// parameters with the start's code, or nil when the driver closed it. Another state is never taken.
    private func browse(_ prov: String, _ j: [String: Any]) async throws -> (q: [String: String], code: String)? {
        let state = str(j["state"]), code = str(j["code"])
        guard let u = URL(string: str(j["url"])), !state.isEmpty, !code.isEmpty else { throw AppError.serverDown }
        let a = AuthSheet()
        authSheet = a
        defer { authSheet = nil }
        guard let cb = await a.run(u), cb.host == prov else { return nil }
        let q = steamQuery(cb)
        guard q["state"] == state else { throw AppError(key: prov + "_again") }
        return (q, code)
    }

    /// "Continue with Steam" / "Continue with Discord": signs in (the code and the password come next), or opens the
    /// new account's form.
    func socialSignIn(_ prov: String) async {
        socialCancel()
        socialProv = prov
        socialBusy = true
        defer { socialBusy = false }
        do {
            let j = try obj(await call("POST", "/account/\(prov)/login/start", body: ["device": "iPhone", "app": 1], auth: false))
            guard let back = try await browse(prov, j) else { return }
            let q = back.q, code = back.code
            let g = q[prov + "Login"] ?? ""
            if g == "0", q["new"] == "1", let sid = q["sid"], !sid.isEmpty {
                signupCode = code
                socialNew = SocialNew(sid: sid, name: q[prov == "discord" ? "name" : "persona"] ?? "")
                return
            }
            if g == "0", q["relink"] == "1" { socialError = "discord_relink_login"; return }
            guard !g.isEmpty, g != "0" else { socialError = prov + "_failed"; return }
            let r = try obj(await call("POST", "/account/login/\(prov)", body: ["grant": g, "code": code, "device": "iPhone", "lang": I18n.shared.lang], auth: false))
            if r["twoFactor"] as? Bool == true, let p = r["pending"] as? String { socialPending = p; socialNeedCode = true; return }
            try await socialSigned(r)
        } catch {
            socialError = errKey(error)
        }
    }

    /// Two-step sign-in on: the authenticator's code, then signed in (or the password, without the server's copy of the key).
    func socialLoginCode(_ code: String) async {
        guard let p = socialPending else { socialCancel(); socialError = "sign_in_again"; return }
        socialBusy = true
        socialError = nil
        defer { socialBusy = false }
        do {
            let r = try obj(await call("POST", "/account/login/2fa", body: ["pending": p, "code": code.trimmingCharacters(in: .whitespaces)], auth: false))
            socialPending = nil
            socialNeedCode = false
            try await socialSigned(r)
        } catch { socialError = errKey(error) }
    }

    /// The password once on this phone: the server hands the data key wrapped with it, and it opens here.
    func socialKey(email e: String, password: String) async {
        guard let s = socialSession, let tok = s["token"] as? String else { socialCancel(); socialError = "sign_in_again"; return }
        let em = e.trimmingCharacters(in: .whitespaces).lowercased()
        guard em.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else { socialError = "bad_email"; return }
        guard !password.isEmpty else { socialError = "enter_pw"; return }
        socialBusy = true
        socialError = nil
        defer { socialBusy = false }
        do {
            let keys = try await Task.detached { try PLCrypto.derive(email: em, password: password) }.value
            let r: [String: Any]
            do { r = try obj(await call("POST", "/account/key", body: ["auth": keys.auth], bearer: tok)) }
            catch let x as AppError where x.key == "the password is wrong" { throw AppError(key: "wrong_email_pw") }
            guard let wrapped = r["wrappedKey"] as? String, let key = try? PLCrypto.open(key: keys.wrap, sealed: wrapped, aad: PLCrypto.accountAAD) else { throw AppError(key: "wrong_email_pw") }
            var j = s
            j["escrow"] = false // the server's copy (if any) did not open the account: this key goes up
            try finishLogin(j, email: em, key: key)
            socialSession = nil
            socialNeedKey = false
            await sync()
        } catch { socialError = errKey(error) }
    }

    /// The sign-in left halfway: its session (if any) is closed on the server.
    func socialCancel() {
        if let t = socialSession?["token"] as? String { Task { _ = try? await call("POST", "/account/logout", body: [:], bearer: t) } }
        socialSession = nil
        socialPending = nil
        signupCode = nil
        socialNeedCode = false
        socialNeedKey = false
        socialNew = nil
        socialError = nil
    }

    /// A new account, like the web's: a new data key wrapped with the password; made from a Steam or Discord sign-in
    /// (socialNew), which links it at once. When the server sent the email to confirm first, the sign-in screen says so.
    func register(email e: String, password: String, name: String) async {
        let em = e.trimmingCharacters(in: .whitespaces).lowercased()
        guard em.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else { socialError = "bad_email"; return }
        guard password.count >= 10 else { socialError = "pw_short"; return }
        let nm = String(name.trimmingCharacters(in: .whitespaces).prefix(32))
        guard !nm.isEmpty else { socialError = "choose_name"; return }
        let sid = socialNew?.sid ?? "", prov = socialProv
        socialBusy = true
        socialError = nil
        defer { socialBusy = false }
        do {
            let keys = try await Task.detached { try PLCrypto.derive(email: em, password: password) }.value
            var key = Data(count: 32)
            let ok = key.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, 32, $0.baseAddress!) }
            guard ok == errSecSuccess else { throw AppError.serverDown }
            let wrapped = try PLCrypto.seal(key: keys.wrap, plain: key, aad: PLCrypto.accountAAD)
            var body: [String: Any] = ["email": em, "auth": keys.auth, "wrappedKey": wrapped, "display": nm, "nameKind": "nick", "device": "iPhone", "lang": I18n.shared.lang]
            if !sid.isEmpty {
                guard let code = signupCode else { throw AppError(key: prov + "_again") }
                body[prov == "discord" ? "discordSid" : "sid"] = sid
                body["code"] = code
            }
            let j = try obj(await call("POST", "/account/register", body: body, auth: false))
            if !sid.isEmpty { signupCode = nil }
            socialNew = nil
            let taken = j["discordTaken"] as? Bool == true
            if j["verifyFirst"] as? Bool == true || j["token"] == nil {
                email = em
                error = taken ? "discord_taken_verify" : "verify your email first: we sent you a link, open it and then sign in"
                return
            }
            try finishLogin(j, email: em, key: key)
            await sync()
            if taken { error = "discord_taken" }
        } catch { socialError = errKey(error) }
    }

    // ---------- Account → Steam and Discord: link them (the password first), show them on your profile, unlink them ----------
    func steam() async throws -> Got<SteamLink> {
        let j = try obj(await call("GET", "/account/steam"))
        return Got(data: SteamLink(linked: j["linked"] as? Bool ?? false, id: str(j["id"]), persona: str(j["persona"]), shown: j["shown"] as? Bool ?? false))
    }

    /// Linking asks the password, then Steam's or Discord's sign-in; it comes back to this app and links it.
    func linkStart(_ prov: String, password: String) async throws {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        let j = try obj(await call("POST", "/account/\(prov)/start", body: ["auth": keys.auth, "device": "iPhone", "app": 1], pass: true))
        guard let back = try await browse(prov, j) else { return }
        let q = back.q, code = back.code
        guard let g = q[prov + "Link"], !g.isEmpty else {
            throw AppError(key: q[prov + "Linked"] == "taken" ? "this \(prov == "discord" ? "Discord" : "Steam") account is already linked to another account" : prov + "_not_linked")
        }
        _ = try await call("POST", prov == "discord" ? "/account/discord/link/grant" : "/account/steam/link", body: ["grant": g, "code": code])
    }

    func steamShow(_ shown: Bool) async throws { _ = try await call("POST", "/account/steam/shown", body: ["shown": shown]) }

    /// Unlinking Steam or Discord asks the password.
    func socialUnlink(_ prov: String, password: String) async throws {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        _ = try await call("POST", "/account/\(prov)/unlink", body: ["auth": keys.auth], pass: true)
    }

    // ---------- two-step sign-in (optional, recommended) ----------
    struct TwoFactorSetup { let secret: String; let url: URL }

    func setup2fa(password: String) async throws -> TwoFactorSetup {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        let j = try JSONSerialization.jsonObject(with: await call("POST", "/account/2fa/setup", body: ["auth": keys.auth], pass: true)) as? [String: Any] ?? [:]
        guard let secret = j["secret"] as? String, let u = (j["url"] as? String).flatMap(URL.init) else { throw AppError.serverDown }
        return TwoFactorSetup(secret: secret, url: u)
    }

    /// Confirms the first code; returns the recovery codes (shown once).
    func enable2fa(code: String) async throws -> [String] {
        let j = try JSONSerialization.jsonObject(with: await call("POST", "/account/2fa/enable", body: ["code": code.trimmingCharacters(in: .whitespaces)], pass: true)) as? [String: Any] ?? [:]
        let codes = j["codes"] as? [String] ?? []
        twoFactor = true
        recoveryLeft = codes.count
        defaults.set(true, forKey: "twoFactor")
        defaults.set(codes.count, forKey: "recoveryLeft")
        return codes
    }

    func disable2fa(password: String, code: String) async throws {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        _ = try await call("POST", "/account/2fa/disable", body: ["auth": keys.auth, "code": code.trimmingCharacters(in: .whitespaces)], pass: true)
        twoFactor = false
        recoveryLeft = 0
        defaults.set(false, forKey: "twoFactor")
        defaults.set(0, forKey: "recoveryLeft")
    }

    /// Pulls the encrypted settings bundle the PC keeps in the account and opens it here: your races come from it.
    func sync(quiet: Bool = false) async {
        if !quiet {
            busy = true
            error = nil
        }
        defer { if !quiet { busy = false } }
        do {
            let data = try await call("GET", "/account/sync")
            let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            var files = 0
            let changed = int(j["version"]) != syncVersion
            if let blob = j["blob"] as? String, !blob.isEmpty, let key = dataKey {
                let raw = try PLCrypto.gunzip(PLCrypto.open(key: key, sealed: blob, aad: PLCrypto.accountAAD))
                let all = try JSONSerialization.jsonObject(with: raw) as? [String: Any] ?? [:]
                files = all.count
                // Go writes the files as base64 strings
                if let b64 = all["races.json"] as? String, let racesData = Data(base64Encoded: b64), let a = try? JSONSerialization.jsonObject(with: racesData) as? [[String: Any]] {
                    let slim = trimRaces(a)
                    if let d = try? JSONSerialization.data(withJSONObject: slim) { save("races", d) }
                } else if all["races.json"] == nil {
                    // a bundle without races.json has no races: never keep an older copy of them
                    save("races", Data("[]".utf8))
                }
                save("drivers", (all["drivers.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
                save("notes", (all["notes.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
                save("ratings", (all["ratings.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
                await escrowUp()
            } else if (j["blob"] as? String ?? "").isEmpty {
                // an account with nothing in it yet: no races and no ratings from an earlier copy
                save("races", Data("[]".utf8))
                save("ratings", Data("{}".utf8))
                await escrowUp()
            }
            syncedFiles = files
            syncVersion = int(j["version"])
            syncUpdated = num(j["updated"]) ?? 0
            defaults.set(syncedFiles, forKey: "syncedFiles")
            defaults.set(syncVersion, forKey: "syncVersion")
            defaults.set(syncUpdated, forKey: "syncUpdated")
            if let me = try? JSONSerialization.jsonObject(with: await call("GET", "/account/me")) as? [String: Any] {
                display = str(me["display"])
                if let id = me["id"] as? String { defaults.set(id, forKey: "acctId") }
                verified = me["verified"] as? Bool ?? true
                realAdmin = me["admin"] as? Bool ?? false
                twoFactor = me["twoFactor"] as? Bool ?? false
                recoveryLeft = me["recoveryLeft"] as? Int ?? 0
                supporter = me["supporter"] as? Bool ?? false
                supporterHidden = me["supporterHidden"] as? Bool ?? false
                defaults.set(supporter, forKey: "supporter")
                defaults.set(supporterHidden, forKey: "supporterHidden")
                defaults.set(realAdmin, forKey: "admin")
                defaults.set(display, forKey: "display")
                defaults.set(verified, forKey: "verified")
                defaults.set(twoFactor, forKey: "twoFactor")
                defaults.set(recoveryLeft, forKey: "recoveryLeft")
                // only "none kept" is taken from the server: a copy that is not this phone's key must not stop this key going up
                if let e = me["escrow"] as? Bool, !e { defaults.set(false, forKey: "escrow") }
            }
            // a new version of the bundle: the races held here are dropped and read again from it (the ratings are
            // read from it each time a screen draws them)
            if changed { allRaces = []; races = [] }
            loadRaces()
            refreshTick += 1
            await publishProfileRaces()
        } catch {
            if !quiet || (error as? AppError)?.key == AppError.signedOut.key { self.error = (error as? AppError)?.key ?? error.localizedDescription }
        }
    }

    private var lastAuto = Date.distantPast
    private var nudge: Task<Void, Never>?

    /// The server said another device uploaded the account (version): read it again in a moment (bursts become one read).
    func nudged(_ version: Int) {
        guard signedIn, !demo, version == 0 || version > syncVersion else { return } // this phone's own upload, or already read
        nudge?.cancel()
        nudge = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled, let self else { return }
            self.lastAuto = Date()
            await self.sync(quiet: true)
        }
    }

    /// The app came to the screen (it opened, or came back from the background): your account, public
    /// name and races are read again by themselves, at most every 30 seconds, without a spinner.
    func syncIfDue() async {
        guard signedIn, !busy, Date().timeIntervalSince(lastAuto) > 30 else { return }
        lastAuto = Date()
        await sync(quiet: true)
    }

    private var minute: Task<Void, Never>?

    /// While the app is on the screen it reads the account once a minute (the same read as syncIfDue), like the PC and
    /// the web; stopMinuteSync ends it when the app goes to the background.
    func startMinuteSync() {
        guard minute == nil else { return }
        minute = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled, let self else { return }
                // a read made meanwhile (the nudge, coming back) counts: never two within the minute
                guard self.signedIn, !self.busy, !self.demo, Date().timeIntervalSince(self.lastAuto) >= 55 else { continue }
                self.lastAuto = Date()
                await self.sync(quiet: true)
            }
        }
    }

    func stopMinuteSync() {
        minute?.cancel()
        minute = nil
    }

    // only what the phone shows, newest first: races.json also has braking points and more
    /// Text saved with the wrong encoding by an older PC ("AutÃ³dromo"): only the damaged pieces are repaired.
    private func fixTxt(_ s: String) -> String {
        guard s.unicodeScalars.contains(where: { $0.value >= 0xC2 && $0.value <= 0xEF }) else { return s }
        var out = ""
        var buf: [UInt8] = []
        func flush() {
            if !buf.isEmpty {
                if let d = String(bytes: buf, encoding: .utf8) { out += d } else { out += String(String.UnicodeScalarView(buf.map { Unicode.Scalar($0) })) }
                buf = []
            }
        }
        let scalars = Array(s.unicodeScalars)
        var i = 0
        while i < scalars.count {
            let v = scalars[i].value
            let need = v >= 0xC2 && v <= 0xDF ? 1 : v >= 0xE0 && v <= 0xEF ? 2 : 0
            if need > 0 && i + need < scalars.count && (1...need).allSatisfy({ scalars[i + $0].value >= 0x80 && scalars[i + $0].value <= 0xBF }) {
                buf = (0...need).map { UInt8(scalars[i + $0].value) }
                flush()
                i += need + 1
            } else {
                out.unicodeScalars.append(scalars[i])
                i += 1
            }
        }
        return out
    }

    private func trimRaces(_ a: [[String: Any]]) -> [[String: Any]] {
        a.sorted { (num($0["when"]) ?? 0) > (num($1["when"]) ?? 0) }
            .prefix(60)
            .map { r0 -> [String: Any] in
                var r = r0
                // the race's incident total, like the web: the largest of the report's total, the laps' and the events'
                let laps0 = r["laps"] as? [[String: Any]] ?? []
                let fromLaps: Int = laps0.reduce(0) { $0 + int($1["i"]) }
                let fromEv: Int = (r["incidents"] as? [[String: Any]] ?? []).reduce(0) { $0 + max(int($1["pts"]), int($1["p"])) }
                r["inc"] = max(int(r["inc"]), fromLaps, fromEv)
                r["brakes"] = nil
                r["incidents"] = nil
                r["laps"] = laps0.map { l -> [String: Any] in
                    var o: [String: Any] = ["n": l["n"] ?? 0, "t": l["t"] ?? 0, "p": l["p"] ?? 0, "i": l["i"] ?? 0, "pit": l["pit"] ?? false, "cut": l["cut"] ?? false]
                    if let d = l["drv"] as? String, !d.isEmpty { o["drv"] = d }
                    return o
                }
                return r
            }
    }

    func loadRaces() {
        if demo { allRaces = Demo.races(); races = allRaces; return }
        guard let d = saved("races"), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { allRaces = []; races = []; return }
        allRaces = a.map { r in
            Race(
                id: str(r["id"]), when: num(r["when"]) ?? 0, track: fixTxt(str(r["track"])), car: fixTxt(str(r["car"])), official: r["official"] as? Bool ?? false,
                start: int(r["start"]), finish: int(r["finish"]), field: int(r["field"]),
                inc: max(int(r["inc"]), (r["laps"] as? [[String: Any]] ?? []).reduce(0) { $0 + int($1["i"]) }), best: pos(r["best"]),
                fieldBest: pos(r["fieldBest"]), avg: pos(r["avg"]), consistency: pos(r["consistency"]), pits: int(r["pits"]), fuelUsed: pos(r["fuelUsed"]),
                ir: int(r["ir"]), irChange: int(r["irChange"]), sof: int(r["sof"]), dnf: r["dnf"] as? Bool ?? false,
                laps: (r["laps"] as? [[String: Any]] ?? []).map { RaceLap(n: int($0["n"]), time: num($0["t"]) ?? 0, pos: int($0["p"]), inc: int($0["i"]), pit: $0["pit"] as? Bool ?? false, cut: $0["cut"] as? Bool ?? false, drv: fixTxt(str($0["drv"]))) },
                results: (r["results"] as? [[String: Any]] ?? []).map { x -> RaceResult in
                    // an offline race has only you as a real driver: everyone else there is an AI driver
                    let me = x["me"] as? Bool ?? false
                    return RaceResult(pos: int(x["cpos"]) > 0 ? int(x["cpos"]) : int(x["pos"]), name: fixTxt(str(x["name"])), ir: int(x["ir"]), best: pos(x["best"]), inc: int(x["inc"]), laps: int(x["laps"]), k: str(x["k"]), me: me,
                                      ai: !me && ((x["ai"] as? Bool ?? false) || (isAIRace(r) && int(r["subsession"]) == 0)),
                                      cc: countryCode(str(x["cc"]).isEmpty ? str(x["flair"]) : str(x["cc"])))
                }.sorted { $0.pos < $1.pos },
                cat: r["cat"] as? String,
                drinks: (r["drinks"] as? [String] ?? []).map { fixTxt($0) }.filter { !$0.isEmpty },
                ai: isAIRace(r), game: str(r["game"]).isEmpty ? "iracing" : str(r["game"])
            )
        }
        races = allRaces.filter { $0.game == game }
    }

    func logout() async {
        _ = try? await call("POST", "/account/logout")
        clear()
        error = nil
    }

    func devices() async throws -> Got<[Device]> {
        let j = try JSONSerialization.jsonObject(with: await call("GET", "/account/sessions")) as? [String: Any] ?? [:]
        return Got(data: (j["sessions"] as? [[String: Any]] ?? []).map { Device(id: str($0["id"]), device: str($0["device"]), lastSeen: num($0["lastSeen"]) ?? 0, current: $0["current"] as? Bool ?? false) })
    }

    func revoke(_ id: String) async throws {
        _ = try await call("POST", "/account/sessions/revoke", body: ["id": id])
    }

    // ---------- Discord: link it (Discord's sign-in, in the browser), show it on your profile, unlink it ----------
    func discord() async throws -> Got<DiscordLink> {
        let j = try JSONSerialization.jsonObject(with: await call("GET", "/account/discord")) as? [String: Any] ?? [:]
        return Got(data: DiscordLink(linked: j["linked"] as? Bool ?? false, id: str(j["id"]), handle: str(j["handle"]), shown: j["shown"] as? Bool ?? false, oauth: j["oauth"] as? Bool ?? false,
                                     login: j["login"] as? Bool ?? true))
    }

    func discordShow(_ shown: Bool) async throws { _ = try await call("POST", "/account/discord/show", body: ["shown": shown]) }


    // ---------- your laps (uploaded by PitlaneHQ.exe) ----------

    // session and lap ids look like acct_<id>:<…>; the ':' stays as it is in the path
    private func idPath(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    /// Your sessions of the chosen game, asked like the web (limit=100&game=…): only this account's, only with laps.
    func sessions() async throws -> Got<[CloudSession]> {
        let gm = game
        if !gameAsked { noteStats(await gameCounts()) }
        if demo { return Got(data: Demo.sessions().filter { $0.game == gm && $0.laps > 0 }) }
        let g = try await cachedGet("/api/sessions?limit=100&game=" + gm)
        return Got(data: parseSessions(g.data).filter { $0.game == gm && $0.laps > 0 && mine($0.id) }, stale: g.stale)
    }

    /// Per game: how many sessions you have and the last one's date (the sheet that asks which game to see), like the web's.
    private func gameCounts() async -> [String: (n: Int, last: Double)] {
        var st: [String: (n: Int, last: Double)] = [:]
        for g in games {
            var l: [CloudSession] = []
            if demo { l = Demo.sessions().filter { $0.game == g && $0.laps > 0 } }
            else if let got = try? await cachedGet("/api/sessions?limit=200&game=" + g) { l = parseSessions(got.data).filter { $0.game == g && $0.laps > 0 && mine($0.id) } }
            st[g] = (l.count, l.map(\.started).max() ?? 0)
        }
        return st
    }

    /// A session of another account (an admin's view of someone else's) never counts as yours: ids are "acct_<id>:…".
    private func mine(_ id: String) -> Bool {
        let me = defaults.string(forKey: "acctId") ?? ""
        guard !me.isEmpty, id.hasPrefix("acct_") else { return true }
        let safe = String(me.map { $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) ? $0 : "_" })
        return id.hasPrefix("acct_" + safe + ":")
    }

    /// Home's four numbers of the month for the chosen game, counted by the server over every session of the account
    /// (the same numbers as the PC and the web): from the start of this month on the phone's clock, in its time zone.
    func monthStats() async throws -> Got<MonthStats> {
        let gm = game
        if demo { return Got(data: localMonthStats(sessions: Demo.sessions().filter { $0.game == gm }, races: Demo.races().filter { $0.game == gm })) }
        let cal = Calendar.current
        let m0 = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let from = Int64(m0.timeIntervalSince1970 * 1000)
        let tz = TimeZone.current.secondsFromGMT() / 60
        // "+120" with its plus sign encoded, never read as a space
        let g = try await cachedGet("/api/sessions/summary?from=\(from)&tz=" + (tz >= 0 ? "%2B\(tz)" : "\(tz)") + "&game=" + gm)
        let j = g.data as? [String: Any] ?? [:]
        var best: MonthBest?
        if let b = j["best"] as? [String: Any], int(b["pos"]) > 0 {
            best = MonthBest(pos: int(b["pos"]), field: int(b["field"]), inClass: (b["cls"] as? Bool) ?? ((b["cls"] as? NSNumber)?.intValue == 1),
                             track: fixTxt(str(b["track"])), car: fixTxt(str(b["car"])), started: num(b["started"]) ?? 0)
        }
        let secs = num(j["secs"]) ?? 0
        return Got(data: MonthStats(laps: int(j["laps"]), secs: secs > 0 ? secs : 0, sessions: int(j["sessions"]), days: int(j["days"]),
                                    races: int(j["races"]), top5: int(j["top5"]), best: best), stale: g.stale)
    }

    private func parseSessions(_ data: Any) -> [CloudSession] {
        (data as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            let kind = str(s["kind"]), game = s["game"] as? String
            // a session against iRacing's AI the server has no flag for (recorded by an older agent): an iRacing session
            // without a subsession (id "t-…" after the account's "acct_…:" prefix) that is not a test is a single-player
            // session, so against the AI
            let offlineAI = (game == nil || game == "iracing") && (id.split(separator: ":").last ?? "").hasPrefix("t-") && !kind.lowercased().contains("test")
            return CloudSession(id: id, started: num(s["started"]) ?? 0, track: str(s["track"]), trackConfig: str(s["track_config"]), car: str(s["car"]), kind: kind, laps: int(s["laps"]), best: pos(s["best"]),
                                cat: s["cat"] as? String, lic: s["lic"] as? String,
                                drvs: str(s["drvs"]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, ai: int(s["ai"]) == 1 || offlineAI,
                                game: (game ?? "").isEmpty ? "iracing" : game!, cls: clsOf(s),
                                pos: posInt(s["pos"]), field: posInt(s["field"]), inClass: (s["cls"] as? Bool) ?? ((s["cls"] as? NSNumber)?.intValue == 1))
        }
    }

    func laps(_ sessionId: String) async throws -> Got<[CloudLap]> {
        if demo { return Got(data: Demo.laps(sessionId)) }
        let g = try await cachedGet("/api/sessions/" + idPath(sessionId))
        let a = (g.data as? [String: Any])?["laps"] as? [[String: Any]] ?? []
        return Got(data: a.map { l in
            CloudLap(id: str(l["id"]), n: int(l["n"]), time: num(l["time"]) ?? 0, valid: ((l["valid"] as? NSNumber)?.intValue ?? 1) == 1, sectors: doubles(l["sectors"]), inc: int(l["inc"]), drv: str(l["drv"]))
        }, stale: g.stale)
    }

    private func parseTrace(_ j: Any?) -> Trace? {
        guard let t = j as? [String: Any], let d = t["d"] as? [[NSNumber]], !d.isEmpty else { return nil }
        var tr = Trace(bin: num(t["bin"]) ?? 10, rows: d.map { $0.map(\.doubleValue) })
        if let x = t["x"] as? [NSNumber], let y = t["y"] as? [NSNumber], x.count == d.count, y.count == d.count {
            tr.x = x.map(\.doubleValue)
            tr.y = y.map(\.doubleValue)
            if let g = t["g"] as? [NSNumber], g.count == 2 { tr.g = g.map(\.doubleValue) }  // the path's origin when it comes from the game's position
        }
        if let inc = t["inc"] as? [NSNumber] { tr.inc = inc.map(\.doubleValue) }
        if let k = t["incK"] as? [String] { tr.incK = k }
        if let f = t["f"] as? [String] { tr.f = f }
        return tr
    }

    func lapTrace(_ lapId: String) async throws -> Trace? {
        if demo { return Demo.trace(lapId) }
        return parseTrace((try await cachedGet("/api/laps/" + idPath(lapId)).data as? [String: Any])?["trace"])
    }

    func bests() async throws -> Got<[PersonalBest]> {
        if demo { return Got(data: Demo.bests()) }
        let g = try await cachedGet("/api/bests")
        return Got(data: (g.data as? [[String: Any]] ?? []).compactMap { b in
            let gm = str(b["game"]).isEmpty ? "iracing" : str(b["game"])
            guard gm == self.game else { return nil }
            let lap = str(b["bestLapId"]), ses = str(b["bestSessionId"])
            return PersonalBest(track: str(b["track"]), trackConfig: str(b["track_config"]), car: str(b["car"]), best: num(b["best"]) ?? 0, laps: int(b["laps"]),
                                last: num(b["last"]) ?? 0, bestLapId: lap.isEmpty ? nil : lap, bestSessionId: ses.isEmpty ? nil : ses, game: gm)
        }.sorted { $0.last > $1.last }, stale: g.stale)
    }

    // ---------- community ----------

    func combos(game gm: String? = nil) async throws -> Got<[Combo]> {
        if demo { return Got(data: Demo.combos()) }
        let g = try await cachedGet("/community/combos?game=\(gm ?? game)")
        let a = (g.data as? [String: Any])?["combos"] as? [[String: Any]] ?? []
        return Got(data: a.map { c in
            Combo(trackId: (c["trackId"] as? NSNumber)?.int64Value ?? 0, track: str(c["track"]), carId: (c["carId"] as? NSNumber)?.int64Value ?? 0, car: str(c["car"]), laps: int(c["laps"]), best: pos(c["best"]), cat: c["cat"] as? String, cls: clsOf(c))
        }, stale: g.stale)
    }

    /// The records: the fastest lap of every car and track, the newest first, with the lap it beat.
    func records() async throws -> Got<[RecordItem]> {
        if demo { return Got(data: []) }
        let gm = game
        let g = try await cachedGet("/community/records?game=\(gm)&limit=40")
        let a = (g.data as? [String: Any])?["records"] as? [[String: Any]] ?? []
        return Got(data: a.map { recordOf($0, trackId: 0, track: "", game: gm) }, stale: g.stale)
    }

    private func recordOf(_ r: [String: Any], trackId: Int64, track: String, game gm: String) -> RecordItem {
        let p = r["prev"] as? [String: Any]
        let tn = str(r["track"])
        return RecordItem(id: str(r["id"]), trackId: (r["trackId"] as? NSNumber)?.int64Value ?? trackId, track: tn.isEmpty ? track : tn,
                          carId: (r["carId"] as? NSNumber)?.int64Value ?? 0, car: str(r["car"]), cat: r["cat"] as? String,
                          time: num(r["time"]) ?? 0, created: num(r["created"]) ?? 0, alias: (r["alias"] as? String) ?? "Driver", n: int(r["n"]),
                          hasTrace: r["hasTrace"] as? Bool ?? false, mine: r["mine"] as? Bool ?? false, prof: r["prof"] as? Bool ?? false, sup: r["sup"] as? Bool ?? false,
                          prevTime: p.flatMap { pos($0["time"]) }, prevAlias: p?["alias"] as? String, cls: clsOf(r), wet: int(r["wet"]),
                          game: str(r["game"]).isEmpty ? gm : str(r["game"]))
    }

    /// One track: its layout and official turns, how many drivers and laps it has, and the record of every car on it.
    func trackPage(trackId: Int64) async throws -> Got<TrackPage> {
        let gm = game
        if demo { return Got(data: TrackPage(trackId: trackId, track: "", drivers: 0, laps: 0, layout: nil, turns: [], cars: [], game: gm)) }
        let g = try await cachedGet("/community/track?game=\(gm)&trackId=\(trackId)")
        let j = g.data as? [String: Any] ?? [:]
        var lay: ([Double], [Double])? = nil
        if let l = j["layout"] as? [String: Any], let x = (l["x"] as? [NSNumber])?.map({ $0.doubleValue }), let y = (l["y"] as? [NSNumber])?.map({ $0.doubleValue }), x.count >= 20, x.count == y.count { lay = (x, y) }
        let turns = ((j["turns"] as? [NSNumber]) ?? []).map { $0.doubleValue }.filter { $0 >= 0 && $0 < 1 }
        let name = str(j["track"])
        let tg = str(j["game"]).isEmpty ? gm : str(j["game"])
        let cars = (j["cars"] as? [[String: Any]] ?? []).map { recordOf($0, trackId: trackId, track: name, game: tg) }
        return Got(data: TrackPage(trackId: trackId, track: name, drivers: int(j["drivers"]), laps: int(j["laps"]), layout: lay, turns: turns, cars: cars, game: tg), stale: g.stale)
    }

    /// One line per driver: their best lap.
    /// The card of a car: what it does on every track it was driven on (its hardest braking, where the fast
    /// drivers shift up, its top speed), learnt by the server from its laps; nil when the server has no laps of it.
    func carCard(carId: Int64, game gm: String? = nil) async throws -> [String: Any]? {
        if demo { return nil }
        guard let j = try await cachedGet("/community/car?game=\(gm ?? game)&carId=\(carId)").data as? [String: Any], ((j["n"] as? NSNumber)?.intValue ?? 0) > 0 else { return nil }
        return j
    }
    /// A track's layout drawn by the community from clean laps (x/y of n points along the lap), nil when none yet.
    func trackLayout(trackId: Int64, game gm: String? = nil) async -> ([Double], [Double])? {
        if demo || trackId <= 0 { return nil }
        guard let j = try? await cachedGet("/community/trackmaps?game=\(gm ?? game)&trackId=\(trackId)").data as? [String: Any],
              let x = j["x"] as? [Any], let y = j["y"] as? [Any], x.count >= 20, x.count == y.count else { return nil }
        return (x.map { ($0 as? NSNumber)?.doubleValue ?? 0 }, y.map { ($0 as? NSNumber)?.doubleValue ?? 0 })
    }
    /// The model's references for a car and track (`/community/model`): the record (the fastest lap really driven) and the
    /// next level for a lap of `lapTime` (the driver just ahead), each a trace every 5 m with its time and, when known, its line.
    /// `cmp` is lap A's tyre compound: the server gives that compound's references when it has them apart.
    /// recXY and lvlXY: the path the web's analysis gives each reference (pitwall-model.js: the record's idealXY, else the
    /// fastest line lineXY; the next level's own, else lineXY), whatever its length, with its origin g.
    func modelRefs(trackId: Int64, carId: Int64, lapTime: Double, game gm: String? = nil, cmp: Int = 0) async -> (rec: (Trace, Double)?, lvl: (Trace, Double)?, corners: [CornerCard], recXY: LapPath?, lvlXY: LapPath?) {
        if demo || trackId <= 0 || carId <= 0 { return (nil, nil, [], nil, nil) }
        guard let m = try? await cachedGet("/community/model?game=\(gm ?? game)&trackId=\(trackId)&carId=\(carId)&cmp=\(cmp)").data as? [String: Any] else { return (nil, nil, [], nil, nil) }
        // the corner card: where the fastest drivers here brake and how fast they take each corner of the record lap
        let cards: [CornerCard] = ((m["corners"] as? [[String: Any]]) ?? []).map { o in
            func d(_ k: String) -> Double { (o[k] as? NSNumber)?.doubleValue ?? 0 }
            return CornerCard(d: d("d"), apex: d("apex"), b0: d("b0"), b1: d("b1"), v0: d("v0"), v1: d("v1"), n: (o["n"] as? NSNumber)?.intValue ?? 0, spread: d("spread"))
        }
        // the model's bins are [speed, time, throttle, brake, gear, steering]; a trace row is [speed, throttle, brake, gear, steering, time]
        func row(_ b: [Any]) -> [Double] {
            let v = b.map { ($0 as? NSNumber)?.doubleValue ?? 0 }
            func at(_ i: Int) -> Double { i < v.count ? v[i] : 0 }
            return [at(0), at(2), at(3), at(4), 0, at(1)]
        }
        func nums(_ a: Any?) -> [Double]? { (a as? [Any])?.map { ($0 as? NSNumber)?.doubleValue ?? 0 } }
        // a path with its origin g when it comes from the game's position (the apps put two paths in one frame by it)
        func xy(_ o: Any?, _ n: Int) -> (x: [Double], y: [Double], g: [Double]?)? {
            guard let o = o as? [String: Any], let x = nums(o["x"]), let y = nums(o["y"]), x.count == n, y.count == n else { return nil }
            let g = nums(o["g"])
            return (x, y, g != nil && g!.count == 2 ? g : nil)
        }
        func num0(_ o: [String: Any], _ k: String) -> Double { (o[k] as? NSNumber)?.doubleValue ?? 0 }
        // a path as the web takes it: x and y of any length (the line of another lap), its origin g
        func path(_ o: Any?) -> LapPath? {
            guard let o = o as? [String: Any], let x = nums(o["x"]), let y = nums(o["y"]) else { return nil }
            let g = nums(o["g"])
            return LapPath(x: x, y: y, g: g != nil && g!.count == 2 ? g : nil)
        }
        let lineXY = path(m["lineXY"])
        var recXY: LapPath? = nil
        var lvlXY: LapPath? = nil
        var rec: (Trace, Double)? = nil
        if let ideal = m["ideal"] as? [[Any]], ideal.count > 40, num0(m, "idealTime") > 0 {
            let rows = ideal.map(row)
            var tr = Trace(bin: 5, rows: rows)
            if let p = xy(m["idealXY"], rows.count) ?? xy(m["lineXY"], rows.count) { tr.x = p.x; tr.y = p.y; tr.g = p.g }
            rec = (tr, num0(m, "idealTime"))
            recXY = path(m["idealXY"]) ?? lineXY
        }
        var lvl: (Trace, Double)? = nil
        let nb = (m["nb"] as? NSNumber)?.intValue ?? 0
        if let lad = m["ladder"] as? [[String: Any]], !lad.isEmpty, lapTime > 0 {
            // the first level this lap is within, then down to one really faster than it
            var i = lad.firstIndex { lapTime <= num0($0, "upTo") } ?? lad.count - 1
            while i > 0 && !(num0(lad[i], "time") < lapTime * 0.997) { i -= 1 }
            let x = lad[i], tm = num0(x, "time")
            if let raw = x["bins"] as? [[Any]], raw.count > 20, tm > 0, tm < lapTime - 0.001 {
                // its bins are every 10 m: each one and the point between it and the next make the 5 m rows
                var rows: [[Double]] = []
                for k in raw.indices {
                    let a = row(raw[k])
                    rows.append(a)
                    if k + 1 < raw.count {
                        let nx = row(raw[k + 1])
                        rows.append([(a[0] + nx[0]) / 2, a[1], a[2], a[3], 0, (a[5] + nx[5]) / 2])
                    } else { rows.append(a) }
                }
                let cut = nb > 0 ? Array(rows.prefix(nb)) : rows
                var tr = Trace(bin: 5, rows: cut)
                if let rg = nums(x["g"]), rg.count == 2 { tr.g = rg }
                if let rx = nums(x["x"]), let ry = nums(x["y"]), rx.count >= 6, rx.count == ry.count {
                    var ox: [Double] = [], oy: [Double] = []
                    for k in rx.indices {
                        let n = k + 1 < rx.count ? k + 1 : k
                        ox.append(rx[k]); ox.append((rx[k] + rx[n]) / 2)
                        oy.append(ry[k]); oy.append((ry[k] + ry[n]) / 2)
                    }
                    if ox.count >= cut.count { tr.x = Array(ox.prefix(cut.count)); tr.y = Array(oy.prefix(cut.count)) }
                    lvlXY = LapPath(x: nb > 0 ? Array(ox.prefix(nb)) : ox, y: nb > 0 ? Array(oy.prefix(nb)) : oy, g: tr.g)
                }
                if lvlXY == nil { lvlXY = lineXY }
                if tr.x == nil, let p = xy(m["lineXY"], cut.count) { tr.x = p.x; tr.y = p.y; tr.g = p.g }
                lvl = (tr, tm)
            }
        }
        return (rec, lvl, cards, recXY, lvlXY)
    }

    /// The laps of a session with their traces, in one call (/api/sessions/:id?traces=1), as the web's coach takes them
    /// (laps with a trace and a time): whether each is valid, and its trace. Empty when they cannot be read; never kept on
    /// the phone (each lap's own trace is).
    func sessionTraces(_ sessionId: String) async -> [(Bool, Trace)] {
        if demo { return Demo.laps(sessionId).compactMap { l in Demo.trace(l.id).map { (l.valid, $0) } } }
        guard let d = try? await call("GET", "/api/sessions/" + idPath(sessionId) + "?traces=1"),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any], let a = o["laps"] as? [[String: Any]] else { return [] }
        return a.filter { ($0["time"] as? NSNumber)?.doubleValue ?? 0 > 0 }.compactMap { l in
            parseTrace(l["trace"]).map { (((l["valid"] as? NSNumber)?.intValue ?? 0) == 1, $0) }
        }
    }
    /// A thumb on one of the coach's tips (1 up, -1 down, 0 takes it back), kept with the account on the server (coachtips.js).
    func rateTip(trackId: Int64, carId: Int64, sid: String, started: Double, n: Int, apexM: Int, kind: String, cls: String, up: Int, game gm: String? = nil) async {
        if demo || trackId <= 0 || carId <= 0 { return }
        _ = try? await call("POST", "/community/coach/rate", body: ["game": gm ?? game, "trackId": trackId, "carId": carId, "sid": sid, "started": Int64(started), "n": n, "apex": apexM, "kind": kind, "cls": cls, "up": up])
    }
    /// A track's official turns (T1 … Tn as fractions of the lap from the line), placed by an admin on its map.
    /// What the coach learnt from everyone's tips (coachtips.js): the tips an admin turned off ("kind|cls"), how many drivers
    /// each bucket helped and whether a tip may say it; nil without a connection.
    func coachInfo() async -> CoachInfo? {
        if demo { return nil }
        guard let j = try? await cachedGet("/community/coach/weights").data as? [String: Any] else { return nil }
        let off = Set((j["off"] as? [String]) ?? [])
        var conf: [String: (Int, Int)] = [:], w: [String: Double] = [:], ask: [String: Double] = [:]
        for b in (j["buckets"] as? [[String: Any]]) ?? [] {
            let k = "\(str(b["kind"]))|\(str(b["cls"]))"
            conf[k] = (int(b["win"]), int(b["n"]))
            let bw = (b["w"] as? NSNumber)?.doubleValue ?? 0
            w[k] = bw > 0 ? bw : 1
            if let a = (b["ask"] as? NSNumber)?.doubleValue, a > 0 { ask[k] = a }
        }
        return CoachInfo(off: off, conf: conf, confidence: (j["confidence"] as? Bool) ?? false, min: (j["min"] as? NSNumber)?.intValue ?? 30, w: w, ask: ask)
    }
    /// The driver's own memory: the kinds of tip that repeat across their tracks (habits), the most repeated first.
    func coachHabits() async -> [Habit] {
        if demo { return [] }
        guard let j = try? await cachedGet("/community/coach/me").data as? [String: Any], let a = j["habits"] as? [[String: Any]] else { return [] }
        return a.map { Habit(kind: str($0["kind"]), tracks: int($0["tracks"]), sessions: int($0["sessions"])) }
    }
    /// The driver's own weights of the coach's tips, by "kind|cls" (/community/coach/me), for the plan's order.
    func coachMeWeights() async -> [String: Double] {
        if demo { return [:] }
        guard let j = try? await cachedGet("/community/coach/me").data as? [String: Any], let w = j["w"] as? [String: Any] else { return [:] }
        return w.compactMapValues { ($0 as? NSNumber)?.doubleValue }
    }
    func turns(trackId: Int64, game gm: String? = nil) async -> [Double] {
        if demo || trackId <= 0 { return [] }
        guard let j = try? await cachedGet("/community/turns?game=\(gm ?? game)&trackId=\(trackId)").data as? [String: Any], let a = j["turns"] as? [Any] else { return [] }
        return a.compactMap { ($0 as? NSNumber)?.doubleValue }.filter { $0 >= 0 && $0 < 1 }
    }
    /// The pit lane of a track, learnt from laps through the pits: [5 m point of a lap of n points, metres to the left].
    func pitLane(trackId: Int64, game gm: String? = nil) async -> PitLane? {
        if demo || trackId <= 0 { return nil }
        guard let j = try? await cachedGet("/community/pitlane?game=\(gm ?? game)&trackId=\(trackId)").data as? [String: Any],
              let a = j["pts"] as? [[Any]], let n = (j["n"] as? NSNumber)?.intValue, n > 0 else { return nil }
        let pts: [(Int, Double)] = a.compactMap { q in
            guard q.count == 2, let i = (q[0] as? NSNumber)?.intValue, let v = (q[1] as? NSNumber)?.doubleValue else { return nil }
            return (i, v)
        }
        return pts.count >= 10 ? PitLane(n: n, pts: pts) : nil
    }
    /// Le Mans Ultimate's class of each car board the server named (its cls), for "This car / Whole class"
    private var boardCls: [String: String] = [:]
    /// "Whole class" chosen on a Le Mans Ultimate leaderboard, kept while the app runs
    @Published var boardWhole = false
    func boardClass(trackId: Int64, carId: Int64) -> String? { game == "lmu" ? boardCls["\(game)|\(trackId)|\(carId)"] : nil }

    /// A leaderboard as chosen: the car's, or in Le Mans Ultimate with "Whole class" each driver's best of any car of its class here.
    func board(trackId: Int64, carId: Int64) async throws -> Got<[CommunityLap]> {
        if boardWhole, let c = boardClass(trackId: trackId, carId: carId) { return try await classBoard(trackId: trackId, cls: c) }
        let g = try await leaderboard(trackId: trackId, carId: carId)
        if boardWhole, let c = boardClass(trackId: trackId, carId: carId) { return try await classBoard(trackId: trackId, cls: c) }
        return g
    }

    /// Le Mans Ultimate's class board: each driver's best lap of any car of the class on the track, with its car.
    func classBoard(trackId: Int64, cls: String) async throws -> Got<[CommunityLap]> {
        if demo { return Got(data: []) }
        return boardOf(try await cachedGet("/community/laps?game=\(game)&trackId=\(trackId)&cls=" + (cls.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? cls)))
    }

    func leaderboard(trackId: Int64, carId: Int64) async throws -> Got<[CommunityLap]> {
        if demo { return Got(data: Demo.board(trackId: trackId, carId: carId)) }
        let g = try await cachedGet("/community/laps?game=\(game)&trackId=\(trackId)&carId=\(carId)")
        if let c = (g.data as? [String: Any])?["cls"] as? String, !c.isEmpty { boardCls["\(game)|\(trackId)|\(carId)"] = c }
        return boardOf(g)
    }

    private func boardOf(_ g: Got<Any>) -> Got<[CommunityLap]> {
        var seen = Set<String>()
        var out: [CommunityLap] = []
        for l in (g.data as? [String: Any])?["laps"] as? [[String: Any]] ?? [] {
            let alias = (l["alias"] as? String) ?? "Driver"
            guard let t = num(l["time"]) else { continue }
            if alias != "Anonymous" {
                if seen.contains(alias) { continue }
                seen.insert(alias)
            }
            out.append(CommunityLap(id: str(l["id"]), alias: alias, time: t, created: num(l["created"]) ?? 0, hasTrace: (l["hasTrace"] as? Bool) ?? false, sectors: doubles(l["sectors"]), mine: (l["mine"] as? Bool) ?? false,
                                    lic: l["lic"] as? String, prof: (l["prof"] as? Bool) ?? false, sup: (l["sup"] as? Bool) ?? false, field: (l["field"] as? Bool) ?? false,
                                    car: (l["car"] as? String).flatMap { $0.isEmpty ? nil : $0 }, wet: int(l["wet"])))
        }
        return Got(data: out.sorted { $0.time < $1.time }, stale: g.stale)
    }

    // the admin profile: accounts, and shared items with who really uploaded them
    func adminList(_ kind: String) async throws -> [[String: Any]] {
        if kind == "status" { return [try await adminStatus()] }
        let j = try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/" + kind)) as? [String: Any]
        let key = ["users": "users", "sessions": "sessions", "blocked": "blocked"][kind] ?? "items"
        return j?[key] as? [[String: Any]] ?? []
    }
    func adminDeleteUser(_ id: String) async throws { _ = try await call("DELETE", "/community/admin/users/" + idPath(id)) }
    /// The owner of Pitlane HQ gives or takes away the supporter badge.
    func adminSupporter(_ id: String, _ on: Bool) async throws { _ = try await call("POST", "/community/admin/supporter", body: ["id": id, "on": on]) }
    /// "In Pitlane HQ since" by hand (nil: the day the account was created)
    func adminSince(_ id: String, _ since: Double?) async throws { _ = try await call("POST", "/community/admin/since", body: ["id": id, "since": since.map { $0 as Any } ?? NSNull()]) }
    /// the admin tools: "models" (rebuild the coach models) or "unlock" (unblock the sign-ins)
    func adminTool(_ tool: String) async throws { _ = try await call("POST", "/community/admin/" + tool, body: tool == "unlock" ? (["all": true] as [String: Any]) : [:]) }
    /// help with an account: "verify", "2fa-off", "signout", "unlink-driver" (with the game) or "rename" (with the new public name)
    func adminAccount(_ id: String, _ act: String, name: String? = nil) async throws { _ = try await call("POST", "/community/admin/users/" + idPath(id) + "/" + act, body: name.map { ["name": $0] as [String: Any] } ?? [:]) }
    /// unblock one entry ("k") or one account's sign-in ("account")
    func adminUnlock(_ key: String, _ value: String) async throws { _ = try await call("POST", "/community/admin/unlock", body: [key: value]) }
    /// A supporter hides (or shows again) their own badge.
    func setBadgeHidden(_ hidden: Bool) async throws { _ = try await call("POST", "/community/profile/badge", body: ["hidden": hidden]) }

    /// A driver's profile, from one of their laps on a leaderboard, or yours (lapId nil).
    func profile(_ lapId: String?) async throws -> DriverProfile {
        if demo { return Demo.profile(lapId) }
        // "acct:<id>": an account's profile, from the admin profile
        let q = (lapId.map { $0.hasPrefix("acct:") ? "id=" + String($0.dropFirst(5)) : "lap=" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? "me=1") + "&tz=\(-TimeZone.current.secondsFromGMT() / 60)"
        let j = (try JSONSerialization.jsonObject(with: await call("GET", "/community/profile?" + q, auth: token != nil)) as? [String: Any]) ?? [:]
        let races = (j["races"] as? [[String: Any]] ?? []).map { r in
            ProfileRace(when: num(r["when"]) ?? 0, track: fixTxt(str(r["track"])), car: fixTxt(str(r["car"])), cat: r["cat"] as? String, lic: r["lic"] as? String, official: r["official"] as? Bool ?? false,
                        start: int(r["start"]), finish: int(r["finish"]), field: int(r["field"]), inc: int(r["inc"]), best: pos(r["best"]), irChange: int(r["irChange"]), dnf: r["dnf"] as? Bool ?? false)
        }
        let laps = (j["laps"] as? [[String: Any]] ?? []).map { x in
            ProfileLap(track: fixTxt(str(x["track"])), car: fixTxt(str(x["car"])), time: num(x["time"]) ?? 0, created: num(x["created"]) ?? 0, cat: x["cat"] as? String, lic: x["lic"] as? String, anon: x["anon"] as? Bool ?? false,
                       trackId: (x["trackId"] as? NSNumber)?.int64Value ?? 0, carId: (x["carId"] as? NSNumber)?.int64Value ?? 0, pos: int(x["pos"]), of: int(x["of"]))
        }
        return DriverProfile(name: (j["name"] as? String) ?? "Driver", since: num(j["since"]) ?? 0, mine: j["mine"] as? Bool ?? false, admin: j["admin"] as? Bool ?? false, anonymous: j["anonymous"] as? Bool ?? false,
                             supporter: j["supporter"] as? Bool ?? false, supporterHidden: j["supporterHidden"] as? Bool ?? false, lics: j["lics"] as? [String: String] ?? [:], races: races, laps: laps,
                             days: (j["days"] as? [String: Any] ?? [:]).mapValues { int($0) },
                             discordId: str((j["discord"] as? [String: Any])?["id"]), discordHandle: str((j["discord"] as? [String: Any])?["handle"]))
    }

    /// The league hub: the posts (with the views and clicks of yours), post one or edit yours, remove yours.
    @Published var leagueLimit = LeagueLimit()
    func leagues() async throws -> [League] {
        let gm = game
        let j = (try JSONSerialization.jsonObject(with: await call("GET", "/community/leagues?game=\(gm)")) as? [String: Any]) ?? [:]
        let lim = j["limits"] as? [String: Any] ?? [:]
        leagueLimit = LeagueLimit(limit: j["limit"] == nil ? 3 : int(j["limit"]), supporter: j["supporter"] as? Bool ?? false,
                                  free: lim["free"] == nil ? 3 : int(lim["free"]), supporterLimit: lim["supporter"] == nil ? 10 : int(lim["supporter"]))
        return (j["leagues"] as? [[String: Any]] ?? []).map { x in
            League(id: str(x["id"]), name: fixTxt(str(x["name"])), about: fixTxt(str(x["about"])), cat: x["cat"] as? String, discord: str(x["discord"]), web: str(x["web"]), schedule: str(x["schedule"]),
                   cars: fixTxt(str(x["cars"])), lang: str(x["lang"]), mine: x["mine"] as? Bool ?? false, by: str(x["by"]),
                   cats: x["cats"] as? [String] ?? [], days: (x["days"] as? [NSNumber] ?? []).map { $0.intValue }, time: str(x["time"]), tz: str(x["tz"]), open: x["open"] as? Bool ?? true,
                   views: x["views"] == nil ? -1 : int(x["views"]), clicks: x["clicks"] == nil ? -1 : int(x["clicks"]), created: num(x["created"]) ?? 0, updated: num(x["updated"]) ?? 0,
                   game: str(x["game"]).isEmpty ? gm : str(x["game"]))
        }
    }
    func saveLeague(_ id: String?, _ l: League) async throws {
        let path = "/community/leagues" + (id.map { "/" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? "")
        _ = try await call("POST", path, body: ["name": l.name, "about": l.about, "cats": l.cats, "days": l.days, "time": l.time, "tz": l.tz, "open": l.open,
                                              "discord": l.discord, "web": l.web, "schedule": l.schedule, "cars": l.cars, "lang": l.lang, "game": l.game])
    }
    func deleteLeague(_ id: String) async throws {
        _ = try await call("POST", "/community/leagues/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id), body: ["delete": true])
    }
    /// A post opened (view) or one of its links pressed (discord, web): the server counts it once per driver and
    /// day, never your own post.
    func leagueHit(_ id: String, _ kind: String, mine: Bool) {
        if mine || demo { return }
        let path = "/community/leagues/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id) + "/hit"
        Task { _ = try? await call("POST", path, body: ["kind": kind]) }
    }
    /// Your post's last 14 days of views and clicks.
    func leagueDays(_ id: String) async throws -> [LeagueDay] {
        let j = (try JSONSerialization.jsonObject(with: await call("GET", "/community/leagues/" + (id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id))) as? [String: Any]) ?? [:]
        return (j["days"] as? [[String: Any]] ?? []).map { LeagueDay(day: str($0["day"]), views: int($0["views"]), clicks: int($0["clicks"])) }
    }

    /// Your profile's recent races: a summary of your own result in each (the race history itself stays encrypted).
    func publishProfileRaces() async {
        guard !demo, signedIn, let d = saved("races"), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return }
        let cats = ["oval": "oval", "dirtoval": "dirt_oval", "dirtroad": "dirt_road", "formulacar": "formula_car", "formula": "formula_car", "sportscar": "sports_car"]
        let list: [[String: Any]] = a.filter { int($0["finish"]) > 0 && (num($0["when"]) ?? 0) > 0 && !($0["partial"] as? Bool ?? false) && ($0["drinks"] as? [Any] ?? []).isEmpty && !isAIRace($0) }
            .sorted { (num($0["when"]) ?? 0) > (num($1["when"]) ?? 0) }.prefix(20).map { r -> [String: Any] in
                let me = (r["results"] as? [[String: Any]] ?? []).first { $0["me"] as? Bool ?? false }
                let rawCat = str(r["cat"]).lowercased().filter { $0.isLetter }
                let id0 = String(str(r["id"]).filter { ($0.isASCII && ($0.isLetter || $0.isNumber)) || "_.:-".contains($0) }.prefix(80))
                return ["id": id0.isEmpty ? "r\(Int(num(r["when"]) ?? 0))" : id0, "when": num(r["when"]) ?? 0, "game": str(r["game"]).isEmpty ? "iracing" : str(r["game"]),
                        "track": str(r["track"]), "car": str(r["car"]), "cat": orNull(cats[rawCat]), "lic": orNull(me?["lic"] as? String),
                        "official": r["official"] as? Bool ?? false, "start": int(r["start"]), "finish": int(r["finish"]), "field": int(r["field"]), "inc": int(r["inc"]),
                        "best": orNull(pos(r["best"])), "laps": (r["laps"] as? [Any])?.count ?? 0, "ir": int(r["ir"]), "irChange": int(r["irChange"]), "sof": int(r["sof"]), "dnf": r["dnf"] as? Bool ?? false]
            }
        guard let body = try? JSONSerialization.data(withJSONObject: list, options: [.sortedKeys]) else { return }
        let last = UserDefaults.standard.string(forKey: "profRaces") ?? ""
        let sig = String(body.count) + ":" + String(body.reduce(UInt32(2166136261)) { ($0 ^ UInt32($1)) &* 16777619 })
        if last == sig { return }
        if (try? await call("POST", "/community/profile/races", body: ["races": list])) != nil { UserDefaults.standard.set(sig, forKey: "profRaces") }
    }
    func adminStatus() async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/status")) as? [String: Any]) ?? [:]
    }
    func adminDelete(_ kind: String, _ id: String) async throws { _ = try await call("DELETE", "/community/admin/\(kind)/" + idPath(id)) }
    /// what the drivers use over the last `days` days (active users per day, devices, top features, games, versions, users)
    func adminAnalytics(_ days: Int) async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/analytics?days=\(days)")) as? [String: Any]) ?? [:]
    }
    /// what the drivers wrote with "Share your feedback" (PC and web), newest first
    func adminFeedback() async throws -> [[String: Any]] {
        let j = try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/feedback")) as? [String: Any]
        return (j?["items"] as? [[String: Any]]) ?? (j?["feedback"] as? [[String: Any]]) ?? []
    }
    /// the coach's buckets (kind × speed of corner): cases, gains, thumbs, the kinds turned off and the confidence switch
    func adminCoach() async throws -> [String: Any] {
        (try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/coach")) as? [String: Any]) ?? [:]
    }
    func adminCoachOff(_ kind: String, _ cls: String, _ off: Bool) async throws { _ = try await call("POST", "/community/admin/coach/off", body: ["kind": kind, "cls": cls, "off": off]) }
    func adminCoachConfidence(_ on: Bool) async throws { _ = try await call("POST", "/community/admin/coach/confidence", body: ["on": on]) }

    // ---------- what the drivers use: sent every 5 minutes while the app is on the screen, and when it goes away ----------
    private var usageTask: Task<Void, Never>?
    func startUsage() {
        guard usageTask == nil else { return }
        Usage.count("game:" + game)
        usageTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000_000)
                guard !Task.isCancelled, let self else { return }
                await self.sendUsage()
            }
        }
    }
    func stopUsage() {
        usageTask?.cancel()
        usageTask = nil
        Task { await sendUsage() }
    }
    /// sends what was counted (POST /community/usage) and takes off what the server got
    func sendUsage() async {
        let counts = Usage.pending
        guard !counts.isEmpty, signedIn, !demo else { return }
        let v = pitlaneClient.replacingOccurrences(of: "ios/", with: "")
        if (try? await call("POST", "/community/usage", body: ["device": "ios", "v": v, "counts": counts])) != nil { Usage.taken(counts) }
    }
    /// what the driver writes from the feedback button's "Send feedback" (POST /community/feedback), with the stars when
    /// given and the screen it was sent from ("menu:<view>")
    func sendFeedback(_ text: String, rating: Int?) async throws {
        guard !demo else { return }
        var b: [String: Any] = ["text": text, "device": "ios", "v": pitlaneClient.replacingOccurrences(of: "ios/", with: ""), "view": "menu:" + Usage.view, "lang": I18n.shared.lang]
        if let r = rating, (1...5).contains(r) { b["rating"] = r }
        _ = try await call("POST", "/community/feedback", body: b)
        Usage.count("act:feedback_sent")
    }
    // ---------- the support chat (the feedback button): the driver and Support, newest at the bottom ----------
    /// Support's messages the driver has not read (an admin in admin mode: the conversations with drivers' messages
    /// not read), and the newest one's line: the button's count and the inbox's "Support replied"
    @Published var supportUnread = 0
    @Published var supportLast = ""
    /// the support chat open: "" the driver's own (or an admin's inbox), else that driver's thread (admins)
    @Published var supportOpen: String?
    var supportNick = ""
    func openSupport(_ accountId: String = "", nick: String = "") {
        guard signedIn, !demo else { return }
        supportNick = nick
        supportOpen = accountId
        Usage.count("act:support_open")
    }
    private var supportTask: Task<Void, Never>?
    /// every 2 minutes while the app is on the screen and signed in: has Support (or a driver, for an admin) written?
    func startSupport() {
        guard supportTask == nil else { return }
        supportTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.checkSupport()
                try? await Task.sleep(nanoseconds: 120_000_000_000)
            }
        }
    }
    func stopSupport() { supportTask?.cancel(); supportTask = nil }
    func checkSupport() async {
        guard signedIn, !demo else { supportUnread = 0; return }
        do {
            if admin {
                let j = try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/support/unread")) as? [String: Any] ?? [:]
                supportUnread = int(j["n"]); supportLast = ""
            } else {
                let j = try JSONSerialization.jsonObject(with: await call("GET", "/community/support/unread")) as? [String: Any] ?? [:]
                supportUnread = int(j["n"]); supportLast = str(j["last"])
            }
        } catch {}
    }
    private func supportMsgs(_ d: Data) -> [SupportMsg] {
        let j = (try? JSONSerialization.jsonObject(with: d) as? [String: Any]) ?? [:]
        return (j["msgs"] as? [[String: Any]] ?? []).map { m in
            // who wrote it: "support" in an admin's thread, "me" (the driver's own) in the driver's
            let support = (m["support"] as? Bool) ?? (m["fromSupport"] as? Bool) ?? !((m["me"] as? Bool) ?? false)
            return SupportMsg(id: str(m["id"]), driver: !support, text: str(m["text"]), created: num(m["created"]) ?? 0, rating: int(m["rating"]))
        }.sorted { $0.created < $1.created }
    }
    /// a thread: the driver's own ("", reading it marks Support's messages read) or a driver's (admins)
    func supportThread(_ accountId: String) async throws -> [SupportMsg] {
        if demo { return [] }
        if accountId.isEmpty {
            let r = supportMsgs(try await call("GET", "/community/support"))
            supportUnread = 0; supportLast = ""
            return r
        }
        return supportMsgs(try await call("GET", "/community/admin/support/" + idPath(accountId)))
    }
    /// the support inbox (admins): one row per driver, the newest first
    func supportInbox() async throws -> [SupportConv] {
        let j = try JSONSerialization.jsonObject(with: await call("GET", "/community/admin/support")) as? [String: Any] ?? [:]
        return (j["items"] as? [[String: Any]] ?? j["convs"] as? [[String: Any]] ?? []).map { c in
            SupportConv(accountId: str(c["accountId"]), nick: str(c["nick"]), text: str(c["last"]).isEmpty ? str(c["text"]) : str(c["last"]),
                        created: num(c["lastAt"]) ?? num(c["created"]) ?? 0, fromSupport: (c["lastSupport"] as? Bool) ?? (c["fromSupport"] as? Bool) ?? false,
                        unread: int(c["unread"]))
        }
    }
    /// a message: the driver's to Support (""), or an admin's reply as Support to that driver
    func supportSend(_ accountId: String, _ text: String) async throws {
        guard !demo else { return }
        if accountId.isEmpty {
            _ = try await call("POST", "/community/support", body: ["text": text, "device": "ios", "v": pitlaneClient.replacingOccurrences(of: "ios/", with: ""), "view": "menu:" + Usage.view, "lang": I18n.shared.lang])
            Usage.count("act:support_sent")
        } else {
            _ = try await call("POST", "/community/admin/support/" + idPath(accountId), body: ["text": text])
            Usage.count("act:support_reply")
        }
        await checkSupport()
    }
    // a DRINKS driver name: taken by someone else on the platform? (your own names never clash)
    func nameFree(_ name: String) async -> Bool {
        guard let d = try? await call("POST", "/community/name-check", body: ["name": name]),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return true }
        return j["free"] as? Bool ?? true
    }

    func communityTrace(_ id: String) async throws -> Trace? {
        if demo { return Demo.trace(id) }
        return parseTrace((try await cachedGet("/community/laps/" + idPath(id)).data as? [String: Any])?["trace"])
    }

    func reports() async throws -> Got<[SharedReport]> {
        if demo { return Got(data: Demo.reports()) }
        let g = try await cachedGet("/community/reports?game=\(game)")
        let a = (g.data as? [String: Any])?["reports"] as? [[String: Any]] ?? []
        return Got(data: a.map { r in
            SharedReport(id: str(r["id"]), alias: str(r["alias"]), track: str(r["track"]), car: str(r["car"]), created: num(r["created"]) ?? 0, finish: int(r["finish"]), field: int(r["field"]), best: pos(r["best"]), mine: (r["mine"] as? Bool) ?? false)
        }, stale: g.stale)
    }

    func setups() async throws -> Got<[SharedSetup]> {
        if demo { return Got(data: Demo.setups()) }
        let g = try await cachedGet("/community/setups?game=\(game)")
        let a = (g.data as? [String: Any])?["setups"] as? [[String: Any]] ?? []
        return Got(data: a.map { s in
            SharedSetup(id: str(s["id"]), alias: str(s["alias"]), name: str(s["name"]), car: str(s["car"]), track: str(s["track"]), notes: str(s["notes"]), downloads: int(s["downloads"]), created: num(s["created"]) ?? 0)
        }, stale: g.stale)
    }
}

/// A race against iRacing's AI: the PC says so, or an offline race (no subsession, its id "t-…")
func isAIRace(_ r: [String: Any]) -> Bool {
    if r["ai"] as? Bool ?? false { return true }
    let g = (r["game"] as? String) ?? ""
    return (g.isEmpty || g == "iracing") && ((r["subsession"] as? NSNumber)?.intValue ?? 0) == 0 && ((r["id"] as? String) ?? "").hasPrefix("t-")
}

/// A Steam or Discord account with no Pitlane HQ account yet: the sign-up grant and the name for the new account's form.
struct SocialNew: Identifiable {
    let sid: String
    let name: String
    var id: String { sid }
}

/// The parameters of pitlanehq://steam?… or pitlanehq://discord?… (a "+" is a space, as the server writes them).
func steamQuery(_ u: URL) -> [String: String] {
    var out: [String: String] = [:]
    for kv in (u.query ?? "").split(separator: "&") {
        let p = kv.split(separator: "=", maxSplits: 1).map { String($0).replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? String($0) }
        if let k = p.first, !k.isEmpty { out[k] = p.count > 1 ? p[1] : "" }
    }
    return out
}

/// Steam's or Discord's sign-in in the system's sign-in sheet (ASWebAuthenticationSession), which closes by itself when
/// the server sends it on to this app's address (pitlanehq://…).
@MainActor
final class AuthSheet: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?

    /// The address it closed on, or nil when the driver closed the sheet.
    func run(_ url: URL) async -> URL? {
        let u: URL? = await withCheckedContinuation { (c: CheckedContinuation<URL?, Never>) in
            let s = ASWebAuthenticationSession(url: url, callbackURLScheme: "pitlanehq") { cb, err in
                c.resume(returning: err == nil ? cb : nil)
            }
            s.presentationContextProvider = self
            session = s
            if !s.start() { c.resume(returning: nil) }
        }
        session = nil
        return u
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let ws = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
        return ws.first { $0.isKeyWindow } ?? ws.first ?? ASPresentationAnchor()
    }
}
