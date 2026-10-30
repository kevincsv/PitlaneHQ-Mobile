import Foundation

/// One week of a series: its track and layout, the length (laps or minutes), when its races start and the rain chance.
/// The start times follow iRacing's race_time_descriptors: every `every` minutes from `first` ("HH:MM" UTC) on `days`
/// (offsets from `base`, all days when empty), or the set `times`.
final class SWeek: Hashable {
    let k: Int, start: Double, end: Double, trackId: Int64, track: String, cfg: String, cat: String
    let laps: Int, mins: Int, rain: Int, carIds: [Int64]
    var rep: Bool, first: String, every: Int, days: [Int], base: Double, times: [Double]
    init(k: Int, start: Double, end: Double, trackId: Int64, track: String, cfg: String, cat: String, laps: Int, mins: Int, rain: Int, carIds: [Int64],
         rep: Bool, first: String, every: Int, days: [Int], base: Double, times: [Double]) {
        self.k = k; self.start = start; self.end = end; self.trackId = trackId; self.track = track; self.cfg = cfg; self.cat = cat
        self.laps = laps; self.mins = mins; self.rain = rain; self.carIds = carIds
        self.rep = rep; self.first = first; self.every = every; self.days = days; self.base = base; self.times = times
    }
    static func == (a: SWeek, b: SWeek) -> Bool { a === b }
    func hash(into h: inout Hasher) { h.combine(ObjectIdentifier(self)) }
}

struct SSeries: Hashable {
    let id: Int64, sid: Int64, name: String, lic: Int, fixed: Bool, multi: Bool, desc: String
    let inc: Int, drops: Int, carIds: [Int64], weeks: [SWeek]
    static func == (a: SSeries, b: SSeries) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

final class SeasonData {
    let series: [SSeries]
    let tracks: [Int64: (String, String)]
    let cars: [Int64: String]
    var racedTracks = Set<Int64>()
    var racedCars = Set<Int64>()
    init(series: [SSeries], tracks: [Int64: (String, String)], cars: [Int64: String]) { self.series = series; self.tracks = tracks; self.cars = cars }
}

/// One race in the plan: the series and its start (epoch ms).
struct PlannedRace: Codable, Hashable { let sid: Int64; let t: Double; let name: String; let track: String }

/// The web planner's maths, the same answers on every device (and the same as Android's Season.kt): the race starts of
/// a week, this week, the next race, and which tracks and cars the account owns, known only from what it raced: a track
/// counts with all its layouts, and the sim's names are matched to the season's by the words they share.
enum Season {
    static let DAY = 86_400_000.0
    private static let MIN = 60_000.0

    private static func i64(_ v: Any?) -> Int64 { (v as? NSNumber)?.int64Value ?? 0 }
    private static func int(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }
    private static func s(_ v: Any?) -> String { v as? String ?? "" }
    private static let dayFmt: DateFormatter = { let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "yyyy-MM-dd"; return f }()
    private static func day(_ x: String) -> Double { dayFmt.date(from: String(x.prefix(10))).map { $0.timeIntervalSince1970 * 1000 } ?? 0 }
    private static func time(_ x: String) -> Double {
        let f = ISO8601DateFormatter()
        if let d = f.date(from: x) { return d.timeIntervalSince1970 * 1000 }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: x).map { $0.timeIntervalSince1970 * 1000 } ?? 0
    }

    static func parse(_ root: [String: Any], owned: [String: Any]?) -> SeasonData {
        let j = root["season"] as? [String: Any] ?? [:]
        var tracks: [Int64: (String, String)] = [:]
        for x in j["tracks"] as? [[String: Any]] ?? [] { tracks[i64(x["track_id"])] = (s(x["track_name"]), s(x["config_name"])) }
        var cars: [Int64: String] = [:]
        for x in j["cars"] as? [[String: Any]] ?? [] { cars[i64(x["car_id"])] = s(x["car_name"]) }
        var classes: [Int64: [Int64]] = [:]
        for c in j["classes"] as? [[String: Any]] ?? [] { classes[i64(c["car_class_id"])] = (c["cars_in_class"] as? [[String: Any]] ?? []).map { i64($0["car_id"]) } }
        var out: [SSeries] = []
        for x in j["seasons"] as? [[String: Any]] ?? [] {
            if (x["active"] as? Bool) == false || (x["complete"] as? Bool) == true { continue }
            let sch = x["schedules"] as? [[String: Any]] ?? []
            let weeks: [SWeek] = sch.enumerated().map { k, w in
                let r = (w["race_time_descriptors"] as? [[String: Any]])?.first ?? [:]
                let wx = (w["weather"] as? [String: Any])?["weather_summary"] as? [String: Any]
                let tr = w["track"] as? [String: Any] ?? [:]
                let st = day(s(w["start_date"]))
                let en0 = time(s(w["week_end_time"]))
                let tid = i64(tr["track_id"])
                return SWeek(
                    k: (w["race_week_num"] as? NSNumber)?.intValue ?? k, start: st, end: en0 > 0 ? en0 : st + 7 * DAY, trackId: tid,
                    track: tracks[tid]?.0 ?? s(tr["track_name"]), cfg: tracks[tid]?.1 ?? s(tr["config_name"]),
                    cat: s(w["category"]), laps: int(w["race_lap_limit"]), mins: int(w["race_time_limit"]), rain: int(wx?["precip_chance"]),
                    carIds: (w["race_week_cars"] as? [[String: Any]] ?? []).map { i64($0["car_id"]) },
                    rep: r["repeating"] as? Bool ?? false, first: s(r["first_session_time"]), every: int(r["repeat_minutes"]),
                    days: (r["day_offset"] as? [NSNumber] ?? []).map { $0.intValue },
                    base: s(r["start_date"]).isEmpty ? st : day(s(r["start_date"])),
                    times: (r["session_times"] as? [String] ?? []).map(time).filter { $0 > 0 })
            }
            if weeks.isEmpty { continue }
            let n = s(sch.first?["series_name"])
            out.append(SSeries(
                id: i64(x["season_id"]), sid: i64(x["series_id"]), name: n.isEmpty ? s(x["season_name"]) : n, lic: (x["license_group"] as? NSNumber)?.intValue ?? 1,
                fixed: x["fixed_setup"] as? Bool ?? false, multi: x["multiclass"] as? Bool ?? false, desc: s(x["schedule_description"]),
                inc: int(x["incident_limit"]), drops: int(x["drops"]),
                carIds: uniq((x["car_class_ids"] as? [NSNumber] ?? []).flatMap { classes[$0.int64Value] ?? [] }), weeks: weeks))
        }
        let d = SeasonData(series: out, tracks: tracks, cars: cars)
        if let seen = root["seen"] as? [String: Any] { applySeen(d, seen) }
        if let owned { raced(d, owned) }
        return d
    }
    private static func uniq(_ a: [Int64]) -> [Int64] { var seen = Set<Int64>(); return a.filter { seen.insert($0).inserted } }

    // ---------- the race starts (the web's sessions) ----------
    private static func hmMin(_ x: String) -> Int {
        let p = (x.isEmpty ? "00:00" : x).split(separator: ":")
        return (p.count > 0 ? Int(p[0]) ?? 0 : 0) * 60 + (p.count > 1 ? Int(p[1]) ?? 0 : 0)
    }
    static func starts(_ w: SWeek, _ from0: Double, _ to0: Double) -> [Double] {
        let from = max(from0, w.start), to = min(to0, w.end)
        var out: [Double] = []
        if to <= from { return out }
        if w.rep && w.every > 0 {
            let first = Double(hmMin(w.first)) * MIN
            let days = w.days.isEmpty ? Array(0...6) : w.days
            for k in 0..<8 {
                let dayStart = w.base + Double(k) * 7 * DAY
                if dayStart > to { break }
                for dd in days {
                    let ds = dayStart + Double(dd) * DAY
                    if ds + DAY < from || ds > to { continue }
                    var t = ds + first
                    while t < ds + DAY { if t >= from && t < to { out.append(t) }; t += Double(w.every) * MIN }
                }
            }
        } else { out = w.times.filter { $0 >= from && $0 < to } }
        return out.sorted()
    }
    static func curWeek(_ s: SSeries, _ now: Double) -> SWeek? { s.weeks.first { now >= $0.start && now < $0.end } }
    static func weekAt(_ s: SSeries, _ t: Double) -> SWeek { s.weeks.first { t >= $0.start && t < $0.end } ?? s.weeks[0] }
    static func nextRace(_ s: SSeries, _ now: Double) -> (Double, SWeek)? {
        for w in s.weeks where w.end >= now { if let t = starts(w, now, now + 14 * DAY).first { return (t, w) } }
        return nil
    }
    /// The discipline of the series: this week's, else its first week's.
    static func cat(_ s: SSeries, _ now: Double) -> String { let c = (curWeek(s, now) ?? s.weeks[0]).cat; return c.isEmpty ? "sports_car" : c }
    /// The cars of a week (its own list, else the series' classes).
    static func carsOf(_ s: SSeries, _ w: SWeek?) -> [Int64] { uniq((w?.carIds.isEmpty == false ? w!.carIds : s.carIds)) }
    static func ownTrack(_ d: SeasonData, _ w: SWeek) -> Bool { d.racedTracks.contains(w.trackId) }
    static func ownCar(_ d: SeasonData, _ s: SSeries, _ w: SWeek?) -> Bool { carsOf(s, w).contains { d.racedCars.contains($0) } }

    // ---------- names: "Tsukuba Circuit 2k Full" is "Tsukuba Circuit · 2000 Full" (the web's ownToks/ownBest) ----------
    static func toks(_ x: String) -> [String] {
        var v = x.folding(options: [.diacriticInsensitive], locale: nil).lowercased()
        if let re = try? NSRegularExpression(pattern: "\\b(\\d+)k\\b") {
            for m in re.matches(in: v, range: NSRange(v.startIndex..., in: v)).reversed() {
                if let r = Range(m.range, in: v), let g = Range(m.range(at: 1), in: v), let n = Int(v[g]) { v.replaceSubrange(r, with: String(n * 1000)) }
            }
        }
        return v.split(whereSeparator: { !($0.isASCII && ($0.isLetter || $0.isNumber)) }).map(String.init)
            .filter { !$0.isEmpty && ($0.count > 1 || $0.contains { $0.isNumber }) }
    }
    private static func score(_ a: [String], _ b: [String]) -> Double {
        if a.isEmpty || b.isEmpty { return 0 }
        func eq(_ x: String, _ y: String) -> Bool { x == y || (min(x.count, y.count) >= 3 && (x.contains(y) || y.contains(x))) }
        return 2.0 * Double(a.filter { x in b.contains { eq(x, $0) } }.count) / Double(a.count + b.count)
    }
    private static func best(_ forms: [[String]], _ cands: [(Int64, [[String]])]) -> [Int64] {
        var bestS = 0.0, out: [Int64] = []
        for (id, cf) in cands {
            let sc = forms.map { f in cf.map { score(f, $0) }.max() ?? 0 }.max() ?? 0
            if sc > bestS + 1e-9 { bestS = sc; out = [id] } else if abs(sc - bestS) < 1e-9 { out.append(id) }
        }
        return bestS >= 0.6 ? out : []
    }
    private static func trackCands(_ d: SeasonData) -> [(Int64, [[String]])] { d.tracks.map { ($0.key, [toks($0.value.0), toks($0.value.0 + " " + $0.value.1)]) } }
    private static func carCands(_ d: SeasonData) -> [(Int64, [[String]])] { d.cars.map { ($0.key, [toks($0.value)]) } }

    private static func raced(_ d: SeasonData, _ r: [String: Any]) {
        let tc = trackCands(d), cc = carCands(d)
        for x in r["tracks"] as? [[Any]] ?? [] {
            let n = s(x.first), cfg = x.count > 1 ? s(x[1]) : ""
            for id in best([toks(n), toks(n + " " + cfg)], tc) {
                let nm = d.tracks[id]?.0
                for (j, y) in d.tracks where y.0 == nm { d.racedTracks.insert(j) }
            }
        }
        for c in r["cars"] as? [String] ?? [] { for id in best([toks(c)], cc) { d.racedCars.insert(id) } }
    }

    // ---------- when official races really started, as the PCs saw it (the web's applySeen/seenFix) ----------
    private static func key(_ w: SWeek) -> String { "\(w.rep)|\(w.first)|\(w.every)|\(w.days)" }
    private static func obsOf(_ v: Any?) -> [Double] { (v as? [[Any]] ?? []).compactMap { ($0.first as? NSNumber)?.doubleValue } }
    private static func applySeen(_ d: SeasonData, _ seen: [String: Any]) {
        let ids = Set(d.series.map { String($0.id) })
        for s in d.series {
            let obs = seen[String(s.id)].map(obsOf) ?? seenByName(d, s, seen, ids)
            if obs.isEmpty { continue }
            for w in s.weeks {
                let o = obs.filter { $0 >= w.start && $0 < w.end }
                if o.isEmpty { continue }
                let p = starts(w, w.start, w.end)
                if !p.isEmpty && o.allSatisfy({ t in p.contains { abs($0 - t) <= 3 * MIN } }) { continue }
                let k = key(w)
                guard let fix = seenFix(w, o) else { continue }
                for x in s.weeks where x === w || (x.start > w.start && key(x) == k && !obs.contains { $0 >= x.start && $0 < x.end }) { fix(x) }
            }
        }
    }
    private static func seenByName(_ d: SeasonData, _ s: SSeries, _ seen: [String: Any], _ ids: Set<String>) -> [Double] {
        let tc = trackCands(d), cc = carCands(d)
        func fits(_ e: [Any]) -> Bool {
            guard e.count > 4, let t0 = (e[0] as? NSNumber)?.doubleValue, let w = s.weeks.first(where: { t0 >= $0.start && t0 < $0.end }) else { return false }
            let tn = Season.s(e[2]), car = Season.s(e[4])
            if tn.isEmpty || car.isEmpty { return false }
            let cfg0 = Season.s(e[3]), cfg = cfg0.contains(":") ? "" : cfg0
            if !best([toks(tn), toks(tn + " " + cfg)], tc).contains(w.trackId) { return false }
            let cs = Set(best([toks(car)], cc))
            return carsOf(s, w).contains { cs.contains($0) }
        }
        let hit = seen.filter { !ids.contains($0.key) }.compactMap { kv -> [[Any]]? in
            guard let a = kv.value as? [[Any]], !a.isEmpty, a.allSatisfy(fits) else { return nil }
            return a
        }
        return hit.count == 1 ? obsOf(hit[0]) : []
    }
    private static func seenFix(_ w: SWeek, _ o: [Double]) -> ((SWeek) -> Void)? {
        func mod(_ a: Int, _ b: Int) -> Int { ((a % b) + b) % b }
        let mins = Array(Set(o.map { Int(((($0.truncatingRemainder(dividingBy: DAY)) + DAY).truncatingRemainder(dividingBy: DAY) / MIN).rounded()) }))
        func hm(_ m: Int) -> String { String(format: "%02d:%02d", m / 60, m % 60) }
        if w.rep && w.every > 0 {
            let f = hmMin(w.first), m = w.every
            let sh = mins.map { mod($0 - f, m) }
            var bestB: Int? = nil, n = 0
            for b in sh { let c = sh.filter { x in min(mod(x - b, m), mod(b - x, m)) <= 3 }.count; if c > n { n = c; bestB = b } }
            if let b = bestB, n * 2 > sh.count { var nf = f + b; if nf >= 1440 { nf -= m }; let v = hm(max(0, nf)); return { $0.first = v } }
        } else if !w.times.isEmpty { return nil }
        if mins.count < 3 { return nil }
        let st = Array(Set(o.map { Int(($0 / (5 * MIN)).rounded()) * 5 })).sorted()
        func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
        var g = 0
        for i in 1..<st.count { g = gcd(g, st[i] - st[0]) }
        if g < 15 || g > 1440 { return nil }
        let first = hm(mod(mins.min()!, g))
        return { $0.rep = true; $0.every = g; $0.first = first; $0.days = []; $0.times = [] }
    }
}
