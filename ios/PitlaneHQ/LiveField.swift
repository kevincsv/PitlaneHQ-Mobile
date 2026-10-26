import Foundation
import CryptoKit

/// One driver of the live session, from the session YAML the PC sends (DriverInfo → Drivers).
struct LiveDriver {
    let idx: Int
    let name: String
    let number: String
    let cls: String
    let ir: Int
    let lic: String
    let pace: Bool
    let spectator: Bool
    let ai: Bool
    let key: String
}

/// What the session YAML says that the Telemetry screens need: who is who, the track, the session kinds.
struct LiveSession {
    var me = -1
    var estLap = 0.0
    var track = ""
    var trackId: Int64 = 0
    var trackLen = 0.0 // m
    var drivers: [Int: LiveDriver] = [:]
    var kinds: [Int: String] = [:]
    var laps: [Int: Int] = [:]
}

/// A car in the standings or the relative: its place, its gap (s) and how many laps up (+) or down (−) on you.
struct LiveRow: Identifiable {
    let idx: Int
    let pos: Int
    let d: LiveDriver?
    let gap: Double?
    let last: Double?
    let best: Double?
    let lapDiff: Double
    let pit: Bool
    let me: Bool
    var id: Int { idx }
}

private func yField(_ block: String, _ key: String) -> String {
    for line in block.split(separator: "\n", omittingEmptySubsequences: false) {
        let l = line.trimmingCharacters(in: .whitespaces)
        if l.hasPrefix(key + ":") {
            return String(l.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
    }
    return ""
}

/// a top-level section of the YAML ("DriverInfo:" and what follows until the next top-level key)
private func ySection(_ y: String, _ name: String) -> String {
    let lines = y.split(separator: "\n", omittingEmptySubsequences: false)
    var out: [Substring] = []
    var on = false
    for l in lines {
        if on {
            if let c = l.first, !c.isWhitespace { break }
            out.append(l)
        } else if l.hasPrefix(name + ":") {
            on = true
            out.append(l)
        }
    }
    return out.joined(separator: "\n")
}

/// the items of a YAML list whose entries start with "- key:"
private func yItems(_ section: String, _ key: String) -> [String] {
    var out: [String] = []
    var cur: [String]? = nil
    for l in section.split(separator: "\n", omittingEmptySubsequences: false) {
        let s = String(l)
        if s.trimmingCharacters(in: .whitespaces).hasPrefix("- " + key + ":") {
            if let c = cur { out.append(c.joined(separator: "\n")) }
            cur = [s.replacingOccurrences(of: "- ", with: "  ", options: [], range: s.range(of: "- "))]
        } else if cur != nil {
            cur!.append(s)
        }
    }
    if let c = cur { out.append(c.joined(separator: "\n")) }
    return out
}

/// The community's opaque key of a driver (the PC's driverKey): what your driver notes find them by.
func driverKey(_ userId: String) -> String {
    let u = userId.trimmingCharacters(in: .whitespaces)
    if u.isEmpty || u == "-1" || u == "0" { return "" }
    let h = SHA256.hash(data: Data(("pitlanehq-other|" + u).utf8))
    return h.prefix(16).map { String(format: "%02x", $0) }.joined()
}

func parseLiveSession(_ y: String) -> LiveSession {
    let di = ySection(y, "DriverInfo"), wi = ySection(y, "WeekendInfo"), si = ySection(y, "SessionInfo")
    var s = LiveSession()
    s.me = Int(yField(di, "DriverCarIdx")) ?? -1
    s.estLap = Double(yField(di, "DriverCarEstLapTime")) ?? 0
    let cfg = yField(wi, "TrackConfigName")
    s.track = yField(wi, "TrackDisplayName") + (cfg.isEmpty ? "" : " · " + cfg)
    s.trackId = Int64(yField(wi, "TrackID")) ?? 0
    let tl = yField(wi, "TrackLength")
    if let r = tl.range(of: "[0-9.]+", options: .regularExpression), let km = Double(tl[r]) { s.trackLen = km * 1000 }
    for b in yItems(di, "CarIdx") {
        guard let i = Int(yField(b, "CarIdx")) else { continue }
        s.drivers[i] = LiveDriver(idx: i, name: yField(b, "UserName"), number: yField(b, "CarNumber"), cls: yField(b, "CarClassShortName"),
                                  ir: Int(yField(b, "IRating")) ?? 0, lic: yField(b, "LicString"), pace: yField(b, "CarIsPaceCar") == "1",
                                  spectator: yField(b, "IsSpectator") == "1", ai: yField(b, "CarIsAI") == "1", key: driverKey(yField(b, "UserID")))
    }
    for b in yItems(si, "SessionNum") {
        guard let n = Int(yField(b, "SessionNum")) else { continue }
        s.kinds[n] = yField(b, "SessionType")
        if let l = Int(yField(b, "SessionLaps")) { s.laps[n] = l }
    }
    return s
}

extension Live {
    private func arr(_ n: String) -> [Double] { arrays[n] ?? [] }
    private func at(_ a: [Double], _ i: Int) -> Double? { i >= 0 && i < a.count ? a[i] : nil }

    /// your car (the stream's PlayerCarIdx, else the session's DriverCarIdx)
    var meIdx: Int { num("PlayerCarIdx").map { Int($0) } ?? session?.me ?? -1 }

    /// an estimate of the lap time, for the gaps of the relative
    var estLap: Double {
        if let e = session?.estLap, e > 0 { return e }
        if let b = num("LapBestLapTime"), b > 0 { return b }
        if let l = num("LapLastLapTime"), l > 0 { return l }
        return 100
    }

    private func lapDiff(_ i: Int, _ me: Int) -> Double {
        let lap = arr("CarIdxLap"), pct = arr("CarIdxLapDistPct")
        return ((at(lap, i) ?? 0) + (at(pct, i) ?? 0)) - ((at(lap, me) ?? 0) + (at(pct, me) ?? 0))
    }

    private func pos0(_ v: Double?) -> Double? { v.flatMap { $0 > 0 ? $0 : nil } }

    /// The standings: every car with a place, in order, with its gap to the leader, last and best lap.
    func standings() -> [LiveRow] {
        let pos = arr("CarIdxPosition"), me = meIdx, f2 = arr("CarIdxF2Time")
        let last = arr("CarIdxLastLapTime"), best = arr("CarIdxBestLapTime"), pit = arr("CarIdxOnPitRoad")
        var rows: [LiveRow] = []
        for i in pos.indices where pos[i] > 0 {
            let d = session?.drivers[i]
            if let d = d, d.pace || d.spectator { continue }
            rows.append(LiveRow(idx: i, pos: Int(pos[i]), d: d, gap: pos0(at(f2, i)), last: pos0(at(last, i)), best: pos0(at(best, i)),
                                lapDiff: me >= 0 ? lapDiff(i, me) : 0, pit: (at(pit, i) ?? 0) != 0, me: i == me))
        }
        return rows.sorted { $0.pos < $1.pos }
    }

    /// The relative: the cars just ahead (gap < 0) and behind (gap > 0) on track, by the time to reach them.
    func relative(_ each: Int = 3) -> [LiveRow] {
        let me = meIdx, pct = arr("CarIdxLapDistPct"), est = arr("CarIdxEstTime"), pos = arr("CarIdxPosition")
        let last = arr("CarIdxLastLapTime"), best = arr("CarIdxBestLapTime"), pit = arr("CarIdxOnPitRoad")
        if me < 0 || pct.isEmpty { return [] }
        let l = estLap
        var rows: [LiveRow] = []
        for i in pct.indices where pct[i] >= 0 {
            let d = session?.drivers[i]
            if let d = d, d.pace || d.spectator { continue }
            var g = (at(est, i) ?? 0) - (at(est, me) ?? 0)
            if g > l / 2 { g -= l }
            if g < -l / 2 { g += l }
            rows.append(LiveRow(idx: i, pos: Int(at(pos, i) ?? 0), d: d, gap: g, last: pos0(at(last, i)), best: pos0(at(best, i)),
                                lapDiff: lapDiff(i, me), pit: (at(pit, i) ?? 0) != 0, me: i == me))
        }
        let ahead = Array(rows.filter { !$0.me && ($0.gap ?? 0) < 0 }.sorted { ($0.gap ?? 0) > ($1.gap ?? 0) }.prefix(each).reversed())
        let behind = Array(rows.filter { !$0.me && ($0.gap ?? 0) >= 0 }.sorted { ($0.gap ?? 0) < ($1.gap ?? 0) }.prefix(each))
        return ahead + rows.filter { $0.me } + behind
    }

    /// The gaps to the cars just ahead of and behind you in the standings (s, nil when none).
    func aheadBehind() -> (Double?, Double?) {
        let st = standings()
        guard let m = st.first(where: { $0.me }) else { return (nil, nil) }
        func g(_ x: LiveRow?) -> Double? { guard let xg = x?.gap, let mg = m.gap else { return nil }; return abs(mg - xg) }
        return (g(st.first { $0.pos == m.pos - 1 }), g(st.first { $0.pos == m.pos + 1 }))
    }
}

/// The laps this phone sees, every 5 m, so that in DRINKS mode whoever is driving is measured against their own best
/// lap (the game's best is the car's, whoever drove it): the same as the PC's overlays and app.
final class LiveLaps {
    private final class Lap {
        let n: Int
        let drv: String
        var t: [Double] = []
        var pit = false
        var time = 0.0
        init(n: Int, drv: String) { self.n = n; self.drv = drv }
    }
    private var cur: Lap?
    private var done: [Lap] = []

    func add(_ v: [String: Double], driver: String) {
        guard let lcv = v["LapCompleted"], let d = v["LapDist"], let t = v["LapCurrentLapTime"] else { return }
        let lc = Int(lcv)
        guard let c = cur, c.n == lc else {
            if let c = cur, lc == c.n + 1, c.t.count > 40 {
                c.time = (v["LapLastLapTime"] ?? 0) > 0 ? v["LapLastLapTime"]! : c.t.last!
                done.append(c)
                if done.count > 40 { done.removeFirst() }
            }
            cur = Lap(n: lc, drv: driver)
            return
        }
        if (v["OnPitRoad"] ?? 0) != 0 { c.pit = true }
        if d < 0 || (d < 60 && t > 8) { return }
        let b = Int(d / 5)
        while c.t.count <= b { c.t.append(c.t.last ?? t) }
        c.t[b] = t
    }

    private func best(_ driver: String) -> Lap? { done.filter { $0.drv == driver && !$0.pit && $0.time > 0 }.min { $0.time < $1.time } }

    func bestTime(_ driver: String) -> Double? { best(driver)?.time }

    /// the current lap against the driver's own best at the same point of the lap
    func delta(_ v: [String: Double], driver: String) -> Double? {
        guard let b = best(driver), let d = v["LapDist"], let t = v["LapCurrentLapTime"] else { return nil }
        let i = Int(d / 5)
        if d < 20 || i < 0 || i >= b.t.count { return nil }
        return t - b.t[i]
    }
}

/// One lap this phone saw, every 5 m: speed (m/s), the lap's time there (s), throttle and brake (0–1) and gear.
final class RecLap {
    let n: Int
    var sp: [Double] = [], t: [Double] = [], thr: [Double] = [], brk: [Double] = [], gear: [Int] = []
    var time = 0.0
    var pit = false
    init(n: Int) { self.n = n }
    var size: Int { t.count }
}

/// The laps of the session this phone watches, for Telemetry's Full mode (the traces of the lap) and Compare laps (the
/// lap now against your best, your last lap or another one, live), and your place at the end of every lap (Standings).
final class LiveRec {
    private(set) var laps: [RecLap] = []
    private(set) var cur: RecLap?
    private(set) var posHist: [(lap: Int, pos: Int)] = []
    private(set) var ver = 0
    private var waitLast: RecLap?
    private var lastSeen = -1.0

    func clear() { laps = []; cur = nil; posHist = []; waitLast = nil; lastSeen = -1; ver += 1 }

    func add(_ v: [String: Double]) {
        guard let lcv = v["LapCompleted"], let d = v["LapDist"], let t = v["LapCurrentLapTime"] else { return }
        let lc = Int(lcv)
        let last = v["LapLastLapTime"] ?? -1
        // the game says the lap's time a moment after the line: it is this lap's once it changes
        if let w = waitLast, last > 0, last != lastSeen { w.time = last; waitLast = nil; lastSeen = last; ver += 1 }
        guard let c = cur, c.n == lc else {
            if let c = cur, lc == c.n + 1, c.size > 40 {
                c.time = c.t.last ?? 0; waitLast = c; laps.append(c); if laps.count > 30 { laps.removeFirst() }
                if let p = v["PlayerCarPosition"], p > 0 { posHist.append((lc, Int(p))); if posHist.count > 200 { posHist.removeFirst() } }
            } else if let c = cur, lc < c.n { clear() } // a new session
            if lastSeen < 0 { lastSeen = last }
            cur = RecLap(n: lc); ver += 1
            return
        }
        if (v["OnPitRoad"] ?? 0) != 0 { c.pit = true }
        if d < 0 || (d < 60 && t > 8) { return }
        let b = Int(d / 5)
        if b > 4000 { return }
        let sp = v["Speed"] ?? 0, th = v["Throttle"] ?? 0, br = v["Brake"] ?? 0, g = Int(v["Gear"] ?? 0)
        while c.size <= b {
            let e = c.size == 0
            c.t.append(e ? t : c.t.last!); c.sp.append(e ? sp : c.sp.last!); c.thr.append(e ? th : c.thr.last!)
            c.brk.append(e ? br : c.brk.last!); c.gear.append(e ? g : c.gear.last!)
        }
        c.t[b] = t; c.sp[b] = sp; c.thr[b] = th; c.brk[b] = br; c.gear[b] = g
        ver += 1
    }

    /// your best lap seen here (never one through the pits) and the last one finished
    func best() -> RecLap? { laps.filter { !$0.pit && $0.time > 0 }.min { $0.time < $1.time } }
    func last() -> RecLap? { laps.last { $0.time > 0 } }
}
