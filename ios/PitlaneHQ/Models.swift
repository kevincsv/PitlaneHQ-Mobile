import Foundation

// ---------- the data the server and the account sync give ----------

struct CloudSession: Identifiable, Hashable {
    let id: String
    let started: Double
    let track: String
    let trackConfig: String
    let car: String
    let kind: String
    let laps: Int
    let best: Double?
    /// the discipline (oval, sports_car, formula_car, dirt_oval, dirt_road) and your license class in it (R, D, C, B, A, P)
    var cat: String? = nil
    var lic: String? = nil
    /// the friends who drove laps of it in DRINKS mode, and a session against iRacing's AI
    var drvs: [String] = []
    var ai = false
    /// the sim it was driven in: iracing or lmu (Le Mans Ultimate)
    var game = "iracing"
    /// the car's class when the server sends one (Le Mans Ultimate: Hypercar, LMP2…)
    var cls: String? = nil
    /// your place and how many cars (your class's when inClass, the place within your class in a multiclass session);
    /// nil for older sessions and test drives
    var pos: Int? = nil
    var field: Int? = nil
    var inClass = false
    /// "P3/20", "P3", or "–" without a place
    var place: String { pos.map { p in "P\(p)" + (field.map { f in "/\(f)" } ?? "") } ?? "–" }
}

/// Home's four numbers of the month, counted by the server like the PC's and the web's (GET /api/sessions/summary).
struct MonthStats {
    var laps = 0
    var secs: Double = 0
    var sessions = 0
    var days = 0
    var races = 0
    var top5 = 0
    var best: MonthBest? = nil
}

/// The month's best result: your place, how many cars (your class's when inClass), where and when.
struct MonthBest {
    let pos: Int
    let field: Int
    let inClass: Bool
    let track: String
    let car: String
    let started: Double
}

/// The same numbers from what the phone already has (demo data, or a server that does not count them yet).
func localMonthStats(sessions: [CloudSession], races: [Race]) -> MonthStats {
    let cal = Calendar.current
    let m0 = (cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()).timeIntervalSince1970 * 1000
    let ms = sessions.filter { $0.started >= m0 && $0.laps > 0 }
    // a session's time is its laps at its best lap's pace, like the web for a session without the server's total
    let secs = ms.reduce(0.0) { a, x in a + Double(x.laps) * ((x.best ?? 0) > 0 && (x.best ?? 0) < 3600 ? x.best! * 1.03 : 0) }
    let days = Set(ms.map { cal.startOfDay(for: Date(timeIntervalSince1970: $0.started / 1000)) }).count
    let month = races.filter { $0.when >= m0 }
    return MonthStats(laps: ms.reduce(0) { $0 + $1.laps }, secs: secs, sessions: ms.count, days: days, races: month.count,
                      top5: month.filter { (1...5).contains($0.finish) && !$0.dnf }.count, best: bestRace(races))
}

/// Home's best result when the server's summary has none for the month, like the web's: the best place of this month's
/// races, else of every race the phone has (the lowest place, the newest of a tie; a DNF never counts).
func bestRace(_ races: [Race]) -> MonthBest? {
    let cal = Calendar.current
    let m0 = (cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()).timeIntervalSince1970 * 1000
    let month = races.filter { $0.when >= m0 }
    let pool = month.isEmpty ? races : month
    let best = pool.filter { $0.finish > 0 && !$0.dnf }.sorted { $0.finish != $1.finish ? $0.finish < $1.finish : $0.when > $1.when }.first
    return best.map { MonthBest(pos: $0.finish, field: $0.field, inClass: false, track: $0.track, car: $0.car, started: $0.when) }
}

struct CloudLap: Identifiable, Hashable {
    let id: String
    let n: Int
    let time: Double
    let valid: Bool
    let sectors: [Double]
    var inc: Int = 0 // incident points on the lap (they do not make it invalid)
    var drv = ""     // a friend's lap (DRINKS mode): who drove it
}

/// One row every `bin` metres: speed m/s, throttle 0-1, brake 0-1, gear, steering rad, lap time s.
struct Trace {
    let bin: Double
    let rows: [[Double]]
    /// The shape of the track: where the car was at every row (Pitlane HQ 0.5 and later record it).
    var x: [Double]? = nil
    var y: [Double]? = nil
    /// The origin [lat, lon] of x=0, y=0 when the path comes from the game's position (exact); nil by dead reckoning.
    var g: [Double]? = nil
    /// The incidents of the lap as [d, pts, d, pts…] (lap distance in m, incident points).
    var inc: [Double] = []
    var hasShape: Bool { x != nil && y != nil && x!.count == rows.count && x!.count > 10 }
    /// What each incident was: "off", "loss", "light" (light contact) or "contact" (older laps: by the points).
    var incK: [String] = []
    /// What the lap was driven in, as the PC tags it: "traffic" (a car close ahead), "cold" (the first lap of a run),
    /// "wet" (the track at least lightly wet); "cmp:<n>" (the tyre compound) is never shown.
    var f: [String] = []
    var incidents: [(d: Double, pts: Int, kind: String)] {
        (0..<(inc.count / 2)).map { i in
            let pts = Int(inc[2 * i + 1])
            let k: String = i < incK.count ? incK[i] : (pts >= 4 ? "contact" : pts == 2 ? "loss" : "off")
            return (d: inc[2 * i], pts: pts, kind: k)
        }
    }
}

struct PersonalBest: Identifiable, Hashable {
    var id: String { track + "|" + trackConfig + "|" + car }
    let track: String
    let trackConfig: String
    let car: String
    let best: Double
    let laps: Int
    let last: Double
    let bestLapId: String?
    let bestSessionId: String?
    var game = "iracing"
}

struct Combo: Identifiable, Hashable {
    var id: String { "\(trackId)-\(carId)" }
    let trackId: Int64
    let track: String
    let carId: Int64
    let car: String
    let laps: Int
    let best: Double?
    var cat: String? = nil
    var cls: String? = nil
}

/// A record of the leaderboards: the fastest lap of a car and track, and the lap it beat (the second fastest), for
/// Community's "Recent records" and the track page.
struct RecordItem: Identifiable, Hashable {
    let id: String
    let trackId: Int64
    let track: String
    let carId: Int64
    let car: String
    let cat: String?
    let time: Double
    let created: Double
    let alias: String
    let n: Int
    let hasTrace: Bool
    let mine: Bool
    let prof: Bool
    let sup: Bool
    let prevTime: Double?
    let prevAlias: String?
    var cls: String? = nil
    var combo: Combo { Combo(trackId: trackId, track: track, carId: carId, car: car, laps: n, best: time, cat: cat, cls: cls) }
}

/// A track's page (in development): its layout and official turns, how many drivers and laps it has, the record of every car on it.
struct TrackPage {
    let trackId: Int64
    let track: String
    let drivers: Int
    let laps: Int
    let layout: ([Double], [Double])?
    let turns: [Double]
    let cars: [RecordItem]
}

/// a track to open its page: its id and name
struct TrackRef: Hashable {
    let id: Int64
    let name: String
}

struct CommunityLap: Identifiable, Hashable {
    let id: String
    let alias: String
    let time: Double
    let created: Double
    let hasTrace: Bool
    let sectors: [Double]
    /// the signed-in driver's own lap, also when it was shared anonymously (only they see that)
    var mine: Bool = false
    var lic: String? = nil
    /// the name opens the driver's profile (never for an anonymous lap)
    var prof: Bool = false
    /// a supporter (someone who donates)
    var sup: Bool = false
    /// a rival of a race someone drove
    var field: Bool = false
}

/// A driver's profile: their nickname (never their iRacing name), license classes, recent races and laps on the leaderboards.
struct DriverProfile {
    let name: String
    let since: Double
    let mine: Bool
    let admin: Bool
    let anonymous: Bool
    let supporter: Bool
    let supporterHidden: Bool
    let lics: [String: String]
    let races: [ProfileRace]
    let laps: [ProfileLap]
    var days: [String: Int] = [:]
    /// their Discord, when they chose to show it on their profile
    var discordId = ""
    var discordHandle = ""
}

/// A league posted on the hub: the days it races (0 Monday … 6 Sunday), the usual start in its time zone, one or
/// several disciplines (mixed), an optional Discord invite and website, whether it is looking for drivers; the views
/// and clicks only for its creator (−1 for everyone else).
/// How many leagues you may post: 3, or 10 as a supporter (Patreon or by hand).
struct LeagueLimit { var limit = 3; var supporter = false; var free = 3; var supporterLimit = 10 }

struct League: Identifiable {
    var id: String
    var name: String
    var about: String
    var cat: String?
    var discord: String
    var web: String
    var schedule: String
    var cars: String
    var lang: String
    var mine: Bool = false
    var by: String = ""
    var cats: [String] = []
    var days: [Int] = []
    var time: String = ""
    var tz: String = ""
    var open: Bool = true
    var views: Int = -1
    var clicks: Int = -1
    var created: Double = 0
    var updated: Double = 0
    var game = "iracing"
}

/// One day of a league post's views and clicks, for its creator's chart.
struct LeagueDay {
    let day: String
    let views: Int
    let clicks: Int
}

/// The disciplines of a league: the new list, or the one discipline older posts carry.
func leagueDiscs(_ x: League) -> [String] { x.cats.isEmpty ? (x.cat.map { [$0] } ?? []) : x.cats }

/// The next race of a league: the first of its days at its time, in its zone, from an hour ago on (a race under way
/// counts); nil without a schedule.
func leagueNext(_ x: League, now: Date = Date()) -> Date? {
    let p = x.time.split(separator: ":").compactMap { Int($0) }
    guard !x.days.isEmpty, p.count == 2, (0...23).contains(p[0]), (0...59).contains(p[1]), let tz = TimeZone(identifier: x.tz.isEmpty ? "UTC" : x.tz) else { return nil }
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = tz
    let start = cal.startOfDay(for: now)
    for i in 0..<8 {
        guard let d = cal.date(byAdding: .day, value: i, to: start) else { continue }
        let wd = (cal.component(.weekday, from: d) + 5) % 7 // 0 Monday … 6 Sunday
        guard x.days.contains(wd), let at = cal.date(bySettingHour: p[0], minute: p[1], second: 0, of: d) else { continue }
        if at.timeIntervalSince(now) >= -3600 { return at }
    }
    return nil
}

struct ProfileRace: Identifiable {
    let id = UUID()
    let when: Double
    let track: String
    let car: String
    let cat: String?
    let lic: String?
    let official: Bool
    let start: Int
    let finish: Int
    let field: Int
    let inc: Int
    let best: Double?
    let irChange: Int
    let dnf: Bool
}

struct ProfileLap: Identifiable {
    let id = UUID()
    let track: String
    let car: String
    let time: Double
    let created: Double
    let cat: String?
    let lic: String?
    let anon: Bool
    var trackId: Int64 = 0
    var carId: Int64 = 0
    var pos: Int = 0
    var of: Int = 0
}

struct SharedReport: Identifiable, Hashable {
    let id: String
    let alias: String
    let track: String
    let car: String
    let created: Double
    let finish: Int
    let field: Int
    let best: Double?
    var mine: Bool = false
}

struct SharedSetup: Identifiable, Hashable {
    let id: String
    let alias: String
    let name: String
    let car: String
    let track: String
    let notes: String
    let downloads: Int
    let created: Double
}

struct Device: Identifiable, Hashable {
    let id: String
    let device: String
    let lastSeen: Double
    let current: Bool
}

/// Your Discord account linked to this one (`oauth`: the server can link it with Discord's sign-in).
/// Your Steam account linked to this one (Account → Steam): its persona name and whether your profile shows it.
struct SteamLink {
    let linked: Bool
    let id: String
    let persona: String
    let shown: Bool
}

/// The sims the phones show, one at a time (Home, Analysis, Community): iRacing and Le Mans Ultimate (in beta).
let games = ["iracing", "lmu"]
func gameShort(_ g: String) -> String { g == "lmu" ? "LMU" : "iRacing" }
func gameName(_ g: String) -> String { g == "lmu" ? "Le Mans Ultimate" : "iRacing" }

/// Le Mans Ultimate's classes, its categories where iRacing has its disciplines (proper names, the same in every language).
let LMU_CLASSES = ["Hypercar", "LMP2", "LMP3", "LMGT3", "GTE"]

/// The Le Mans Ultimate class of a car: the server's when it sends one, else from the car's name ("" when unknown).
func lmuClass(_ cls: String?, _ car: String) -> String {
    let c = (cls ?? "").trimmingCharacters(in: .whitespaces)
    if !c.isEmpty {
        let l = c.lowercased()
        if l.contains("hyper") || l == "lmh" || l == "lmdh" { return "Hypercar" }
        if l.contains("lmp2") { return "LMP2" }
        if l.contains("lmp3") { return "LMP3" }
        if l.contains("gt3") { return "LMGT3" }
        if l.contains("gte") { return "GTE" }
        return c
    }
    let rx = { (p: String) -> Bool in car.range(of: p, options: [.regularExpression, .caseInsensitive]) != nil }
    if rx("\\blmp2\\b|oreca 07|alpine a470") { return "LMP2" }
    if rx("\\blmp3\\b|ligier js p3|js p325|ginetta g61|duqueine d0[89]") { return "LMP3" }
    if rx("gt3") { return "LMGT3" }
    if rx("\\bgte\\b|488 gte|911 rsr|c8\\.r|vantage amr") { return "GTE" }
    if rx("hypercar|\\blmdh\\b|\\blmh\\b|499p|\\b963\\b|gr010|9x8|v-series|a424|sc63|m hybrid|vanwall|\\b680\\b|glickenhaus|scg 007|isotta|tipo 6|valkyrie") { return "Hypercar" }
    return ""
}

struct DiscordLink {
    let linked: Bool
    let id: String
    let handle: String
    let shown: Bool
    let oauth: Bool
    /// the link signs in with Discord (false when only the bot's /link made it: it is linked again from Account)
    var login = true
}

/// DRINKS mode on the PC (admins only): friends drive and their laps go to the community under their name.
struct Drinks: Equatable {
    let admin: Bool
    let on: Bool
    let guest: String
    let guestAuto: Bool
    let guests: [String]
    let driver: String
}

/// A race the PC recorded (races.json in the account sync).
struct Race: Identifiable, Hashable {
    let id: String
    let when: Double
    let track: String
    let car: String
    let official: Bool
    let start: Int
    let finish: Int
    let field: Int
    let inc: Int
    let best: Double?
    let fieldBest: Double?
    let avg: Double?
    let consistency: Double?
    let pits: Int
    let fuelUsed: Double?
    let ir: Int
    let irChange: Int
    let sof: Int
    let dnf: Bool
    let laps: [RaceLap]
    let results: [RaceResult]
    var cat: String? = nil  // the discipline as iRacing names it (Oval, Road, DirtOval…); raceDisc tells which of ours
    var drinks: [String] = []  // DRINKS mode: who drove it when a friend drove any lap (the PC's report)
    var ai = false  // a race against iRacing's AI drivers (an offline race)
    var game = "iracing"  // the sim: Le Mans Ultimate (lmu) has no iRating and counts contacts, not incidents

    /// no iRating at all: a race against the AI, or one in another sim (Le Mans Ultimate has none)
    var noIr: Bool { ai || game != "iracing" }
    /// Le Mans Ultimate counts contacts, not iRacing's incident points
    var contacts: Bool { game == "lmu" }
    /// the incidents as the game counts them: "3x" in iRacing, "3" contacts in Le Mans Ultimate
    var incText: String { contacts ? "\(inc)" : "\(inc)x" }
    var incLabel: String { contacts ? t("contacts") : t("incidents") }

    /// DRINKS mode: your name in the race (the one of its drivers that is no lap's friend)
    var ownName: String { drinks.first(where: { n in !laps.contains(where: { $0.drv.caseInsensitiveCompare(n) == .orderedSame }) }) ?? "Me" }
    /// who drove a lap: the friend's name, or yours
    func driverOf(_ l: RaceLap) -> String { l.drv.isEmpty ? ownName : l.drv }
    /// DRINKS mode: who drove the race, with their laps and best lap, in the order they first drove ([] when you alone)
    var drivers: [(name: String, laps: Int, best: Double?)] {
        guard laps.contains(where: { !$0.drv.isEmpty }) else { return [] }
        var order: [String] = [], by: [String: (String, [RaceLap])] = [:]
        for l in laps { let n = driverOf(l), k = n.lowercased(); if by[k] == nil { order.append(k); by[k] = (n, []) }; by[k]!.1.append(l) }
        return order.map { k in let (n, ls) = by[k]!; return (n, ls.count, ls.filter { $0.time > 0 && !$0.cut && !$0.pit }.map(\.time).min()) }
    }
}

/// The discipline of a race as the PC tells it (discipline in journal.go, raceDisc in the web): iRacing says "Road"
/// for sports and formula cars alike, so the car name tells which.
func raceDisc(_ cat: String?, _ car: String) -> String {
    let c = (cat ?? "").lowercased().replacingOccurrences(of: "[ _-]", with: "", options: .regularExpression)
    let known = ["oval": "oval", "dirtoval": "dirt_oval", "dirtroad": "dirt_road", "formulacar": "formula_car", "sportscar": "sports_car"]
    if let k = known[c] { return k }
    if !c.isEmpty && c != "road" { return c }
    if car.isEmpty { return "" }
    if car.range(of: "p217|lmp|\\bgtp\\b|\\bdpi?\\b|prototype|hypercar", options: [.regularExpression, .caseInsensitive]) != nil { return "sports_car" }
    let formula = "formula|\\bf[1-4]\\b|super ?formula|dallara|indy|\\bir-?\\d+|skip barber|ff1600|pro mazda|\\busf\\b|lotus (18|49|79)|williams fw|mercedes-amg w1|tatuus|\\bvee\\b|\\bfr ?[23]\\."
    return car.range(of: formula, options: [.regularExpression, .caseInsensitive]) != nil ? "formula_car" : "sports_car"
}

struct RaceLap: Hashable {
    let n: Int
    let time: Double
    let pos: Int
    let inc: Int
    let pit: Bool
    var cut: Bool = false // the car left the track: not a valid lap
    var drv: String = ""  // DRINKS mode: the friend who drove it ("" you)
}

struct RaceResult: Hashable {
    let pos: Int
    let name: String
    let ir: Int
    let best: Double?
    let inc: Int
    let laps: Int
    var k: String = ""       // the driver's opaque key (the PC's driverKey): what your driver notes find them by
    var me: Bool = false
    var ai: Bool = false     // an AI driver
}

/// Your note on another driver (drivers.json in the account): one tag (danger, careful, clean, friend) and a note.
struct DriverNote: Hashable {
    let name: String
    let tag: String
    let note: String
}

/// Your notes on a track (notes.json in the account, the same the PC and the web write): a general note and one per
/// corner (the corner's number, where its braking zone starts and what you wrote).
struct TrackNote: Identifiable, Hashable {
    let trackId: Int64
    let track: String
    let general: String
    let corners: [CornerNote]
    let updated: String
    var id: Int64 { trackId }
}
struct CornerNote: Hashable {
    let n: Int
    let dist: Double
    let name: String
    let note: String
}

/// The facts of one lap, as the server reads them: its hardest braking (m/s², the top 5 % of its braking), the
/// speed it shifted up at in every gear (the highest point it took the gear to), its top speed.
/// Rows [speed, throttle, brake, gear, steering, time].
func lapFacts(_ rows: [[Double]]) -> (brake: Double?, shifts: [Int: Double], vmax: Double) {
    var dec: [Double] = []
    var shifts: [Int: Double] = [:]
    var vmax = 0.0
    if rows.count >= 2 {
        for i in 0..<(rows.count - 1) {
            let a = rows[i], b = rows[i + 1]
            if a.count < 6 || b.count < 6 { continue }
            vmax = max(vmax, a[0])
            let dt = b[5] - a[5]
            if dt > 0.01 && dt < 2 && a[2] >= 0.5 && a[0] > 12 && a[0] > b[0] { dec.append((a[0] - b[0]) / dt) }
            let g = Int(a[3])
            if g >= 1 && Int(b[3]) == g + 1 && a[0] > 5 { shifts[g] = max(shifts[g] ?? 0, a[0]) }
        }
    }
    dec.sort()
    let brake: Double? = dec.count >= 5 ? dec[min(dec.count - 1, Int((0.95 * Double(dec.count - 1) + 0.5).rounded(.down)))] : nil
    return (brake, shifts, vmax)
}

/// Text that came through a wrong encoding ("AutÃ³dromo") read back as it was written ("Autódromo").
func fixText(_ s: String) -> String {
    guard s.contains("Ã") || s.contains("Â"), let d = s.data(using: .isoLatin1), let u = String(data: d, encoding: .utf8) else { return s }
    return u
}
/// One car under several badges is one car (the server's carfamily.js): the lists show the family without the brand.
private let carFams: [(String, String)] = [
    ("Super Formula SF23", "^Super Formula SF23\\b"),
    ("NASCAR Cup Series Next Gen", "^NASCAR Cup Series Next Gen\\b"),
    ("NASCAR Cup Series Gen 6", "^NASCAR (Cup|Monster Energy Cup) Series (Chevrolet|Ford|Toyota)\\b"),
    ("NASCAR Xfinity Series", "^NASCAR Xfinity\\b"),
    ("NASCAR Truck Series", "^NASCAR (Craftsman |Camping World |Gander (RV & )?Outdoors )?Truck\\b"),
    ("ARCA Menards Series", "^ARCA Menards\\b"),
    ("Supercars Gen3", "^Supercars?\\b.*\\bGen ?3\\b"),
    ("Supercars Gen2", "^Supercars? (Ford Mustang GT|Holden ZB Commodore)\\b"),
    ("V8 Supercars", "^V8 Supercars?\\b"),
]
func carFam(_ s: String) -> String {
    let n = fixText(s).trimmingCharacters(in: .whitespaces)
    return carFams.first { n.range(of: $0.1, options: [.regularExpression, .caseInsensitive]) != nil }?.0 ?? n
}
/// A name as a key: no accents, no case, letters and numbers only, so the same car or track is one entry.
func nameKey(_ s: String) -> String {
    fixText(s).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased().filter { $0.isLetter || $0.isNumber }
}

func lapTime(_ s: Double?) -> String {
    guard let s, s.isFinite, s > 0 else { return "—" }
    let m = Int(s / 60)
    let r = s - Double(m) * 60
    return m > 0 ? String(format: "%d:%06.3f", m, r) : String(format: "%.3f", r)
}

func signed(_ n: Int) -> String { n > 0 ? "+\(n)" : "\(n)" }

func day(_ ms: Double) -> String {
    ms > 0 ? Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .omitted) : ""
}

func dayTime(_ ms: Double) -> String {
    ms > 0 ? Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .shortened) : ""
}

// ---------- comparing two laps (the same as Android's LapMath.kt) ----------

/// Two lap traces on the same distance grid (every `step` metres), ready to draw and compare.
struct Compared {
    let step: Double
    let speedA: [Double]
    let speedB: [Double]?
    let thrA: [Double]
    let brkA: [Double]
    let delta: [Double]?
    let tA: [Double]
    let tB: [Double]?
    var thrB: [Double]? = nil
    var brkB: [Double]? = nil
    var gearA: [Double]? = nil
    var gearB: [Double]? = nil
    /// the racing line: how far A was to one side of B at each point (m, NaN where unknown), and B's path, same grid
    var lat: [Double]? = nil
    var bx: [Double]? = nil
    var by: [Double]? = nil
}

/// The racing line, as the PC and the web read it: both laps carry the path their car drove (every 5 m, the game's
/// heading for both); at the same lap distance A's point along B's normal is how far A was to one side of B; the slow
/// drift of that dead reckoning goes with a ±400 m moving average. Nil when either has no path or they are not the same track.
/// B's path in A's frame: both from the game's position (B moved to A's origin) or both by dead reckoning; nil when one is
/// each, because they never line up.
func sameFrame(_ a: Trace, _ b: Trace) -> ([Double], [Double])? {
    guard let bx = b.x, let by = b.y else { return nil }
    if (a.g == nil) != (b.g == nil) { return nil }
    guard let ga = a.g, let gb = b.g, !(ga[0] == gb[0] && ga[1] == gb[1]) else { return (bx, by) }
    let dx = (gb[1] - ga[1]) * 111320 * cos(ga[0] * .pi / 180), dy = (gb[0] - ga[0]) * 110540
    return (bx.map { $0 + dx }, by.map { $0 + dy })
}

func lineOffsets(_ ax: [Double], _ ay: [Double], _ bx: [Double], _ by: [Double]) -> [Double]? {
    let n = [ax.count, ay.count, bx.count, by.count].min() ?? 0
    if n < 60 { return nil }
    var lat = [Double](repeating: 0, count: n), lon = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let i0 = max(0, i - 2), i1 = min(n - 1, i + 2)
        var tx = bx[i1] - bx[i0], ty = by[i1] - by[i0]
        let tm = hypot(tx, ty) > 0 ? hypot(tx, ty) : 1
        tx /= tm; ty /= tm
        let dx = ax[i] - bx[i], dy = ay[i] - by[i]
        lat[i] = -ty * dx + tx * dy; lon[i] = tx * dx + ty * dy
    }
    func smooth(_ v: [Double]) -> [Double] {
        var pre = [Double](repeating: 0, count: n + 1)
        for i in 0..<n { pre[i + 1] = pre[i] + v[i] }
        return (0..<n).map { i in let lo = max(0, i - 80), hi = min(n - 1, i + 80); return v[i] - (pre[hi + 1] - pre[lo]) / Double(hi - lo + 1) }
    }
    var lc = smooth(lat)
    let oc = smooth(lon)
    if oc.map({ abs($0) }).sorted()[n / 2] > 6 { return nil }
    for i in 0..<n where abs(oc[i]) > 20 || abs(lc[i]) > 25 { lc[i] = .nan }
    return lc
}

/// How far A was to the inside of B (m, + inside) at B's turn-in, apex and exit; nil on a straight or without a line.
func cornerLine(_ c: Compared, brake: Int, apex: Int, exit: Int, span: Int) -> (Double, Double, Double)? {
    guard let lat = c.lat, let bx = c.bx, let by = c.by else { return nil }
    let n = [lat.count, bx.count, by.count].min() ?? 0
    if apex <= 0 || apex >= n - 1 { return nil }
    func tan(_ i: Int) -> (Double, Double) { let i0 = max(0, i - 1), i1 = min(n - 1, i + 1), tx = bx[i1] - bx[i0], ty = by[i1] - by[i0], m = hypot(tx, ty) > 0 ? hypot(tx, ty) : 1; return (tx / m, ty / m) }
    let t1 = tan(max(0, apex - span)), t2 = tan(min(n - 1, apex + span))
    let cr = t1.0 * t2.1 - t1.1 * t2.0
    if abs(cr) < 0.05 { return nil }
    let sg: Double = cr < 0 ? -1 : 1
    func at(_ i: Int) -> Double { let v = (max(0, i - 1)...min(n - 1, i + 1)).map { lat[$0] }.filter { !$0.isNaN }; return v.isEmpty ? .nan : v.reduce(0, +) / Double(v.count) * sg }
    let r = (at(brake), at(apex), at(min(n - 1, exit)))
    return r.0.isNaN || r.1.isNaN || r.2.isNaN ? nil : r
}

/// The advice of the line in one corner: an I18n key and its argument (metres), or nil.
func lineTip(_ l: (Double, Double, Double)?, sameBrake: Bool) -> (String, String)? {
    guard let l else { return nil }
    var c: [(Double, String, String)] = []
    func m(_ v: Double) -> String { String(format: "%.1f", abs(v)) }
    if l.0 >= 1.5 { c.append((l.0, sameBrake ? "tip_line_same_brake" : "tip_line_turnin", m(l.0))) }
    if l.1 <= -1.5 { c.append((-l.1, "tip_line_apex", m(l.1))) }
    if l.2 >= 1.5 { c.append((l.2, "tip_line_exit", m(l.2))) }
    return c.max { $0.0 < $1.0 }.map { ($0.1, $0.2) }
}

/// The gear at a distance: the nearest row, not a blend of two gears.
private func gearAt(_ tr: Trace, _ d: Double) -> Double {
    if tr.rows.isEmpty || tr.bin <= 0 { return 0 }
    let i = max(0, min(tr.rows.count - 1, Int((d / tr.bin).rounded())))
    return tr.rows[i].count > 3 ? tr.rows[i][3] : 0
}

/// One place on the lap where time goes, with what is different there.
struct Loss: Hashable {
    let fromM: Int
    let lost: Double
    let brakeDiffM: Int?
    let minA: Double
    let minB: Double
    let throttleDiffM: Int?
}

private func at(_ tr: Trace, _ d: Double, _ k: Int) -> Double {
    if tr.rows.isEmpty || tr.bin <= 0 { return 0 }
    let x = d / tr.bin
    let i = max(0, min(tr.rows.count - 1, Int(x)))
    let j = min(i + 1, tr.rows.count - 1)
    let f = max(0, min(1, x - Double(i)))
    let a = k < tr.rows[i].count ? tr.rows[i][k] : 0
    let b = k < tr.rows[j].count ? tr.rows[j][k] : 0
    let v = a * (1 - f) + b * f
    return v.isFinite ? v : 0
}

func compare(_ a: Trace, _ b: Trace?, step step0: Double = 10) -> Compared {
    let len = Double(a.rows.count - 1) * a.bin
    let lenB = b.map { Double($0.rows.count - 1) * $0.bin } ?? len
    // at most 400 points per line: enough for a phone screen, light to draw and to touch
    let step = max(step0, min(len, lenB) / 400)
    let n = max(2, Int(min(len, lenB) / step))
    let d = (0..<n).map { Double($0) * step }
    let tA = d.map { at(a, $0, 5) }
    let tB = b.map { tr in d.map { at(tr, $0, 5) } }
    var line: [Double]? = nil
    var bxy: ([Double], [Double])? = nil
    if a.hasShape, let b, b.hasShape, abs(a.bin - b.bin) < 1e-6, let p = sameFrame(a, b) { bxy = p; line = lineOffsets(a.x!, a.y!, p.0, p.1) }
    var out = Compared(
        step: step,
        speedA: d.map { at(a, $0, 0) * 3.6 },
        speedB: b.map { tr in d.map { at(tr, $0, 0) * 3.6 } },
        thrA: d.map { at(a, $0, 1) },
        brkA: d.map { at(a, $0, 2) },
        delta: tB.map { tb in tA.indices.map { tA[$0] - tb[$0] } },
        tA: tA, tB: tB,
        thrB: b.map { tr in d.map { at(tr, $0, 1) } },
        brkB: b.map { tr in d.map { at(tr, $0, 2) } },
        gearA: d.map { gearAt(a, $0) },
        gearB: b.map { tr in d.map { gearAt(tr, $0) } }
    )
    if let line, let b, let bxy {
        let bx = bxy.0, by = bxy.1
        out.lat = d.map { let i = Int(($0 / a.bin).rounded()); return i < line.count ? line[i] : .nan }
        out.bx = d.map { bx[max(0, min(bx.count - 1, Int(($0 / b.bin).rounded())))] }
        out.by = d.map { by[max(0, min(by.count - 1, Int(($0 / b.bin).rounded())))] }
    }
    return out
}

/// One corner in four phases, as driver coaches read data: braking (brake point, how hard), entry
/// (releasing the brake into the turn, trail braking, coasting), apex (minimum speed) and exit (when
/// the throttle comes back). `tip` is an I18n key with `args`, about the phase that loses the most.
/// The same analysis as the web's braking coach and Android's LapMath.kt.
struct Corner: Hashable {
    let n: Int
    let atM: Int
    let lost: Double
    let phases: [String: Double]
    let phase: String?
    let coastA: Double
    let coastB: Double
    let tip: String?
    let args: [String]
    var lineTip: String? = nil  // what the line says, besides the tip
    var lineArgs: [String] = []
    var apexM: Int = 0          // the reference's slowest point, metres from the line: the same corner on the server (coachtips.js)
    var cls: String = ""        // the corner's speed there: slow (under 80 km/h), medium (under 150), fast
    // the braking points table (like the web's): A's brake point against B's (m, + A later; nil without one within 100 m),
    // the speed at each lap's slowest point (km/h), the gear there, and whether B takes the corner without braking (a lift)
    var dd: Int? = nil
    var vA: Double? = nil
    var vB: Double = 0
    var gearA: Int = 0
    var gearB: Int = 0
    var lift: Bool = false
}

/// A tip in a few words for the braking points table: without its figures in brackets (the columns carry them) and, of two
/// sentences, the one that says what to do (the last, unless it is only the measurement and the first is not), like the web's tipShort.
func tipShort(_ text: String) -> String {
    let plain = text.replacingOccurrences(of: "\\s*\\([^)]*\\)", with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    let q = plain.replacingOccurrences(of: "\\.\\s+", with: "\u{1}", options: .regularExpression).split(separator: "\u{1}")
        .map { s -> String in var x = s.trimmingCharacters(in: .whitespaces); if x.hasSuffix(".") { x.removeLast() }; return x.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    guard q.count >= 2, let first = q.first, let last = q.last else { return q.first ?? "" }
    let num: (String) -> Bool = { $0.range(of: "\\d", options: .regularExpression) != nil }
    return num(last) && !num(first) ? first : last
}

/// The corner card the model learnt (`corners` in /community/model): where the fastest drivers of this car and track
/// brake (b0..b1, metres from the line) and how fast they pass the slowest point (v0..v1, m/s) of one corner of the
/// record lap, from n drivers' best laps. A hint beside a tip, never a lap to compare with.
struct CornerCard: Hashable {
    let d: Double, apex: Double, b0: Double, b1: Double, v0: Double, v1: Double, n: Int
    /// the card of a corner whose slowest point is at `apexM` metres (within 60 m), or nil
    static func of(_ cards: [CornerCard], apexM: Int) -> CornerCard? {
        cards.filter { abs($0.apex - Double(apexM)) <= 60 }.min { abs($0.apex - Double(apexM)) < abs($1.apex - Double(apexM)) }
    }
}

let phaseKeys = ["brake", "entry", "apex", "exit"]

/// The official number of the turn nearest to a point of the lap (turns: fractions of the lap, T1 … Tn in order).
func turnNo(_ turns: [Double], at: Double, lapLen: Double, fallback: Int) -> Int {
    if turns.isEmpty || lapLen <= 0 { return fallback }
    let f = ((at / lapLen).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
    var bi = 0, bd = 2.0
    for (i, x) in turns.enumerated() { let d = min(abs(x - f), 1 - abs(x - f)); if d < bd { bd = d; bi = i } }
    return bi + 1
}

/// The pit lane of a track (from laps through the pits): [5 m point of a lap of n points, metres to the left of the track].
struct PitLane {
    let n: Int
    let pts: [(Int, Double)]
}

/// What the coach learnt from everyone's tips: the tips turned off, how many drivers each bucket helped, the confidence switch.
struct CoachInfo {
    let off: Set<String>
    let conf: [String: (Int, Int)]
    let confidence: Bool
    let min: Int
}
/// A kind of tip that repeats across the driver's tracks.
struct Habit: Hashable {
    let kind: String
    let tracks: Int
    let sessions: Int
}

func corners(_ c: Compared, turns: [Double] = [], off: Set<String> = []) -> [Corner] {
    guard let tB = c.tB, let sB = c.speedB, let bB = c.brkB, let hB = c.thrB else { return [] }
    let n = [c.tA.count, tB.count, sB.count, bB.count, hB.count, c.brkA.count, c.thrA.count, c.speedA.count].min() ?? 0
    if n < 10 { return [] }
    func bins(_ m: Double) -> Int { max(1, Int(m / c.step)) }
    func seg(_ x: Int, _ y: Int) -> Double { x < y ? (c.tA[y] - c.tA[x]) - (tB[y] - tB[x]) : 0 }
    // braking zones on the reference: from the brake to the slowest point before the throttle is back
    var zones: [(Int, Int)] = []
    var i = 1
    while i < n {
        if bB[i] > 0.12 && bB[i - 1] <= 0.12 {
            var k = i
            var imin = i
            while k < n && k < i + bins(600) && !(hB[k] > 0.6 && bB[k] < 0.05) {
                if sB[k] < sB[imin] { imin = k }
                k += 1
            }
            if sB[i] - sB[imin] > 15 { zones.append((i, imin)) }
            i = max(k, i + 1)
        } else {
            i += 1
        }
    }
    // the corners by the track's turns (the official ones, or the ones the layout's geometry gives): two brake applications in
    // one corner are one corner, and a turn taken without braking (a lift) is a corner of its own, like the web's cornerZones
    struct Z { var zi: Int; var zmin: Int; let turn: Int; let lift: Bool }
    var zs: [Z] = zones.map { Z(zi: $0.0, zmin: $0.1, turn: -1, lift: false) }
    if !turns.isEmpty {
        let ap = turns.map { Int($0 * Double(n)) }.filter { $0 >= 1 && $0 < n - 1 }
        func near(_ i: Int) -> Int { var b = -1, bd = Int.max; for (k, a) in ap.enumerated() { let d = abs(a - i); if d < bd { bd = d; b = k } }; return bd <= bins(150) ? b : -1 }
        var byTurn: [Int: Z] = [:]
        var loose: [Z] = []
        for (zi, zmin) in zones {
            let k = near(zmin)
            if k < 0 { loose.append(Z(zi: zi, zmin: zmin, turn: -1, lift: false)); continue }
            if var o = byTurn[k] { if sB[zmin] < sB[o.zmin] { o.zmin = zmin }; o.zi = min(o.zi, zi); byTurn[k] = o } else { byTurn[k] = Z(zi: zi, zmin: zmin, turn: k, lift: false) }
        }
        for (k, a) in ap.enumerated() where byTurn[k] == nil {
            var i0 = max(0, a - bins(100))
            for i in stride(from: a, to: max(1, a - bins(200)), by: -1) where hB[i] > 0.9 { i0 = i; break }
            var imin = a
            for i in i0..<min(n, a + bins(50)) where sB[i] < sB[imin] { imin = i }
            if sB[i0] - sB[imin] > 7 { byTurn[k] = Z(zi: i0, zmin: imin, turn: k, lift: true) }  // it really slows (7 km/h, like the web's 2 m/s)
        }
        zs = (Array(byTurn.values) + loose).sorted { $0.zi < $1.zi }
    }
    var out: [Corner] = []
    for (idx, z) in zs.enumerated() {
        let zi = z.zi, zmin = z.zmin
        let i0 = max(0, zi - bins(50)), i1 = min(n - 1, zmin + bins(150))
        let lost = seg(i0, i1)
        let vb = sB[zmin]  // km/h at the reference's slowest point
        let cls = vb < 80 ? "slow" : vb < 150 ? "medium" : "fast"
        // the same corner on this lap: its brake point within 100 m
        let w = bins(100)
        var ja: Int? = nil
        for j in max(1, zi - w)...min(n - 1, zi + w) where c.brkA[j] > 0.12 && c.brkA[j - 1] <= 0.12 {
            if ja == nil || abs(j - zi) < abs(ja! - zi) { ja = j }
        }
        var aMin: Int? = nil
        if let j = ja { aMin = (j...i1).min { c.speedA[$0] < c.speedA[$1] } }
        var ipb = zi
        for k in zi...zmin where bB[k] > bB[ipb] { ipb = k }
        let rel = (ipb...zmin).first { bB[$0] < 0.05 } ?? zmin
        let a0 = max(rel, zmin - bins(20)), a1 = min(i1, zmin + bins(20))
        let ph: [String: Double] = ["brake": seg(i0, rel), "entry": seg(rel, a0), "apex": seg(a0, a1), "exit": seg(a1, i1)]
        var coastA = 0.0, coastB = 0.0
        for k in i0...i1 {
            if c.thrA[k] < 0.05 && c.brkA[k] < 0.05 { coastA += c.step }
            if hB[k] < 0.05 && bB[k] < 0.05 { coastB += c.step }
        }
        var tip: String? = nil
        var args: [String] = []
        var phase: String? = nil
        if lost > 0.03 {
            phase = ph.max { $0.value < $1.value }?.key
            if z.lift && phase == "brake" { phase = "entry" }  // a corner taken without braking has no braking phase to speak of
            let dd: Int? = ja.map { Int(Double($0 - zi) * c.step) }
            var ipa = ja ?? 0
            if let j = ja, let m = aMin { for k in j...max(j, m) where c.brkA[k] > c.brkA[ipa] { ipa = k } }
            let pa = ja != nil ? c.brkA[ipa] : 0
            var trailA: Int? = nil
            if let m = aMin, ja != nil { trailA = Int(Double(((ipa...max(ipa, m)).first { c.brkA[$0] < 0.05 } ?? m) - ipa) * c.step) }
            let trailB = Int(Double(rel - ipb) * c.step)
            let dmin: Double? = aMin.map { c.speedA[$0] - sB[zmin] }
            var late: Int? = nil
            if let m = aMin, let pA = (m...max(m, i1)).first(where: { c.thrA[$0] > 0.5 }), let pB = (zmin...i1).first(where: { hB[$0] > 0.5 }) { late = Int(Double(pA - pB) * c.step) }
            // the gear through the corner and the lifts after the apex: what a generic tip gives way to
            let gA = aMin.flatMap { c.gearA?[safe: $0] }.map { Int($0) } ?? 0
            let gB = c.gearB?[safe: zmin].map { Int($0) } ?? 0
            func lifts(_ th: [Double], _ from: Int, _ to: Int) -> Int { var n = 0; var prev = -1.0; if from > min(to, th.count - 1) { return 0 }; for k in from...min(to, th.count - 1) { let t = th[k]; if prev >= 0 && prev > 0.8 && t < 0.5 { n += 1 }; prev = t }; return n }
            let lA = aMin.map { lifts(c.thrA, $0, i1) } ?? 0
            // how the throttle is opened after the apex: metres from picking it up (5 %) to full (95 %)
            func ramp(_ th: [Double], _ from: Int, _ to: Int) -> Int? { var a = -1; if from > min(to, th.count - 1) { return nil }; for k in from...min(to, th.count - 1) { if a < 0 && th[k] > 0.05 { a = k }; if a >= 0 && th[k] > 0.95 { return Int(Double(k - a) * c.step) } }; return nil }
            let rampA = aMin.flatMap { ramp(c.thrA, $0, i1) }
            let rampB = ramp(hB, zmin, i1)
            let lB = lifts(hB, zmin, i1)
            // braking later than the reference and arriving slower at the apex is one mistake, whatever phase pays for it
            if let d = dd, let dm = dmin, d > 6, dm < -2 { tip = "tip_brake_late_apex"; args = ["\(d)", "\(Int(-dm))"] } else {
            switch phase ?? "" {
            case "brake":
                if let d = dd, d < -6 { tip = "tip_brake_later"; args = ["\(-d)"] }
                else if ja != nil && pa < bB[ipb] - 0.05 { tip = "tip_brake_harder"; args = ["\(Int(pa * 100))", "\(Int(bB[ipb] * 100))"] }
                else if let d = dd, d > 6 { tip = "tip_brake_earlier"; args = ["\(d)"] }
                else if let ta = trailA, trailB - ta >= 15 { tip = "tip_trail"; args = ["\(ta)", "\(trailB)"] }
                else if dd != nil { tip = "tip_brake_same" }
                else { tip = "tip_brake_generic" }
            case "entry":
                if let ta = trailA, trailB - ta >= 15 { tip = "tip_trail"; args = ["\(ta)", "\(trailB)"] }
                else if coastA - coastB >= 10 { tip = "tip_coast"; args = ["\(Int(coastA))", "\(Int(coastB))"] }
                else if let dm = dmin, dm >= 0 { tip = "tip_entry_before" }
                else { tip = "tip_entry_speed" }
            case "apex":
                if let dm = dmin, dm < -2 { tip = "tip_apex_speed"; args = ["\(Int(-dm))"] } else if let dm = dmin, dm >= 0 { tip = "tip_apex_longer" } else { tip = "tip_apex_line" }
            default:
                if let l = late, l >= 8 { tip = "tip_throttle"; args = ["\(l)"] }
                else if let ra = rampA, let rb = rampB, rb - ra >= 15, lA > lB { tip = "tip_throttle_rough"; args = ["\(ra)", "\(rb)"] }
                else if let ra = rampA, let rb = rampB, ra - rb >= 15 { tip = "tip_throttle_slow"; args = ["\(ra)", "\(rb)"] }
                else if coastA - coastB >= 10 { tip = "tip_no_wait" }
                else if let l = late, let dm = dmin, l <= -8, dm < -1 { tip = "tip_exit_speed"; args = ["\(-l)", "\(Int(-dm))"] }
                else { tip = "tip_full_throttle" }
            }
            }
            if GENERIC_TIPS.contains(tip ?? "") {
                if gA >= 1 && gB >= 1 && gB > gA { tip = "tip_gear_up"; args = ["\(gB)", "\(gA)"] }
                else if gA >= 1 && gB >= 1 && gB < gA { tip = "tip_gear_down"; args = ["\(gB)", "\(gA)"] }
                else if phase == "exit" && lA >= 2 && lA > lB + 1 { tip = "tip_lifts"; args = ["\(lA)", "\(lB)"] }
            }
            // a tip an admin turned off for corners of this speed gives way to the phase's plain tip (like the web)
            if let tp = tip, off.contains(String(tp.dropFirst(4)) + "|" + cls) {
                tip = phase == "entry" ? "tip_entry_speed" : phase == "apex" ? "tip_apex_line" : phase == "exit" ? "tip_full_throttle" : "tip_brake_generic"
                args = []
            }
        }
        // the line: where the car was across the track; braking at the reference's point but on the wrong part of the
        // track is said first, a generic tip gives way to it, otherwise it goes under the tip
        var lineKey: String? = nil, lineArgs: [String] = []
        if lost > 0.03 {
            let dd: Int? = ja.map { Int(Double($0 - zi) * c.step) }
            let same = dd.map { abs($0) <= 6 } ?? false
            if let lt = lineTip(cornerLine(c, brake: zi, apex: zmin, exit: zmin + bins(80), span: bins(40)), sameBrake: same) {
                if GENERIC_TIPS.contains(tip ?? "") || (phase == "brake" && same) { tip = lt.0; args = [lt.1] }
                else { lineKey = lt.0; lineArgs = [lt.1] }
            }
        }
        out.append(Corner(n: z.turn >= 0 ? z.turn + 1 : turnNo(turns, at: Double(zmin) * c.step, lapLen: Double(n) * c.step, fallback: idx + 1), atM: Int(Double(zi) * c.step), lost: lost, phases: ph, phase: phase, coastA: coastA, coastB: coastB, tip: tip, args: args, lineTip: lineKey, lineArgs: lineArgs,
                          apexM: Int(Double(zmin) * c.step), cls: cls,
                          dd: ja.map { Int(Double($0 - zi) * c.step) }, vA: aMin.map { c.speedA[$0] }, vB: vb,
                          gearA: c.gearA?[safe: aMin ?? zmin].map { Int($0) } ?? 0, gearB: c.gearB?[safe: zmin].map { Int($0) } ?? 0, lift: z.lift))
    }
    return out
}

/// The tips that say nothing the data showed: what the data shows plainly (the gear, lifts, the line) replaces them.
let GENERIC_TIPS: Set<String> = ["tip_brake_generic", "tip_entry_speed", "tip_apex_line", "tip_full_throttle", "tip_brake_same", "tip_entry_before", "tip_apex_longer"]

/// Where a lap starts braking (brake over 12 % after being below), in metres, from a series on the `step` grid.
func brakePoints(_ brk: [Double]?, _ step: Double) -> [Double] {
    guard let brk, brk.count >= 3 else { return [] }
    var out: [Double] = []
    var i = 1
    while i < brk.count {
        if brk[i] > 0.12 && brk[i - 1] <= 0.12 {
            out.append(Double(i) * step)
            var k = i
            while k < brk.count && k < i + 60 && brk[k] > 0.05 { k += 1 }
            i = k + 1
        } else { i += 1 }
    }
    return out
}

func losses(_ c: Compared, segM: Double = 250) -> [Loss] {
    guard let tB = c.tB, let speedB = c.speedB, c.tA.count > 1 else { return [] }
    let per = max(1, Int(segM / c.step))
    var out: [Loss] = []
    var s = 0
    while s < c.tA.count - 1 {
        let e = min(c.tA.count - 1, s + per)
        let lost = (c.tA[e] - c.tA[s]) - (tB[e] - tB[s])
        let r = s...e
        let minA = r.map { c.speedA[$0] }.min() ?? 0
        let minB = r.map { speedB[$0] }.min() ?? 0
        // braking: the reference has no brake channel here, so use where its speed starts to drop
        let bA = r.first { c.brkA[$0] > 0.3 }
        let bB = (s..<e).first { $0 + 2 <= e && speedB[$0 + 2] < speedB[$0] - 3 }
        let brakeDiff = (bA != nil && bB != nil) ? Int(Double(bA! - bB!) * c.step) : nil
        let fullA = r.first { c.thrA[$0] > 0.95 && c.speedA[$0] > minA + 2 }
        let minIdxB = r.min { speedB[$0] < speedB[$1] } ?? s
        let fullB = r.first { speedB[$0] > minB + 2 && $0 > minIdxB }
        let thrDiff = (fullA != nil && fullB != nil) ? Int(Double(fullA! - fullB!) * c.step) : nil
        out.append(Loss(fromM: Int(Double(s) * c.step), lost: lost, brakeDiffM: brakeDiff, minA: minA, minB: minB, throttleDiffM: thrDiff))
        s = e
    }
    return Array(out.filter { $0.lost > 0.02 }.sorted { $0.lost > $1.lost }.prefix(3))
}

extension RaceResult: Identifiable { var id: String { "\(pos)|\(name)" } }

extension Array {
    /// The element at an index, or nil when it is out of the array
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
