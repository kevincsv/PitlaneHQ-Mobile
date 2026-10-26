import Foundation

/// Invented data to test the app (Settings → Demo data). It only lives on this phone: nothing is
/// uploaded, and every screen shows a DEMO banner while it is on. The same as Android's Demo.kt.
enum Demo {
    private struct C0 {
        let track: String, cfg: String, trackId: Int64, car: String, carId: Int64, len: Double, lap: Double
    }

    private static let combos0 = [
        C0(track: "Spa-Francorchamps", cfg: "Grand Prix Pits", trackId: 163, car: "Porsche 911 GT3 R (992)", carId: 169, len: 7004, lap: 137.8),
        C0(track: "Watkins Glen International", cfg: "Boot", trackId: 434, car: "Mazda MX-5 Cup", carId: 67, len: 5435, lap: 126.4),
        C0(track: "Okayama International Circuit", cfg: "Full Course", trackId: 166, car: "Toyota GR86", carId: 160, len: 3703, lap: 92.1),
        C0(track: "Road Atlanta", cfg: "Full Course", trackId: 127, car: "BMW M4 GT3", carId: 132, len: 4088, lap: 85.6),
        C0(track: "Laguna Seca", cfg: "Full Course", trackId: 47, car: "Mazda MX-5 Cup", carId: 67, len: 3602, lap: 95.3),
    ]
    private static let names = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J"].map { "Demo Driver " + $0 }
    private static let dayMs = 86_400_000.0
    private static let now = Date().timeIntervalSince1970 * 1000

    /// A repeatable random sequence, so the demo looks the same every time.
    struct Seeded: RandomNumberGenerator {
        var state: UInt64
        init(_ seed: Int) { state = UInt64(bitPattern: Int64(seed)) &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static func stableHash(_ s: String) -> Int {
        var h = 7
        for u in s.unicodeScalars { h = (h &* 31 &+ Int(u.value)) & 0x7FFF_FFFF }
        return h
    }

    private static func trace(_ c: C0, _ lapTime: Double, _ seed: Int) -> Trace {
        var r = Seeded(seed)
        let bin = 10.0
        let n = Int(c.len / bin)
        // the corners of a track are always in the same place: every lap of a combination shares them
        var rc = Seeded(stableHash(c.track))
        var corners: [Double] = []
        for k in 0..<9 { corners.append((Double(k) + 0.5 + Double.random(in: -0.2...0.2, using: &rc)) / 9) }
        var raw: [Double] = []
        for i in 0..<n {
            let x: Double = Double(i) / Double(n)
            var v: Double = 72
            for k in corners {
                let d: Double = x - k
                v -= 38 * exp(-(d * d) / 0.0009)
            }
            let wave: Double = sin(x * 2 * Double.pi * 3) * 3
            raw.append(max(18, v + wave + Double.random(in: -0.6...0.6, using: &r)))
        }
        var sumT: Double = 0
        for v in raw { sumT += bin / v }
        let f: Double = sumT / lapTime
        var t: Double = 0
        var rows: [[Double]] = []
        for i in 0..<n {
            let v: Double = raw[i] * f
            t += bin / v
            let next: Double = raw[min(n - 1, i + 3)] * f
            let braking = next < v - 1.5
            let thr: Double = braking ? 0 : min(1, 0.55 + v / 80)
            let brk: Double = braking ? min(1, (v - next) / 8) : 0
            let gear = Double(min(6, Int(1 + v / 14)))
            let steer: Double = cos(Double(i) * 0.05) * 0.1
            rows.append([v, thr, brk, gear, steer, t])
        }
        // the shape of the track, like the position Pitlane HQ records: a loop that turns at every corner
        var turns: [Double] = []
        for k in 0..<corners.count { turns.append((k % 3 == 2 ? -0.6 : 1.0) * Double.random(in: 0.6...1.3, using: &rc)) }
        let tot: Double = turns.reduce(0, +)
        var xs: [Double] = [], ys: [Double] = []
        var h: Double = 0, px: Double = 0, py: Double = 0
        for i in 0..<n {
            let q: Double = Double(i) / Double(n)
            var dh: Double = 0
            for (j, k) in corners.enumerated() {
                let dd: Double = q - k
                dh += turns[j] * 2 * Double.pi / tot * exp(-(dd * dd) / 0.0006) / ((Double.pi * 0.0006).squareRoot() * Double(n))
            }
            h += dh; px += bin * cos(h); py += bin * sin(h); xs.append(px); ys.append(py)
        }
        let ex: Double = xs[n - 1] - xs[0], ey: Double = ys[n - 1] - ys[0]
        for i in 0..<n { let f: Double = Double(i) / Double(n - 1); xs[i] -= ex * f; ys[i] -= ey * f }
        return Trace(bin: bin, rows: rows, x: xs, y: ys)
    }

    private static func sectors(_ lap: Double, _ r: inout Seeded) -> [Double] {
        var a: [Double] = []
        for share in [0.31, 0.37, 0.32] { a.append(share * lap + Double.random(in: -0.15...0.15, using: &r)) }
        let s: Double = a.reduce(0, +)
        return a.map { $0 * lap / s }
    }

    static func sessions() -> [CloudSession] {
        var out: [CloudSession] = []
        for (i, c) in combos0.enumerated() {
            let practice: Double = now - Double(i * 2 + 1) * dayMs
            let race: Double = now - Double(i * 2) * dayMs - 3_600_000
            let pBest: Double = c.lap + 0.4 + Double(i) * 0.05
            out.append(CloudSession(id: "demo:\(i):p", started: practice, track: c.track, trackConfig: c.cfg, car: c.car, kind: "Practice", laps: 9, best: pBest))
            out.append(CloudSession(id: "demo:\(i):r", started: race, track: c.track, trackConfig: c.cfg, car: c.car, kind: "Race", laps: 14, best: c.lap + 0.2))
        }
        return out.sorted { $0.started > $1.started }
    }

    private static func combo(of id: String) -> C0 { combos0[Int(id.split(separator: ":")[1]) ?? 0] }

    static func laps(_ sessionId: String) -> [CloudLap] {
        var r = Seeded(stableHash(sessionId))
        guard let s = sessions().first(where: { $0.id == sessionId }), let best = s.best else { return [] }
        var out: [CloudLap] = []
        for n in 1...s.laps {
            let extra: Double = Double.random(in: 0.1...1.6, using: &r) + (n == 1 ? 4.0 : 0.0)
            let time: Double = n == 3 ? best : best + extra
            out.append(CloudLap(id: "\(sessionId):\(n)", n: n, time: time, valid: n != 6, sectors: sectors(time, &r)))
        }
        return out
    }

    static func trace(_ lapId: String) -> Trace? {
        if lapId.hasPrefix("comm:") {
            let p = lapId.split(separator: ":")
            let c = combos0[Int(p[1]) ?? 0]
            guard let lap = board(trackId: c.trackId, carId: c.carId).first(where: { $0.id == lapId }) else { return nil }
            return trace(c, lap.time, stableHash(lapId))
        }
        let sessionId = String(lapId[..<(lapId.lastIndex(of: ":") ?? lapId.endIndex)])
        guard let lap = laps(sessionId).first(where: { $0.id == lapId }) else { return nil }
        return trace(combo(of: lapId), lap.time, stableHash(lapId))
    }

    static func bests() -> [PersonalBest] {
        var out: [PersonalBest] = []
        for (i, c) in combos0.enumerated() {
            let last: Double = now - Double(i * 2) * dayMs
            out.append(PersonalBest(track: c.track, trackConfig: c.cfg, car: c.car, best: c.lap + 0.2, laps: 23, last: last, bestLapId: "demo:\(i):r:3", bestSessionId: "demo:\(i):r"))
        }
        return out
    }

    static func combos() -> [Combo] {
        var out: [Combo] = []
        for c in combos0 {
            out.append(Combo(trackId: c.trackId, track: c.track, carId: c.carId, car: c.car, laps: 40 + Int(c.carId) % 30, best: c.lap - 0.7, cat: "sports_car"))
        }
        return out
    }

    static func board(trackId: Int64, carId: Int64) -> [CommunityLap] {
        guard let i = combos0.firstIndex(where: { $0.trackId == trackId && $0.carId == carId }) else { return [] }
        let c = combos0[i]
        var r = Seeded(i * 31 + 7)
        var out: [CommunityLap] = []
        for (k, n) in names.enumerated() {
            let step: Double = Double.random(in: 0.08...0.35, using: &r)
            let time: Double = c.lap - 0.7 + Double(k) * step
            let created: Double = now - Double(k) * dayMs
            out.append(CommunityLap(id: "comm:\(i):\(k)", alias: n, time: time, created: created, hasTrace: true, sectors: sectors(time, &r), lic: demoLics[k % demoLics.count], prof: true, sup: k % 3 == 0))
        }
        return out.sorted { $0.time < $1.time }
    }

    private static let demoLics = ["A", "B", "C", "B", "D", "R", "A", "C", "B", "P"]

    static func profile(_ lapId: String?) -> DriverProfile {
        let k = Int(lapId?.split(separator: ":").last ?? "0") ?? 0
        let lic = demoLics[k % demoLics.count]
        let rs = races().prefix(6).map { r in ProfileRace(when: r.when, track: r.track, car: r.car, cat: "sports_car", lic: lic, official: r.official, start: r.start, finish: r.finish, field: r.field, inc: r.inc, best: r.best, irChange: r.irChange, dnf: r.dnf) }
        let ls = combos0.map { c in ProfileLap(track: c.track, car: c.car, time: c.lap - 0.3, created: now - 3 * dayMs, cat: "sports_car", lic: lic, anon: false) }
        return DriverProfile(name: lapId == nil ? "Demo Driver" : names[k % names.count], since: now - 200 * dayMs, mine: lapId == nil, admin: false, anonymous: false, supporter: k % 3 == 0, supporterHidden: false,
                             lics: ["sports_car": lic, "oval": "D"], races: Array(rs), laps: ls)
    }

    static func reports() -> [SharedReport] {
        var out: [SharedReport] = []
        for (i, c) in combos0.enumerated() {
            for k in 0..<2 {
                let created: Double = now - Double(i + k) * dayMs
                let best: Double = c.lap + 0.3 + Double(k) * 0.2
                out.append(SharedReport(id: "rep\(i)\(k)", alias: names[(i + k) % names.count], track: c.track, car: c.car, created: created, finish: 3 + k * 4, field: 18 + i, best: best))
            }
        }
        return out
    }

    static func setups() -> [SharedSetup] {
        var out: [SharedSetup] = []
        for (i, c) in combos0.enumerated() {
            let first: String = c.track.split(separator: " ").first.map(String.init) ?? c.track
            let created: Double = now - Double(i * 3) * dayMs
            out.append(SharedSetup(id: "set\(i)", alias: names[i], name: first + " race", car: c.car, track: c.track,
                                   notes: "Stable on entry, a click less rear wing for the long straight.", downloads: 12 + i * 9, created: created))
        }
        return out
    }

    static func races() -> [Race] {
        var ir = 2150
        var out: [Race] = []
        for k in 0..<8 {
            let c = combos0[k % combos0.count]
            var r = Seeded(k * 101)
            let field: Int = 16 + Int.random(in: 0..<8, using: &r)
            let start: Int = 1 + Int.random(in: 0..<field, using: &r)
            let finish: Int = max(1, min(field, start + Int.random(in: -5..<5, using: &r)))
            let base: Double = Double(field / 2 - finish) * 6.5
            let change: Int = Int(base) + Int.random(in: -8..<8, using: &r)
            let inc: Int = Int.random(in: 0..<9, using: &r)
            let best: Double = c.lap + 0.3 + Double.random(in: 0..<0.8, using: &r)
            var laps: [RaceLap] = []
            for n in 1...15 {
                let extra: Double = Double.random(in: 0..<1.5, using: &r) + (n == 1 ? 5.0 : 0.0)
                let p: Int = max(1, start + (finish - start) * n / 15)
                laps.append(RaceLap(n: n, time: best + extra, pos: p, inc: n == 4 ? min(inc, 4) : 0, pit: n == 9))
            }
            var results: [RaceResult] = []
            for p in 1...field {
                if p == finish {
                    results.append(RaceResult(pos: p, name: "You", ir: ir, best: best, inc: inc, laps: 15))
                } else {
                    let rIr: Int = 1500 + Int.random(in: 0..<1600, using: &r)
                    let rBest: Double = best + Double.random(in: -0.8..<1.2, using: &r)
                    let rInc: Int = Int.random(in: 0..<10, using: &r)
                    results.append(RaceResult(pos: p, name: names[(p + k) % names.count], ir: rIr, best: rBest, inc: rInc, laps: 15))
                }
            }
            let when: Double = now - Double(k) * dayMs - 7_200_000
            let sof: Int = 1800 + Int.random(in: 0..<900, using: &r)
            out.append(Race(id: "demo-race-\(k)", when: when, track: c.track, car: c.car, official: true, start: start, finish: finish, field: field,
                            inc: inc, best: best, fieldBest: best - 0.4, avg: best + 0.7, consistency: 0.42, pits: 1, fuelUsed: 38.5, ir: ir, irChange: change,
                            sof: sof, dnf: false, laps: laps, results: results))
            ir -= change
        }
        return out
    }

    private static let liveTrace = trace(combos0[0], combos0[0].lap, 1)

    /// A lap around the track, for the live screen.
    static func live(_ tick: Int) -> [String: Double] {
        let c = combos0[0]
        let row = liveTrace.rows[tick % liveTrace.rows.count]
        var m: [String: Double] = [:]
        m["Speed"] = row[0]
        m["RPM"] = 4000 + row[0] * 80
        m["Gear"] = row[3]
        m["FuelLevel"] = 62 - Double(tick) * 0.002
        m["Lap"] = Double(4 + tick / liveTrace.rows.count)
        // the lap's time, distance and number, so Full and Compare laps have laps to draw (each a little different)
        let lapN = tick / liveTrace.rows.count
        m["LapCurrentLapTime"] = row[5] * (1 + 0.004 * sin(Double(lapN) * 1.7))
        m["LapDist"] = Double(tick % liveTrace.rows.count) * 10
        m["LapCompleted"] = Double(3 + lapN)
        m["LapLastLapTime"] = c.lap + 0.31
        m["LapBestLapTime"] = c.lap + 0.12
        m["LapDeltaToBestLap"] = sin(Double(tick) / 40) * 0.4
        m["Throttle"] = row[1]
        m["Brake"] = row[2]
        m["PlayerCarPosition"] = Double(6 - lapN % 3)
        return m
    }
}
