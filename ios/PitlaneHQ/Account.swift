import Foundation
import Security

let server = URL(string: "https://pitlanehq.app")!
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
private func orNull(_ v: Any?) -> Any { v ?? NSNull() }
private func pos(_ v: Any?) -> Double? { num(v).flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
private func doubles(_ v: Any?) -> [Double] { (v as? [NSNumber] ?? []).map(\.doubleValue) }

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
    /// an admin can see the app as everyone else does (to test it), on this phone
    @Published var asUser = UserDefaults.standard.bool(forKey: "asUser") {
        didSet { UserDefaults.standard.set(asUser, forKey: "asUser"); if !admin && demo { demo = false } }
    }
    /// what the screens use: false while an admin looks as a normal user
    var admin: Bool { realAdmin && !asUser }
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
    /// the thumbs the driver gave the coach's tips on this device, by session and corner ("sid:apexM" → 1 or -1)
    @Published var tipRatings: [String: Int] = [:]
    @Published var demo = UserDefaults.standard.bool(forKey: "demo") {
        didSet { UserDefaults.standard.set(demo, forKey: "demo"); loadRaces() }
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
        Vault.set("token", nil)
        Vault.set("dataKey", nil)
        for k in ["email", "display", "verified", "admin", "syncedFiles", "syncVersion", "syncUpdated", "twoFactor", "recoveryLeft"] { defaults.removeObject(forKey: k) }
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
        races = []
    }

    // ---------- server ----------

    func call(_ method: String, _ path: String, body: [String: Any]? = nil, auth: Bool = true) async throws -> Data {
        guard let url = URL(string: server.absoluteString + path) else { throw AppError.serverDown }
        var r = URLRequest(url: url, timeoutInterval: 20)
        r.httpMethod = method
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "content-type")
        }
        if auth {
            guard let t = token else { throw AppError.signedOut }
            r.setValue("Bearer " + t, forHTTPHeaderField: "authorization")
        }
        let pair: (Data, URLResponse)
        do {
            pair = try await URLSession.shared.data(for: r)
        } catch {
            throw AppError.offline
        }
        let (data, resp) = pair
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
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
        guard let token = j["token"] as? String, let wrapped = j["wrappedKey"] as? String else { throw AppError.serverDown }
        let key = try PLCrypto.open(key: wrap, sealed: wrapped, aad: PLCrypto.accountAAD)
        guard key.count == 32 else { throw AppError.serverDown }
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
        signedIn = true
    }

    // ---------- two-step sign-in (optional, recommended) ----------
    struct TwoFactorSetup { let secret: String; let url: URL }

    func setup2fa(password: String) async throws -> TwoFactorSetup {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        let j = try JSONSerialization.jsonObject(with: await call("POST", "/account/2fa/setup", body: ["auth": keys.auth])) as? [String: Any] ?? [:]
        guard let secret = j["secret"] as? String, let u = (j["url"] as? String).flatMap(URL.init) else { throw AppError.serverDown }
        return TwoFactorSetup(secret: secret, url: u)
    }

    /// Confirms the first code; returns the recovery codes (shown once).
    func enable2fa(code: String) async throws -> [String] {
        let j = try JSONSerialization.jsonObject(with: await call("POST", "/account/2fa/enable", body: ["code": code.trimmingCharacters(in: .whitespaces)])) as? [String: Any] ?? [:]
        let codes = j["codes"] as? [String] ?? []
        twoFactor = true
        recoveryLeft = codes.count
        defaults.set(true, forKey: "twoFactor")
        defaults.set(codes.count, forKey: "recoveryLeft")
        return codes
    }

    func disable2fa(password: String, code: String) async throws {
        let keys = try await Task.detached { [email] in try PLCrypto.derive(email: email, password: password) }.value
        _ = try await call("POST", "/account/2fa/disable", body: ["auth": keys.auth, "code": code.trimmingCharacters(in: .whitespaces)])
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
            if let blob = j["blob"] as? String, !blob.isEmpty, let key = dataKey {
                let raw = try PLCrypto.gunzip(PLCrypto.open(key: key, sealed: blob, aad: PLCrypto.accountAAD))
                let all = try JSONSerialization.jsonObject(with: raw) as? [String: Any] ?? [:]
                files = all.count
                // Go writes the files as base64 strings
                if let b64 = all["races.json"] as? String, let racesData = Data(base64Encoded: b64), let a = try? JSONSerialization.jsonObject(with: racesData) as? [[String: Any]] {
                    let slim = trimRaces(a)
                    if let d = try? JSONSerialization.data(withJSONObject: slim) { save("races", d) }
                }
                save("drivers", (all["drivers.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
                save("notes", (all["notes.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
                save("ratings", (all["ratings.json"] as? String).flatMap { Data(base64Encoded: $0) } ?? Data("{}".utf8))
            }
            syncedFiles = files
            syncVersion = int(j["version"])
            syncUpdated = num(j["updated"]) ?? 0
            defaults.set(syncedFiles, forKey: "syncedFiles")
            defaults.set(syncVersion, forKey: "syncVersion")
            defaults.set(syncUpdated, forKey: "syncUpdated")
            if let me = try? JSONSerialization.jsonObject(with: await call("GET", "/account/me")) as? [String: Any] {
                display = str(me["display"])
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
            }
            loadRaces()
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
        a.filter { str($0["game"]).isEmpty || str($0["game"]) == "iracing" }
            .sorted { (num($0["when"]) ?? 0) > (num($1["when"]) ?? 0) }
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
        if demo { races = Demo.races(); return }
        guard let d = saved("races"), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { races = []; return }
        races = a.map { r in
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
                                      ai: !me && ((x["ai"] as? Bool ?? false) || (isAIRace(r) && int(r["subsession"]) == 0)))
                }.sorted { $0.pos < $1.pos },
                cat: r["cat"] as? String,
                drinks: (r["drinks"] as? [String] ?? []).map { fixTxt($0) }.filter { !$0.isEmpty },
                ai: isAIRace(r)
            )
        }
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
        return Got(data: DiscordLink(linked: j["linked"] as? Bool ?? false, id: str(j["id"]), handle: str(j["handle"]), shown: j["shown"] as? Bool ?? false, oauth: j["oauth"] as? Bool ?? false))
    }

    /// The address of Discord's sign-in, to open in the browser.
    func discordStart() async throws -> URL? {
        let j = try JSONSerialization.jsonObject(with: await call("POST", "/account/discord/start", body: [:])) as? [String: Any] ?? [:]
        return URL(string: str(j["url"]))
    }

    func discordShow(_ shown: Bool) async throws { _ = try await call("POST", "/account/discord/show", body: ["shown": shown]) }

    func discordUnlink() async throws { _ = try await call("POST", "/account/discord/unlink", body: [:]) }

    // ---------- your laps (uploaded by PitlaneHQ.exe) ----------

    // session and lap ids look like acct_<id>:<…>; the ':' stays as it is in the path
    private func idPath(_ id: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~:")
        return id.addingPercentEncoding(withAllowedCharacters: allowed) ?? id
    }

    func sessions() async throws -> Got<[CloudSession]> {
        if demo { return Got(data: Demo.sessions()) }
        let g = try await cachedGet("/api/sessions?limit=100")
        return Got(data: (g.data as? [[String: Any]] ?? []).compactMap { s in
            guard let id = s["id"] as? String else { return nil }
            let kind = str(s["kind"]), game = s["game"] as? String
            // a session against iRacing's AI the server has no flag for (recorded by an older agent): an iRacing session
            // without a subsession (id "t-…" after the account's "acct_…:" prefix) that is not a test is a single-player
            // session, so against the AI
            let offlineAI = (game == nil || game == "iracing") && (id.split(separator: ":").last ?? "").hasPrefix("t-") && !kind.lowercased().contains("test")
            return CloudSession(id: id, started: num(s["started"]) ?? 0, track: str(s["track"]), trackConfig: str(s["track_config"]), car: str(s["car"]), kind: kind, laps: int(s["laps"]), best: pos(s["best"]),
                                cat: s["cat"] as? String, lic: s["lic"] as? String,
                                drvs: str(s["drvs"]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }, ai: int(s["ai"]) == 1 || offlineAI)
        }, stale: g.stale)
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
            let game = str(b["game"])
            guard game.isEmpty || game == "iracing" else { return nil }
            let lap = str(b["bestLapId"]), ses = str(b["bestSessionId"])
            return PersonalBest(track: str(b["track"]), trackConfig: str(b["track_config"]), car: str(b["car"]), best: num(b["best"]) ?? 0, laps: int(b["laps"]),
                                last: num(b["last"]) ?? 0, bestLapId: lap.isEmpty ? nil : lap, bestSessionId: ses.isEmpty ? nil : ses)
        }.sorted { $0.last > $1.last }, stale: g.stale)
    }

    // ---------- community ----------

    func combos() async throws -> Got<[Combo]> {
        if demo { return Got(data: Demo.combos()) }
        let g = try await cachedGet("/community/combos?game=iracing")
        let a = (g.data as? [String: Any])?["combos"] as? [[String: Any]] ?? []
        return Got(data: a.map { c in
            Combo(trackId: (c["trackId"] as? NSNumber)?.int64Value ?? 0, track: str(c["track"]), carId: (c["carId"] as? NSNumber)?.int64Value ?? 0, car: str(c["car"]), laps: int(c["laps"]), best: pos(c["best"]), cat: c["cat"] as? String)
        }, stale: g.stale)
    }

    /// The records: the fastest lap of every car and track, the newest first, with the lap it beat.
    func records() async throws -> Got<[RecordItem]> {
        if demo { return Got(data: []) }
        let g = try await cachedGet("/community/records?game=iracing&limit=40")
        let a = (g.data as? [String: Any])?["records"] as? [[String: Any]] ?? []
        return Got(data: a.map { recordOf($0, trackId: 0, track: "") }, stale: g.stale)
    }

    private func recordOf(_ r: [String: Any], trackId: Int64, track: String) -> RecordItem {
        let p = r["prev"] as? [String: Any]
        let tn = str(r["track"])
        return RecordItem(id: str(r["id"]), trackId: (r["trackId"] as? NSNumber)?.int64Value ?? trackId, track: tn.isEmpty ? track : tn,
                          carId: (r["carId"] as? NSNumber)?.int64Value ?? 0, car: str(r["car"]), cat: r["cat"] as? String,
                          time: num(r["time"]) ?? 0, created: num(r["created"]) ?? 0, alias: (r["alias"] as? String) ?? "Driver", n: int(r["n"]),
                          hasTrace: r["hasTrace"] as? Bool ?? false, mine: r["mine"] as? Bool ?? false, prof: r["prof"] as? Bool ?? false, sup: r["sup"] as? Bool ?? false,
                          prevTime: p.flatMap { pos($0["time"]) }, prevAlias: p?["alias"] as? String)
    }

    /// One track: its layout and official turns, how many drivers and laps it has, and the record of every car on it.
    func trackPage(trackId: Int64) async throws -> Got<TrackPage> {
        if demo { return Got(data: TrackPage(trackId: trackId, track: "", drivers: 0, laps: 0, layout: nil, turns: [], cars: [])) }
        let g = try await cachedGet("/community/track?game=iracing&trackId=\(trackId)")
        let j = g.data as? [String: Any] ?? [:]
        var lay: ([Double], [Double])? = nil
        if let l = j["layout"] as? [String: Any], let x = (l["x"] as? [NSNumber])?.map({ $0.doubleValue }), let y = (l["y"] as? [NSNumber])?.map({ $0.doubleValue }), x.count >= 20, x.count == y.count { lay = (x, y) }
        let turns = ((j["turns"] as? [NSNumber]) ?? []).map { $0.doubleValue }.filter { $0 >= 0 && $0 < 1 }
        let name = str(j["track"])
        let cars = (j["cars"] as? [[String: Any]] ?? []).map { recordOf($0, trackId: trackId, track: name) }
        return Got(data: TrackPage(trackId: trackId, track: name, drivers: int(j["drivers"]), laps: int(j["laps"]), layout: lay, turns: turns, cars: cars), stale: g.stale)
    }

    /// One line per driver: their best lap.
    /// The card of a car: what it does on every track it was driven on (its hardest braking, where the fast
    /// drivers shift up, its top speed), learnt by the server from its laps; nil when the server has no laps of it.
    func carCard(carId: Int64) async throws -> [String: Any]? {
        if demo { return nil }
        guard let j = try await cachedGet("/community/car?game=iracing&carId=\(carId)").data as? [String: Any], ((j["n"] as? NSNumber)?.intValue ?? 0) > 0 else { return nil }
        return j
    }
    /// A track's layout drawn by the community from clean laps (x/y of n points along the lap), nil when none yet.
    func trackLayout(trackId: Int64) async -> ([Double], [Double])? {
        if demo || trackId <= 0 { return nil }
        guard let j = try? await cachedGet("/community/trackmaps?game=iracing&trackId=\(trackId)").data as? [String: Any],
              let x = j["x"] as? [Any], let y = j["y"] as? [Any], x.count >= 20, x.count == y.count else { return nil }
        return (x.map { ($0 as? NSNumber)?.doubleValue ?? 0 }, y.map { ($0 as? NSNumber)?.doubleValue ?? 0 })
    }
    /// The model's references for a car and track (`/community/model`): the record (the fastest lap really driven) and the
    /// next level for a lap of `lapTime` (the driver just ahead), each a trace every 5 m with its time and, when known, its line.
    func modelRefs(trackId: Int64, carId: Int64, lapTime: Double) async -> (rec: (Trace, Double)?, lvl: (Trace, Double)?, corners: [CornerCard]) {
        if demo || trackId <= 0 || carId <= 0 { return (nil, nil, []) }
        guard let m = try? await cachedGet("/community/model?game=iracing&trackId=\(trackId)&carId=\(carId)").data as? [String: Any] else { return (nil, nil, []) }
        // the corner card: where the fastest drivers here brake and how fast they take each corner of the record lap
        let cards: [CornerCard] = ((m["corners"] as? [[String: Any]]) ?? []).map { o in
            func d(_ k: String) -> Double { (o[k] as? NSNumber)?.doubleValue ?? 0 }
            return CornerCard(d: d("d"), apex: d("apex"), b0: d("b0"), b1: d("b1"), v0: d("v0"), v1: d("v1"), n: (o["n"] as? NSNumber)?.intValue ?? 0)
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
        var rec: (Trace, Double)? = nil
        if let ideal = m["ideal"] as? [[Any]], ideal.count > 40, num0(m, "idealTime") > 0 {
            let rows = ideal.map(row)
            var tr = Trace(bin: 5, rows: rows)
            if let p = xy(m["idealXY"], rows.count) ?? xy(m["lineXY"], rows.count) { tr.x = p.x; tr.y = p.y; tr.g = p.g }
            rec = (tr, num0(m, "idealTime"))
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
                }
                if tr.x == nil, let p = xy(m["lineXY"], cut.count) { tr.x = p.x; tr.y = p.y; tr.g = p.g }
                lvl = (tr, tm)
            }
        }
        return (rec, lvl, cards)
    }
    /// A thumb on one of the coach's tips (1 up, -1 down, 0 takes it back), kept with the account on the server (coachtips.js).
    func rateTip(trackId: Int64, carId: Int64, sid: String, started: Double, n: Int, apexM: Int, kind: String, cls: String, up: Int) async {
        if demo || trackId <= 0 || carId <= 0 { return }
        _ = try? await call("POST", "/community/coach/rate", body: ["game": "iracing", "trackId": trackId, "carId": carId, "sid": sid, "started": Int64(started), "n": n, "apex": apexM, "kind": kind, "cls": cls, "up": up])
    }
    /// A track's official turns (T1 … Tn as fractions of the lap from the line), placed by an admin on its map.
    /// What the coach learnt from everyone's tips (coachtips.js): the tips an admin turned off ("kind|cls"), how many drivers
    /// each bucket helped and whether a tip may say it; nil without a connection.
    func coachInfo() async -> CoachInfo? {
        if demo { return nil }
        guard let j = try? await cachedGet("/community/coach/weights").data as? [String: Any] else { return nil }
        let off = Set((j["off"] as? [String]) ?? [])
        var conf: [String: (Int, Int)] = [:]
        for b in (j["buckets"] as? [[String: Any]]) ?? [] { conf["\(str(b["kind"]))|\(str(b["cls"]))"] = (int(b["win"]), int(b["n"])) }
        return CoachInfo(off: off, conf: conf, confidence: (j["confidence"] as? Bool) ?? false, min: (j["min"] as? NSNumber)?.intValue ?? 30)
    }
    /// The driver's own memory: the kinds of tip that repeat across their tracks (habits), the most repeated first.
    func coachHabits() async -> [Habit] {
        if demo { return [] }
        guard let j = try? await cachedGet("/community/coach/me").data as? [String: Any], let a = j["habits"] as? [[String: Any]] else { return [] }
        return a.map { Habit(kind: str($0["kind"]), tracks: int($0["tracks"]), sessions: int($0["sessions"])) }
    }
    func turns(trackId: Int64) async -> [Double] {
        if demo || trackId <= 0 { return [] }
        guard let j = try? await cachedGet("/community/turns?game=iracing&trackId=\(trackId)").data as? [String: Any], let a = j["turns"] as? [Any] else { return [] }
        return a.compactMap { ($0 as? NSNumber)?.doubleValue }.filter { $0 >= 0 && $0 < 1 }
    }
    /// The pit lane of a track, learnt from laps through the pits: [5 m point of a lap of n points, metres to the left].
    func pitLane(trackId: Int64) async -> PitLane? {
        if demo || trackId <= 0 { return nil }
        guard let j = try? await cachedGet("/community/pitlane?game=iracing&trackId=\(trackId)").data as? [String: Any],
              let a = j["pts"] as? [[Any]], let n = (j["n"] as? NSNumber)?.intValue, n > 0 else { return nil }
        let pts: [(Int, Double)] = a.compactMap { q in
            guard q.count == 2, let i = (q[0] as? NSNumber)?.intValue, let v = (q[1] as? NSNumber)?.doubleValue else { return nil }
            return (i, v)
        }
        return pts.count >= 10 ? PitLane(n: n, pts: pts) : nil
    }
    func leaderboard(trackId: Int64, carId: Int64) async throws -> Got<[CommunityLap]> {
        if demo { return Got(data: Demo.board(trackId: trackId, carId: carId)) }
        let g = try await cachedGet("/community/laps?game=iracing&trackId=\(trackId)&carId=\(carId)")
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
                                    lic: l["lic"] as? String, prof: (l["prof"] as? Bool) ?? false, sup: (l["sup"] as? Bool) ?? false, field: (l["field"] as? Bool) ?? false))
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
    /// help with an account: "verify", "2fa-off", "signout", "unlink-driver" or "rename" (with the new public name)
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
        let j = (try JSONSerialization.jsonObject(with: await call("GET", "/community/leagues")) as? [String: Any]) ?? [:]
        let lim = j["limits"] as? [String: Any] ?? [:]
        leagueLimit = LeagueLimit(limit: j["limit"] == nil ? 3 : int(j["limit"]), supporter: j["supporter"] as? Bool ?? false,
                                  free: lim["free"] == nil ? 3 : int(lim["free"]), supporterLimit: lim["supporter"] == nil ? 10 : int(lim["supporter"]))
        return (j["leagues"] as? [[String: Any]] ?? []).map { x in
            League(id: str(x["id"]), name: fixTxt(str(x["name"])), about: fixTxt(str(x["about"])), cat: x["cat"] as? String, discord: str(x["discord"]), web: str(x["web"]), schedule: str(x["schedule"]),
                   cars: fixTxt(str(x["cars"])), lang: str(x["lang"]), mine: x["mine"] as? Bool ?? false, by: str(x["by"]),
                   cats: x["cats"] as? [String] ?? [], days: (x["days"] as? [NSNumber] ?? []).map { $0.intValue }, time: str(x["time"]), tz: str(x["tz"]), open: x["open"] as? Bool ?? true,
                   views: x["views"] == nil ? -1 : int(x["views"]), clicks: x["clicks"] == nil ? -1 : int(x["clicks"]), created: num(x["created"]) ?? 0, updated: num(x["updated"]) ?? 0)
        }
    }
    func saveLeague(_ id: String?, _ l: League) async throws {
        let path = "/community/leagues" + (id.map { "/" + ($0.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0) } ?? "")
        _ = try await call("POST", path, body: ["name": l.name, "about": l.about, "cats": l.cats, "days": l.days, "time": l.time, "tz": l.tz, "open": l.open,
                                              "discord": l.discord, "web": l.web, "schedule": l.schedule, "cars": l.cars, "lang": l.lang])
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
        let cats = ["oval": "oval", "dirtoval": "dirt_oval", "dirtroad": "dirt_road", "formulacar": "formula_car", "sportscar": "sports_car"]
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
        let g = try await cachedGet("/community/reports?game=iracing")
        let a = (g.data as? [String: Any])?["reports"] as? [[String: Any]] ?? []
        return Got(data: a.map { r in
            SharedReport(id: str(r["id"]), alias: str(r["alias"]), track: str(r["track"]), car: str(r["car"]), created: num(r["created"]) ?? 0, finish: int(r["finish"]), field: int(r["field"]), best: pos(r["best"]), mine: (r["mine"] as? Bool) ?? false)
        }, stale: g.stale)
    }

    func setups() async throws -> Got<[SharedSetup]> {
        if demo { return Got(data: Demo.setups()) }
        let g = try await cachedGet("/community/setups?game=iracing")
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
