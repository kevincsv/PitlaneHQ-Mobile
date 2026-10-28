import SwiftUI

/// Lap B: the driver's own best lap of the session, or the model's next level (the driver just ahead) or record.
enum RefKind: Hashable { case myBest, level, record }

/// A lap and the lap it is compared with, for the lap analysis and the coach.
struct LapAnalysis {
    let lap: CloudLap
    var trace: Trace?
    var ref: Trace?
    var refLabel = ""
    var refTime: Double?
    var refSectors: [Double] = []
    var car: [String: Any]?
    var turns: [Double] = []      // the official turn numbers of this track, when an admin placed them
    var fastest = false           // nobody known is faster here: lap B is your own best
    var layout: ([Double], [Double])?  // the track's layout drawn by the community: the map's road when the lap has no path
    // the session, its car and track as the community knows them, and the model's corner card (where the fastest drivers
    // here brake and how fast they take each corner): the thumbs on a tip and the hint beside it
    var session: CloudSession?
    var trackId: Int64 = 0
    var carId: Int64 = 0
    var corners: [CornerCard] = []
    // what the coach learnt from everyone (the tips turned off, how many drivers each helped) and this driver's habits
    var coach: CoachInfo?
    var habits: [Habit] = []
    // the web's analysis of these two laps (pitwall-analysis.js) in each language: its corners, tips, plan and sectors are
    // what the screens show; nil when it cannot run, and the screens use Models.swift
    var js: [String: JsResult]? = nil
    /// the web's analysis in the app's language
    var jsNow: JsResult? { js?[I18n.shared.lang] }
}

/// What a lap was driven in, from its trace's flags, like the web's lap list ("traffic · wet track"); nil when nothing to say.
func lapFlags(_ tr: Trace?) -> String? {
    let s: [String] = (tr?.f ?? []).compactMap { f in
        switch f { case "traffic": return t("lap_traffic"); case "cold": return t("lap_cold"); case "wet": return t("lap_wet"); case "damp": return t("lap_damp"); case "rain": return t("lap_rain"); default: return nil }
    }
    return s.isEmpty ? nil : s.joined(separator: " · ")
}

func fillArgs(_ s0: String, _ args: [String]) -> String {
    var s = s0
    for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a) }
    return s
}

extension Account {
    private func ownRef(_ b: CloudLap?) async -> (Trace?, String, Double?, [Double]) {
        guard let b else { return (nil, "", nil, []) }
        let tr: Trace? = try? await lapTrace(b.id)
        return (tr, "L\(b.n)", b.time, b.sectors)
    }

    /// Opens a lap and its lap B, like the PC and the web: the driver's own best lap of the session (DRINKS mode: a
    /// friend's lap against that friend's best), or the model's next level or record; when nobody known is faster,
    /// your own best lap. The coach (withLaps) also hands the web's analysis the session's laps, like the web's: how steady
    /// each corner is gives the plan its consistency steps.
    func analyse(session: CloudSession, lap: CloudLap, all: [CloudLap], kind: RefKind, withLaps: Bool = false) async throws -> LapAnalysis {
        var a = LapAnalysis(lap: lap)
        a.session = session
        a.trace = try await lapTrace(lap.id)
        // the car and track of this session among the ones the community knows, matched by name
        let gm = session.game
        let combos = (try? await self.combos(game: gm).data) ?? []
        let c = combos.first { $0.track.caseInsensitiveCompare(session.track) == .orderedSame && $0.car.caseInsensitiveCompare(session.car) == .orderedSame }
            ?? combos.first { session.track.lowercased().hasPrefix($0.track.lowercased()) && $0.car.caseInsensitiveCompare(session.car) == .orderedSame }
        // the car card needs the car alone: what it does on other tracks, for when nobody known drove it here yet
        if let cc = c ?? combos.first(where: { $0.car.caseInsensitiveCompare(session.car) == .orderedSame }) { a.car = try? await carCard(carId: cc.carId, game: gm) }
        if let tc = c { a.turns = await turns(trackId: tc.trackId, game: gm); a.trackId = tc.trackId; a.carId = tc.carId }
        a.coach = await coachInfo()
        a.habits = await coachHabits()
        // a lap with no path of its own (an older one, a rival's) still gets its map: the track's layout drawn by the community
        if let tc = c, !(a.trace?.hasShape ?? false) { a.layout = await trackLayout(trackId: tc.trackId, game: gm) }
        let own = all.filter { $0.valid && $0.time > 0 && $0.id != lap.id && $0.drv == lap.drv }.min { $0.time < $1.time }
        // lap B's path as the web's analysis takes it: a model reference's own (the web's, lineXY and its origin when it has
        // none), else the trace's
        var modelPath = false
        var refPath: LapPath? = nil
        if kind == .myBest {
            (a.ref, a.refLabel, a.refTime, a.refSectors) = await ownRef(own)
            // the corner card also when lap B is your own lap: the model knows the corners whoever the reference is
            if let c { a.corners = await modelRefs(trackId: c.trackId, carId: c.carId, lapTime: lap.time, game: gm, cmp: a.trace?.cmp ?? 0).corners }
        } else {
            var rec: (Trace, Double)? = nil
            var lvl: (Trace, Double)? = nil
            var recXY: LapPath? = nil
            var lvlXY: LapPath? = nil
            if let c {
                let m = await modelRefs(trackId: c.trackId, carId: c.carId, lapTime: lap.time, game: gm, cmp: a.trace?.cmp ?? 0)
                rec = m.rec
                lvl = m.lvl
                recXY = m.recXY
                lvlXY = m.lvlXY
                a.corners = m.corners
            }
            let pick = kind == .level ? (lvl ?? rec) : rec
            if let p = pick, p.1 < lap.time - 0.001 {
                a.ref = p.0
                a.refTime = p.1
                a.refLabel = kind == .level && lvl != nil ? "▲ " + t("next_level") : "★ " + t("record")
                modelPath = true
                refPath = kind == .level && lvl != nil ? lvlXY : recXY
            } else {
                // nobody known is faster here (this lap is the record) or nobody known at all: like the web's coach,
                // your own best lap of the session is lap B
                a.fastest = pick != nil
                (a.ref, a.refLabel, a.refTime, a.refSectors) = await ownRef(own)
            }
        }
        // a rival's lap has no path (it comes from its place on track): the line is then measured against the driver's
        // own best lap of the session, the fastest line known here
        if var r = a.ref, r.x == nil || r.y == nil, let b = own, let bt = try? await lapTrace(b.id), let bx = bt.x, let by = bt.y,
           !bx.isEmpty, abs(bx.count - r.rows.count) <= 6 {
            r.x = (0..<r.rows.count).map { bx[min($0, bx.count - 1)] }
            r.y = (0..<r.rows.count).map { by[min($0, by.count - 1)] }
            r.g = bt.g
            a.ref = r
        }
        // the web's own analysis of the two laps, the same corners, tips, plan and sectors as the PC's (the module counts a
        // point every 5 m: other traces, the demo data's, go to Models.swift)
        if let tr = a.trace, let rb = a.ref, let tb = a.refTime, JsAnalysis.runs(tr), JsAnalysis.runs(rb) {
            let me = await coachMeWeights()
            let w = CoachWeights(w: a.coach?.w ?? [:], ask: a.coach?.ask ?? [:], off: a.coach?.off ?? [], me: me, habits: a.habits)
            var laps: [[String: Any]] = []
            if withLaps { laps = await sessionTraces(session.id).filter { $0.0 && JsAnalysis.runs($0.1) }.map { JsAnalysis.sessionLap($0.1, valid: $0.0) } }
            a.js = await AnalysisJs.shared.analyse(a: JsAnalysis.lap(tr, time: lap.time, sectors: lap.sectors),
                                                   b: JsAnalysis.lap(rb, time: tb, sectors: a.refSectors, path: modelPath ? refPath : JsAnalysis.pathOf(rb)),
                                                   ctx: JsAnalysis.ctx(lang: "en", turns: a.turns, w: w, cards: a.corners), laps: laps)
        }
        return a
    }
}

/// Lap A's sectors against lap B's.
struct SectorTable: View {
    let a: [Double]
    let b: [Double]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: t("sectors"))
            Panel {
                ForEach(Array(a.enumerated()), id: \.offset) { i, s in
                    let r: Double? = i < b.count ? b[i] : nil
                    HStack {
                        Text("S\(i + 1)").foregroundColor(Theme.muted).frame(width: 40, alignment: .leading)
                        Text(String(format: "%.3f", s)).foregroundColor(Theme.accent)
                        Spacer()
                        Text(r.map { String(format: "%.3f", $0) } ?? "—").foregroundColor(Theme.blue)
                        Spacer()
                        Text(r.map { String(format: "%+.3f", s - $0) } ?? "").foregroundColor(r != nil && s <= r! ? Theme.good : Theme.bad)
                    }
                    .font(.system(size: 13, design: .monospaced))
                }
            }
        }
    }
}

/// A corner that costs time: its official turn, where, the phase that loses the most, the tip and what the line says.
/// With the analysis: 👍/👎 on the tip (the coach learns from them, coachtips.js) and the corner card (where the fastest
/// drivers here brake and how fast they take the corner, a range of real laps).
struct CornerTipView: View {
    let k: Corner
    var an: LapAnalysis? = nil
    @EnvironmentObject var account: Account
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(t("corner_n", k.n)).font(.subheadline.weight(.black)).foregroundColor(Theme.accent)
                Text(t("at_m", k.atM) + (k.phase.map { " · " + t("phase_" + $0) } ?? "")).font(.caption).foregroundColor(Theme.muted)
                Spacer()
                Text(String(format: "+%.2f", k.lost)).font(.system(.subheadline, design: .monospaced).bold()).foregroundColor(Theme.bad)
            }
            if let tip = k.tip {
                HStack(alignment: .top, spacing: 6) {
                    Text(k.text ?? fillArgs(t(tip), k.args)).font(.subheadline)
                    Spacer(minLength: 0)
                    if let s = an?.session {
                        let key = s.id + ":" + String(k.apexM)
                        let mine = account.tipRatings[key] ?? 0
                        ForEach([(1, "👍"), (-1, "👎")], id: \.0) { up, g in
                            Button { rate(s, key: key, up: up, mine: mine) } label: {
                                Text(g).font(.caption).padding(.horizontal, 5).padding(.vertical, 3)
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(mine == up ? Theme.accent : Theme.line, lineWidth: 1))
                                    .opacity(mine == up ? 1 : 0.55)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            if let lt = k.lineTip { Text(fillArgs(t(lt), k.lineArgs)).font(.footnote).foregroundColor(Theme.accent) }
            // how many drivers this tip helped on corners like this, when the admin lets the tips say it
            if let ci = an?.coach, ci.confidence, let tp = k.tip, let b = ci.conf[String(tp.dropFirst(4)) + "|" + k.cls], b.1 >= ci.min {
                Text(t("tip_helped", b.0, b.1)).font(.caption2).foregroundColor(Theme.muted)
            }
            if let an, let c = CornerCard.of(an.corners, apexM: k.apexM) {
                Text(t("corner_fast", Int(c.b0), Int(c.b1), Int(c.v0 * 3.6), Int(c.v1 * 3.6), c.n)).font(.caption2).foregroundColor(Theme.muted)
            }
        }
    }
    /// a thumb on the tip (the same one again takes it back), kept on this device and sent to the account
    private func rate(_ s: CloudSession, key: String, up: Int, mine: Int) {
        guard let an else { return }
        let now = mine == up ? 0 : up
        if now == 0 { account.tipRatings.removeValue(forKey: key) } else { account.tipRatings[key] = now }
        let kind = (k.tip ?? "").hasPrefix("tip_") ? String((k.tip ?? "").dropFirst(4)) : (k.tip ?? "")
        Task { await account.rateTip(trackId: an.trackId, carId: an.carId, sid: s.id, started: s.started, n: k.n, apexM: k.apexM, kind: kind, cls: k.cls, up: now, game: s.game) }
    }
}

/// "Take the plan to the coach overlay", like the web's: the plan's corners become the coach overlay's chosen ones on your
/// PC for this track (the account's settings, which the PC takes at its next sync), and a short line says so.
private struct PlanToOverlay: View {
    @EnvironmentObject var account: Account
    let turns: [String]
    let trackId: Int64
    @State private var busy = false
    @State private var msg: String?
    var body: some View {
        Button {
            busy = true
            Task {
                do { msg = try await account.setCoachTurns(turns, trackId: trackId) ? t("plan_sent", turns.joined(separator: ", ")) : t("plan_no_pc") }
                catch { msg = (error as? AppError).map { t($0.key) } ?? error.localizedDescription }
                busy = false
            }
        } label: { Text(t("plan_to_overlay")).font(.subheadline).foregroundColor(Theme.accent) }
        .disabled(busy).padding(.top, 4)
        if let msg { Text(msg).font(.caption).foregroundColor(Theme.muted) }
    }
}

/// One step of the coach's plan: the corner, its phase, what it costs and the tip.
private struct PlanRow: View {
    let i: Int
    let k: Corner
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(i + 1).").font(.subheadline.weight(.black)).foregroundColor(Theme.accent).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(t("corner_n", k.n) + (k.phase.map { " · " + t("phase_" + $0) } ?? "")).font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "+%.2f s", k.lost)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.bad)
                }
                if let tip = k.tip { Text(k.text ?? fillArgs(t(tip), k.args)).font(.caption).foregroundColor(Theme.muted) }
            }
        }
        .padding(.top, 4)
    }
}

/// One step of the web's plan: what to work on, what it is worth, why and how.
private struct PlanItemRow: View {
    let i: Int
    let p: PlanItem
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Text("\(i + 1).").font(.subheadline.weight(.black)).foregroundColor(Theme.accent).frame(width: 22, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(p.t).font(.subheadline.bold())
                    Spacer()
                    if p.gain > 0 {
                        Text((p.k == "cons" ? "±" : "+") + String(format: "%.2f s", p.gain)).font(.system(size: 12, design: .monospaced)).foregroundColor(p.k == "cons" ? Theme.accent : Theme.bad)
                    }
                }
                if !p.why.isEmpty { Text(p.why).font(.caption).foregroundColor(Theme.muted) }
                if !p.how.isEmpty { Text("→ " + p.how).font(.caption) }
            }
        }
        .padding(.top, 4)
    }
}

/// The coach's top card: the gap to the reference, both times and what to work on first.
struct CoachGap: View {
    let an: LapAnalysis
    let refName: String
    let first: Corner?
    var body: some View {
        let d = an.refTime.map { an.lap.time - $0 }
        VStack(alignment: .leading, spacing: 8) {
            Text(t("coach_vs", refName).uppercased()).font(.system(size: 11, weight: .semibold)).tracking(1.3).foregroundColor(Theme.muted).lineLimit(2)
            HStack {
                Text(d.map { String(format: "%+.3f", $0) } ?? "—").font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundColor(d == nil ? Theme.fg : d! <= 0 ? Theme.good : Theme.bad)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(t("you") + " · L\(an.lap.n)  " + lapTime(an.lap.time)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.accent)
                    if let fl = lapFlags(an.trace) { Text(fl).font(.system(size: 10)).foregroundColor(Theme.muted) }
                    Text(lapTime(an.refTime)).font(.system(size: 12, design: .monospaced)).foregroundColor(Theme.blue)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(t("coach_first").uppercased()).font(.system(size: 10, weight: .bold)).tracking(1).foregroundColor(Theme.accent)
                if let f = first { CornerTipView(k: f, an: an) } else { Text(t("all_clean")).font(.subheadline).foregroundColor(Theme.good) }
            }
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .padding(14)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

/// A corner's four phases (braking, entry, apex, exit): what each costs against lap B.
private struct PhaseRow: View {
    let k: Corner
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(phaseKeys, id: \.self) { p in
                    let v = k.phases[p] ?? 0
                    Text(t("phase_" + p) + " " + (v > 0 ? "+" : "") + String(format: "%.2f", v))
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(v > 0.03 ? Theme.bad : Theme.muted)
                }
            }
        }
        .padding(.top, 2)
    }
}

/// The coach, like the web's: the gap to the reference with what to work on first, the plan, the map, the sectors and the
/// corners that cost the most (each with its four phases). The car card shows only when nobody known is ahead.
struct CoachBody: View {
    let an: LapAnalysis
    @State private var pick: Double?

    var body: some View {
        let refName = an.refLabel.isEmpty ? t("ref") : an.refLabel
        let d = an.refTime.map { an.lap.time - $0 }
        let cs0: [Corner] = gapCorners()
        let lose0: [Corner] = cs0.filter { $0.tip != nil && $0.lost > 0.03 }.sorted { $0.lost > $1.lost }
        VStack(alignment: .leading, spacing: 10) {
            if !cs0.isEmpty { CoachGap(an: an, refName: refName, first: lose0.first) }
            // the driver's habit first: a kind of tip that repeats on several of their tracks
            // (the web's plan already starts with it)
            if an.jsNow?.plan.contains(where: { $0.k == "habit" }) != true, let h = an.habits.first, h.tracks >= 3 { Panel { Text(t("habit_line", t("kind_" + h.kind), h.tracks, h.sessions)).font(.subheadline) } }
            if cs0.isEmpty { HStack(spacing: 8) {
                Metric(label: t("you") + " · L\(an.lap.n)", value: lapTime(an.lap.time), color: Theme.accent, sub: lapFlags(an.trace))
                Metric(label: refName, value: lapTime(an.refTime), color: Theme.blue)
                Metric(label: t("delta"), value: d.map { String(format: "%+.3f", $0) } ?? "—", color: d == nil ? Theme.fg : d! <= 0 ? Theme.good : Theme.bad)
            }
            .fixedSize(horizontal: false, vertical: true) }
            if an.fastest { Text(t("coach_fastest")).font(.caption).foregroundColor(Theme.good) }
            if let tr = an.trace { details(tr) } else { EmptyNote(text: t("no_trace")) }
        }
    }

    private func gapCorners() -> [Corner] {
        // the web's corners and tips (pitwall-analysis.js); Models.swift's only when the phone cannot run it
        if let js = an.jsNow { return js.coach }
        guard let tr = an.trace, an.ref != nil else { return [] }
        return corners(compare(tr, an.ref), turns: an.turns, off: an.coach?.off ?? [])
    }

    @ViewBuilder private func summary(_ cs: [Corner], _ lose: [Corner], _ c: Compared) -> some View {
        let lost = cs.reduce(0.0) { $0 + max(0, $1.lost) }
        let gained = cs.reduce(0.0) { $0 + min(0, $1.lost) }
        let lapLen = Double(c.speedA.count) * c.step
        Text(t("coach_sum", String(format: "%.2f", lost), cs.count, String(format: "%.2f", -gained))).font(.caption).foregroundColor(Theme.muted)
        // every corner's cost: touch one to read its tip (and see it on the map)
        SectionLabel(text: t("corners_cost"))
        CornerStrip(cs: cs, lapLen: lapLen, pick: $pick, title: false)
        let k: Corner? = picked(cs, lapLen)
        Panel { if let k { CornerTipView(k: k, an: an) } else { Text(t("corner_pick")).font(.caption).foregroundColor(Theme.muted) } }
        // the web's plan: what to work on first, what it is worth, why and how
        if let plan = an.jsNow?.plan, !plan.isEmpty {
            Panel {
                SectionLabel(text: t("coach_plan").uppercased())
                Text(t("coach_plan_note")).font(.caption2).foregroundColor(Theme.muted)
                ForEach(Array(plan.prefix(4).enumerated()), id: \.offset) { i, p in PlanItemRow(i: i, p: p) }
                // the turns of the plan's first four steps, like the web's planTurns
                let turns = plan.prefix(4).flatMap { $0.turns }.reduce(into: [Int]()) { if !$0.contains($1) { $0.append($1) } }.map { "T\($0)" }
                if !turns.isEmpty { PlanToOverlay(turns: turns, trackId: an.trackId) }
            }
        } else if !lose.isEmpty {
            Panel {
                SectionLabel(text: t("coach_plan").uppercased())
                Text(t("coach_plan_note")).font(.caption2).foregroundColor(Theme.muted)
                ForEach(Array(lose.prefix(4).enumerated()), id: \.offset) { i, k in PlanRow(i: i, k: k) }
                let turns = lose.prefix(4).map { "T\($0.n)" }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                if !turns.isEmpty { PlanToOverlay(turns: turns, trackId: an.trackId) }
            }
        }
    }

    /// the corner the finger picked on the strip or the map (its apex within about 1 % of the lap)
    private func picked(_ cs: [Corner], _ lapLen: Double) -> Corner? {
        guard let p = pick else { return nil }
        let len = max(lapLen, 1)
        var best: Corner?
        var gap = 0.012
        for c in cs {
            let g = abs(Double(c.atM) / len - p)
            if g < gap { gap = g; best = c }
        }
        return best
    }

    @ViewBuilder private func details(_ tr: Trace) -> some View {
        let c = compare(tr, an.ref)
        let cs: [Corner] = an.jsNow?.coach ?? (an.ref != nil ? corners(c, turns: an.turns, off: an.coach?.off ?? []) : [])
        let lose = cs.filter { $0.tip != nil && $0.lost > 0.03 }.sorted { $0.lost > $1.lost }
        if an.ref == nil { Text(t("no_reference")).font(.caption).foregroundColor(Theme.muted) }
        else if !cs.isEmpty { summary(cs, lose, c) }
        if tr.hasShape || an.layout != nil { TrackMapView(c: c, trace: tr, pick: $pick, turns: an.turns, road: an.layout, cs: an.jsNow?.corners) }
        // the web's sectors (the game's when both laps have them, else thirds of the lap from the traces), else the game's
        if let s = an.jsNow?.secs, !s.isEmpty { SectorTable(a: s.map { $0.0 }, b: s.map { $0.1 }) }
        else if !an.lap.sectors.isEmpty { SectorTable(a: an.lap.sectors, b: an.refSectors) }
        if !lose.isEmpty {
            SectionLabel(text: t("coach_top").uppercased())
            ForEach(Array(lose.prefix(3)), id: \.self) { k in
                Panel {
                    CornerTipView(k: k, an: an)
                    PhaseRow(k: k)
                    if k.coastA - k.coastB > 10 { Text(t("coasting") + ": \(Int(k.coastA)) m · " + t("ref") + " \(Int(k.coastB)) m").font(.caption2).foregroundColor(Theme.muted) }
                }
            }
        }
        // what this car does on other tracks, when nobody known is ahead of this lap here
        if let car = an.car, an.fastest || an.ref == nil { CarCardView(card: car, trace: tr) }
    }
}

/// "DRINKS · Ana" (or "Multiple drivers") when friends drove laps of a session, and "vs AI" for one against iRacing's AI.
struct SessionBadges: View {
    let x: CloudSession
    var body: some View {
        if !x.drvs.isEmpty || x.ai || x.game == "lmu" {
            HStack(spacing: 6) {
                if x.game == "lmu" { LmuPill() }
                if !x.drvs.isEmpty {
                    Text("DRINKS · " + (x.drvs.count > 1 ? t("drinks_multiple") : x.drvs[0])).font(.system(size: 10, weight: .bold)).foregroundColor(Color(red: 1, green: 0.886, blue: 0.659)).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 2).background(Theme.accent.opacity(0.22)).overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1)).clipShape(Capsule())
                }
                if x.ai {
                    Text(t("vs_ai")).font(.system(size: 10, weight: .bold)).foregroundColor(Theme.blue).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(Theme.blue.opacity(0.55), lineWidth: 1))
                }
            }
        }
    }
}

/// A session in My sessions: its track, car, kind, day and laps, your best lap, and who drove it in DRINKS mode.
struct SessionRow: View {
    let x: CloudSession
    var on = false
    var body: some View {
        Panel {
            Text(fixText(x.track) + (x.trackConfig.isEmpty ? "" : " · " + fixText(x.trackConfig))).font(.headline.weight(.black)).foregroundColor(Theme.fg).lineLimit(1)
            Text(fixText(x.car)).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
            SessionBadges(x: x)
            HStack {
                Text([placeLine(x), kindText(x.kind), day(x.started), t("laps_n", x.laps)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                LicBadge(k: x.lic)
                Spacer()
                Text(lapTime(x.best)).font(.system(.subheadline, design: .monospaced).bold()).foregroundColor(Theme.purple)
            }
            .padding(.top, 4)
        }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent : Color.clear, lineWidth: 1))
    }
}

/// The session Laps and the Coach show, with the button that opens My sessions to choose another.
struct SessionHead: View {
    let x: CloudSession
    let choose: () -> Void
    var body: some View {
        Panel {
            Text(fixText(x.track) + (x.trackConfig.isEmpty ? "" : " · " + fixText(x.trackConfig))).font(.headline.weight(.black)).foregroundColor(Theme.fg).lineLimit(1)
            Text(fixText(x.car)).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
            SessionBadges(x: x)
            HStack(spacing: 6) {
                Text([placeLine(x), kindText(x.kind), day(x.started), sessCat(x)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                LicBadge(k: x.lic)
                Spacer()
                Button(t("choose_session") + " ▾", action: choose).font(.caption.bold()).foregroundColor(Theme.accent).lineLimit(1)
            }
        }
    }
}

/// The game's official sectors of a lap when they add up to its time, like the web's lap list (lapSecsOf); else none.
func lapSecs(_ l: CloudLap) -> [Double] {
    let s = l.sectors
    return l.time > 0 && s.count >= 2 && s.allSatisfy({ $0 > 0 }) && abs(s.reduce(0, +) - l.time) < 1 ? s : []
}

/// A session's laps: its best and average, then every lap with its sectors and, in DRINKS mode, its driver (tap one to
/// analyse it).
struct SessionLaps: View {
    let session: CloudSession
    let laps: [CloudLap]
    var body: some View {
        // your laps only: a friend's lap (DRINKS mode) is never the account's best
        let mine = laps.filter { $0.valid && $0.time > 0 && $0.drv.isEmpty }
        let valid = mine.isEmpty ? laps.filter { $0.valid && $0.time > 0 } : mine
        let best = valid.map(\.time).min()
        let nSec = laps.map { lapSecs($0).count }.max() ?? 0
        // fastest time of each sector over the valid laps, in purple like in the sim
        let bestSec: [Double?] = (0..<nSec).map { i in valid.compactMap { lapSecs($0)[safe: i] }.min() }
        // a sector better than the same sector of your best lap is green, like the web's lap list
        let bestLapSec: [Double] = valid.min { $0.time < $1.time }.map(lapSecs) ?? []
        // the average of the valid laps: a real figure, not a lap made of the best sectors
        let avg: Double? = valid.isEmpty ? nil : valid.map(\.time).reduce(0, +) / Double(valid.count)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Metric(label: t("best"), value: lapTime(best), color: Theme.purple)
                Metric(label: t("average"), value: lapTime(avg))
            }
            .fixedSize(horizontal: false, vertical: true)
            if laps.isEmpty { EmptyNote(text: t("no_laps")) }
            else {
                HStack {
                    SectionLabel(text: t("laps").uppercased())
                    Spacer()
                    Text(t("tap_lap")).font(.caption2).foregroundColor(Theme.muted)
                }
                ForEach(laps) { lap in
                    NavigationLink(value: Route.lap(session, lap, laps)) { LapRow(lap: lap, best: best, bestSec: bestSec, bestLapSec: bestLapSec, nSec: nSec) }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LapRow: View {
    let lap: CloudLap
    let best: Double?
    let bestSec: [Double?]
    let bestLapSec: [Double]
    let nSec: Int
    var body: some View {
        Panel {
            HStack {
                Text("L\(lap.n)").font(.system(.subheadline, design: .monospaced)).foregroundColor(Theme.muted).frame(width: 44, alignment: .leading)
                Text(lapTime(lap.time)).font(.system(.subheadline, design: .monospaced).bold())
                    .foregroundColor(!lap.valid ? Theme.muted : lap.time == best ? Theme.purple : Theme.fg).strikethrough(!lap.valid)
                Spacer()
                if let best, lap.valid, lap.time > best { Text(String(format: "+%.3f", lap.time - best)).font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.muted) }
                if lap.inc > 0 { Text("\(lap.inc)x").font(.system(size: 11, design: .monospaced)).foregroundColor(Theme.bad) }
                if !lap.valid { Text(t("invalid")).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.bad) }
                Image(systemName: "chevron.right").foregroundColor(Theme.muted)
            }
            if !lap.drv.isEmpty { Text(lap.drv).font(.caption2).foregroundColor(Theme.accent).lineLimit(1) }
            // one column per sector (S1, S2, S3…), the same place on every lap: purple the session's best, green better than your best lap's
            if nSec > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        ForEach(0..<nSec, id: \.self) { i in
                            let s: Double? = lapSecs(lap)[safe: i]
                            Text("S\(i + 1) " + (s.map { String(format: "%.3f", $0) } ?? "–")).font(.system(size: 11, design: .monospaced))
                                .foregroundColor(secColor(i, s)).frame(width: 84, alignment: .leading)
                        }
                    }
                }
            }
        }
    }

    private func secColor(_ i: Int, _ s: Double?) -> Color {
        guard let s else { return Theme.muted }
        if lap.valid && i < bestSec.count && bestSec[i] == s { return Theme.purple }
        if lap.valid && i < bestLapSec.count && bestLapSec.count == lapSecs(lap).count && s < bestLapSec[i] - 1e-4 { return Theme.good }
        return Theme.muted
    }
}
