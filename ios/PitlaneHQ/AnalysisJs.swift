import Foundation
import JavaScriptCore

/// One step of the coach's plan as the web writes it: what to work on (t), what it is worth (gain, s), why and how, and the
/// turns it is about (what "Take the plan to the coach overlay" sends, like the web's planTurns).
struct PlanItem: Hashable {
    let k: String
    let gain: Double
    let t: String
    let why: String
    let how: String
    var turns: [Int] = []
}

/// What the web's lap analysis and coach (pitwall-analysis.js, run by AnalysisJs) say about lap A against lap B: the
/// analyzer's corners, the coach's corners (the same, a corner taken differently every lap hearing about consistency), the
/// coach's plan and both laps' sectors (A, B). The screens show these instead of Models.swift's.
struct JsResult {
    let corners: [Corner]
    let coach: [Corner]
    let plan: [PlanItem]
    let secs: [(Double, Double)]
}

/// What the coach learnt that the analysis weighs by: everyone's (/community/coach/weights) and the driver's own (/community/coach/me).
struct CoachWeights {
    var w: [String: Double] = [:]
    var ask: [String: Double] = [:]
    var off: Set<String> = []
    var me: [String: Double] = [:]
    var habits: [Habit] = []
}

/// A lap's path as the web's analysis takes it (xy): x east and y north in metres, g its origin [lat, lon] when it comes from
/// the game's position. Its length may differ from the lap's points (the model's fastest line, lineXY).
struct LapPath {
    let x: [Double]
    let y: [Double]
    let g: [Double]?
}

enum JsAnalysis {
    /// The shape of the module's answer this app reads; another one (a newer pitwall-analysis.js) is not run and Models.swift is used.
    static let version = 1

    private static func num(_ v: Double) -> Any { v.isFinite ? v : NSNull() }

    /// The module counts a point every 5 m: a trace of other points (the demo data's 10 m) goes to Models.swift instead.
    static func runs(_ tr: Trace) -> Bool { abs(tr.bin - 5) < 1e-6 }

    /// A trace's own path, when it has one.
    static func pathOf(_ tr: Trace) -> LapPath? {
        guard let x = tr.x, let y = tr.y else { return nil }
        return LapPath(x: x, y: y, g: tr.g?.count == 2 ? tr.g : nil)
    }

    /// A lap in the web's shape: one point every 5 m, [speed m/s, lap time s, throttle, brake, gear, steering], and its path
    /// (the trace's own unless another is given: a model reference takes the web's, lineXY with its origin).
    static func lap(_ tr: Trace, time: Double, sectors: [Double]) -> [String: Any] { lap(tr, time: time, sectors: sectors, path: pathOf(tr)) }

    static func lap(_ tr: Trace, time: Double, sectors: [Double], path: LapPath?) -> [String: Any] {
        func at(_ r: [Double], _ k: Int) -> Any { num(k < r.count ? r[k] : 0) }
        let bins: [[Any]] = tr.rows.map { r in [at(r, 0), at(r, 5), at(r, 1), at(r, 2), at(r, 3), at(r, 4), NSNull()] }
        var o: [String: Any] = ["bins": bins, "maxBin": tr.rows.count - 1, "time": time]
        if !sectors.isEmpty { o["sectors"] = sectors.map { num($0) } }
        if let x = path?.x, let y = path?.y, x.count == y.count, x.count > 10 {
            var p: [String: Any] = ["x": x.map { num($0) }, "y": y.map { num($0) }, "g": NSNull()]
            if let g = path?.g, g.count == 2 { p["g"] = g }
            o["xy"] = p
        }
        return o
    }

    /// One lap of the session for the coach's plan (ctx.laps, how steady each corner is): only what it reads, the speed
    /// and the lap time at every point, and whether the lap is valid.
    static func sessionLap(_ tr: Trace, valid: Bool) -> [String: Any] {
        func at(_ r: [Double], _ k: Int) -> Any { num(k < r.count ? r[k] : 0) }
        return ["bins": tr.rows.map { r in [at(r, 0), at(r, 5)] }, "maxBin": tr.rows.count - 1, "valid": valid]
    }

    /// The context the analysis reads: the language, the official turns, what the coach learnt and the model's corner cards.
    static func ctx(lang: String, turns: [Double], w: CoachWeights, cards: [CornerCard]) -> [String: Any] {
        [
            "lang": lang, "units": "metric",
            "turns": turns.isEmpty ? NSNull() as Any : turns as Any,
            "weights": ["w": w.w, "b": w.ask.mapValues { ["ask": $0] }, "off": Array(w.off)] as [String: Any],
            "me": ["w": w.me, "habits": w.habits.map { ["kind": $0.kind, "tracks": $0.tracks, "sessions": $0.sessions] as [String: Any] }] as [String: Any],
            "cards": cards.map { ["apex": $0.apex, "spread": $0.spread] },
        ]
    }

    /// The call the engine evaluates, after the file itself: the analysis with the session's laps in ctx.laps, in English,
    /// Spanish and Portuguese (so a change of language in Settings needs no new run), as one JSON string.
    static func call(_ a: String, _ b: String, _ ctx: String, _ laps: String) -> String {
        "(function(A,B,c,L){var o={};c.laps=L;['en','es','pt'].forEach(function(l){c.lang=l;o[l]=PW_ANALYSIS.analyse(A,B,c)});return JSON.stringify(o)})(\(a),\(b),\(ctx),\(laps))"
    }

    private static func dbl(_ v: Any?) -> Double { (v as? NSNumber)?.doubleValue ?? 0 }

    private static func corner(_ o: [String: Any]) -> Corner {
        let ph = o["ph"] as? [String: Any] ?? [:]
        let text = o["text"] as? String ?? ""
        let kind = o["kind"] as? String ?? ""
        var k = Corner(n: (o["n"] as? NSNumber)?.intValue ?? 0, atM: Int(dbl(o["d"]).rounded()), lost: dbl(o["lost"]),
                       phases: Dictionary(uniqueKeysWithValues: phaseKeys.map { ($0, dbl(ph[$0])) }), phase: o["phase"] as? String,
                       coastA: dbl(o["coastA"]), coastB: dbl(o["coastB"]), tip: !text.isEmpty && !kind.isEmpty ? "tip_" + kind : nil, args: [])
        k.apexM = Int(dbl(o["apex"]).rounded())
        k.cls = o["cls"] as? String ?? ""
        // the braking points table: where A brakes against B (m, + A later), the slowest point of each (km/h, the context's
        // units are metric), the gear there, a corner B takes without braking, and what to do in a few words
        k.dd = (o["dd"] as? NSNumber).map { Int($0.doubleValue.rounded()) }
        k.vA = (o["vmin"] as? NSNumber)?.doubleValue
        k.vB = dbl(o["vminr"])
        k.gearA = (o["gA"] as? NSNumber)?.intValue ?? 0
        k.gearB = (o["gB"] as? NSNumber)?.intValue ?? 0
        k.lift = o["lift"] as? Bool ?? false
        k.text = text.isEmpty ? nil : text
        let todo = o["todo"] as? String ?? ""
        k.todo = todo.isEmpty ? nil : todo
        return k
    }

    private static func one(_ j: [String: Any]) -> JsResult? {
        guard (j["v"] as? NSNumber)?.intValue == version, let coach = j["coach"] as? [String: Any] else { return nil }
        func list(_ v: Any?) -> [[String: Any]] { v as? [[String: Any]] ?? [] }
        return JsResult(
            corners: list(j["corners"]).map(corner), coach: list(coach["cs"]).map(corner),
            plan: list(coach["plan"]).map { PlanItem(k: $0["k"] as? String ?? "", gain: dbl($0["gain"]), t: $0["t"] as? String ?? "", why: $0["why"] as? String ?? "", how: $0["how"] as? String ?? "",
                                                     turns: ($0["turns"] as? [NSNumber] ?? []).map { $0.intValue }.filter { $0 > 0 }) },
            secs: list(coach["secs"]).map { (dbl($0["a"]), dbl($0["b"])) })
    }

    /// The analysis' answer as the screens' own structures, by language; nil when it is not one, or not the shape this app
    /// was built for (its v).
    static func parse(_ s: String) -> [String: JsResult]? {
        guard let d = s.data(using: .utf8), let root = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        var out: [String: JsResult] = [:]
        for l in ["en", "es", "pt"] { guard let o = root[l] as? [String: Any], let r = one(o) else { return nil }; out[l] = r }
        return out
    }
}

/// The web's lap analysis and coach on the phone: web/dist/pitwall-analysis.js, the file the PC app and pitlanehq.app run,
/// evaluated in JavaScriptCore, so the corners, tips, plan and sectors are the PC's. The newest copy comes from pitlanehq.app
/// (at most every six hours, its ETag says when nothing changed) and is kept on disk; the copy in the app (Resources,
/// refreshed from the Pitwall-test repository with tools/sync-analysis.sh) is used until a download succeeds. Nil from
/// `analyse` when it cannot run: the screens then fall back to Models.swift.
final class AnalysisJs {
    static let shared = AnalysisJs()
    static let name = "pitwall-analysis.js"
    static let url = URL(string: "https://pitlanehq.app/pitwall-analysis.js")!
    private static let every: TimeInterval = 6 * 3600
    private let queue = DispatchQueue(label: "com.pitlanehq.analysis")
    private var context: JSContext?
    private var loaded = ""        // the copy the context has evaluated (its length and hash)
    private var failures = 0       // the engine failing again and again: the fallback for the rest of the run
    private var threw = false
    private let defaults = UserDefaults.standard
    private var file: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent(AnalysisJs.name)
    }

    // a copy that is the module and gives the shape this app reads (its VERSION); a newer shape is never kept nor run
    private func valid(_ s: String) -> Bool {
        s.count > 2000 && s.contains("PW_ANALYSIS") && s.range(of: "\\bVERSION\\s*=\\s*\(JsAnalysis.version)\\b", options: .regularExpression) != nil
    }

    /// The file to run: the downloaded copy when there is a good one, else the app's own.
    private func source() -> String? {
        if let s = try? String(contentsOf: file, encoding: .utf8), valid(s) { return s }
        guard let u = Bundle.main.url(forResource: "pitwall-analysis", withExtension: "js") else { return nil }
        return try? String(contentsOf: u, encoding: .utf8)
    }

    /// Downloads the newest copy from pitlanehq.app, at most every six hours; nothing changes when it fails.
    func refresh() async {
        let now = Date().timeIntervalSince1970
        let have = FileManager.default.fileExists(atPath: file.path)
        if now - defaults.double(forKey: "analysis.at") < AnalysisJs.every && have { return }
        defaults.set(now, forKey: "analysis.at")
        var r = URLRequest(url: AnalysisJs.url)
        r.timeoutInterval = 20
        if have, let e = defaults.string(forKey: "analysis.etag") { r.setValue(e, forHTTPHeaderField: "If-None-Match") }
        guard let pair = try? await URLSession.shared.data(for: r), let h = pair.1 as? HTTPURLResponse, h.statusCode == 200,
              let s = String(data: pair.0, encoding: .utf8), valid(s) else { return }
        let data = pair.0
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: file, options: .atomic)) != nil { defaults.set(h.value(forHTTPHeaderField: "ETag"), forKey: "analysis.etag") }
    }

    /// Evaluates `code` after the file (once per context); its result as a string, or nil when the engine cannot. On the queue.
    private func run(_ code: String) -> String? {
        if failures >= 3 { return nil }
        guard let src = source() else { return nil }
        let key = "\(src.count):\(src.hashValue)"
        if context == nil || loaded != key {
            let made: JSContext? = JSContext()
            guard let c = made else { failures += 1; return nil }
            c.exceptionHandler = { [weak self] _, _ in self?.threw = true }
            threw = false
            c.evaluateScript(src)
            let pw: JSValue? = c.objectForKeyedSubscript("PW_ANALYSIS")
            if threw || (pw?.isUndefined ?? true) { failures += 1; context = nil; loaded = ""; return nil }
            context = c
            loaded = key
        }
        threw = false
        let v: JSValue? = context?.evaluateScript(code)
        let s: String? = v != nil && !threw && v!.isString ? v!.toString() : nil
        guard let s else { failures += 1; context = nil; loaded = ""; return nil }
        failures = 0
        return s
    }

    /// Lap A against lap B as the web analyses them, with the session's `laps` (JsAnalysis.sessionLap) for the coach's plan,
    /// by language, or nil (the screens then use Models.swift).
    func analyse(a: [String: Any], b: [String: Any], ctx: [String: Any], laps: [[String: Any]] = []) async -> [String: JsResult]? {
        // the newest copy is fetched beside it, never in the way: this run uses the one on disk, the next one the new
        Task.detached(priority: .background) { await self.refresh() }
        func json(_ o: [String: Any]) -> String? { (try? JSONSerialization.data(withJSONObject: o)).flatMap { String(data: $0, encoding: .utf8) } }
        guard let ja = json(a), let jb = json(b), let jc = json(ctx),
              let jl = (try? JSONSerialization.data(withJSONObject: laps)).flatMap({ String(data: $0, encoding: .utf8) }) else { return nil }
        let code = JsAnalysis.call(ja, jb, jc, jl)
        let s: String? = await withCheckedContinuation { k in queue.async { k.resume(returning: self.run(code)) } }
        return s.flatMap { JsAnalysis.parse($0) }
    }
}
