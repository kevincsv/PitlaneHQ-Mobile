import SwiftUI
import UIKit

// ---------- Telemetry: the same three tabs as the PC's (what matters while driving, the standings, the tyres) ----------

/// the delta of the top card and the delta bar: iRacing's to your best lap; in DRINKS mode the driver's own (LiveLaps)
@MainActor func liveDelta(_ l: Live) -> Double? {
    if l.drinks?.on ?? false { return l.ownDelta }
    if l.num("LapDeltaToBestLap_OK") == 0 { return nil }
    return l.num("LapDeltaToBestLap")
}

@MainActor func liveBestLap(_ l: Live) -> Double? {
    if l.drinks?.on ?? false { return l.ownBest }
    guard let b = l.num("LapBestLapTime"), b > 0 else { return nil }
    return b
}

func signedS(_ v: Double, _ d: Int = 1) -> String { (v >= 0 ? "+" : "−") + String(format: "%.\(d)f", abs(v)) }

struct LiveTabsView: View {
    @ObservedObject var live: Live
    @EnvironmentObject var account: Account
    @State private var sub = 0
    @State private var lmode = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Tabs(labels: [t("tab_telemetry"), t("tab_standings"), t("tab_tyres")], selected: $sub)
                .onChange(of: sub) { v in Usage.count("view:" + ["live", "standings", "tyres"][min(max(v, 0), 2)]) }
            switch sub {
            case 0:
                // Basic, Full (the lap's traces too) or Compare laps, live, like the PC and the web
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array([t("lm_basic"), t("lm_full"), t("lm_cmp")].enumerated()), id: \.offset) { i, l in LiveChip(label: l, on: lmode == i) { lmode = i } }
                    }
                }
                if lmode == 2 {
                    LiveCompareView(live: live)
                } else {
                    LiveTopView(live: live)
                    LiveDeltaBarView(live: live)
                    if lmode == 1 { LiveTracesView(live: live) }
                    LiveMapView(live: live)
                    LiveRelativeView(live: live)
                    LiveFuelView(live: live)
                    LiveIncidentsView(live: live)
                }
            case 1:
                LiveStandingsView(live: live)
                PosHistoryView(live: live)
            default:
                LiveTyresView(live: live)
            }
        }
        .onAppear { account.loadDriverNotes() }
    }
}

/// the laps a car is up (+) or down (−) on you: a red "+1L" or a blue "−1L", like the relative of the PC
struct LapPill: View {
    let lapDiff: Double
    var body: some View {
        let n = Int(lapDiff.rounded())
        if abs(lapDiff) >= 0.5 && n != 0 {
            let col = n > 0 ? Theme.bad : Theme.blue
            Text((n > 0 ? "+\(n)" : "−\(-n)") + "L").font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(col)
                .padding(.horizontal, 4).padding(.vertical, 1).overlay(Capsule().stroke(col.opacity(0.6), lineWidth: 1))
        }
    }
}

/// a driver's name in the relative and the standings: your note's icon first, then the name, its laps up or down
struct LiveName: View {
    let r: LiveRow
    @EnvironmentObject var account: Account
    var body: some View {
        HStack(spacing: 4) {
            if !r.me, let d = r.d, let n = account.noteFor(d.key, d.name), !n.tag.isEmpty { TagIcon(tag: n.tag).frame(width: 12, height: 12) }
            Text(r.d?.name ?? "#\(r.idx)").font(.system(size: 12, weight: r.me ? .black : .regular)).foregroundColor(r.me ? Theme.accent : Theme.fg).lineLimit(1)
            if r.pen { PenaltyClock(size: 12) }
            if r.d?.ai ?? false { Text(t("ai_driver")).font(.system(size: 9, weight: .bold)).foregroundColor(Theme.blue) }
            if !r.me { LapPill(lapDiff: r.lapDiff) }
            if r.pit { Text(t("lt_pit")).font(.system(size: 9, weight: .bold)).foregroundColor(Theme.muted) }
        }
    }
}

/// the top of the Telemetry screen: where you are, the delta and your best, the last lap, the fuel; beside it the gaps
/// to the cars just ahead and behind, your incidents and what is left of the session
struct LiveTopView: View {
    @ObservedObject var live: Live
    var body: some View {
        let ses = live.session
        let sn = live.num("SessionNum").map { Int($0) }
        let kind = sn.flatMap { ses?.kinds[$0] } ?? ""
        let drk = live.drinks?.on ?? false
        let dlt = liveDelta(live)
        let best = liveBestLap(live)
        let last = live.num("LapLastLapTime").flatMap { $0 > 0 ? $0 : nil }
        let field = ses?.drivers.values.filter { !$0.pace && !$0.spectator }.count ?? 0
        let pos = live.num("PlayerCarPosition").flatMap { $0 > 0 ? Int($0) : nil }
        let total = sn.flatMap { ses?.laps[$0] }.flatMap { $0 > 0 && $0 < 32000 ? $0 : nil }
        let lap = live.num("Lap").map { Int($0) }
        let fuel = live.num("FuelLevel")
        let perLap = live.num("FuelUsePerLap").flatMap { $0 > 0.01 ? $0 : nil }
        let ab = live.aheadBehind()
        let inc = live.num("PlayerCarMyIncidentCount").map { Int($0) }
        let lapsLeft = live.num("SessionLapsRemainEx").flatMap { $0 >= 0 && $0 < 32000 ? Int($0) : nil }
        let timeLeft = live.num("SessionTimeRemain").flatMap { $0 > 0 && $0 < 604800 ? $0 : nil }
        let who = drk && !(live.drinks?.driver ?? "").isEmpty ? " · " + (live.drinks?.driver ?? "") : ""
        // what the cards say, worked out here so SwiftUI has little to type-check in the views
        let posText: String = pos.map { "P\($0)" + (field > 1 ? "/\(field)" : "") } ?? "—"
        let lapNo: String? = lap.map { "\($0)" + (total.map { "/\($0)" } ?? "") }
        let lapSub: String? = lapNo.map { t("lt_lap_of", $0) }
        let dltText: String = dlt.map { signedS($0, 2) } ?? "—"
        let dltColor: Color = dlt == nil ? Theme.fg : dlt! <= 0 ? Theme.good : Theme.bad
        let bestSub: String? = best.map { t("lt_best_t", lapTime($0)) + who }
        let isBest: Bool = { guard let l = last, let b = best else { return false }; return l <= b + 0.001 }()
        let lastSub: String? = { () -> String? in
            guard let l = last, let b = best else { return nil }
            return l <= b + 0.001 ? t("lt_your_best") : t("lt_off_best", String(format: "%.2f", l - b))
        }()
        let lastColor: Color = isBest ? Theme.purple : Theme.fg
        let fuelText: String = fuel.map { String(format: "%.1f L", $0) } ?? "—"
        let fuelSub: String? = { () -> String? in
            guard let f = fuel, let p = perLap else { return nil }
            return t("lt_laps", String(format: "%.1f", f / p))
        }()
        let isRace = kind.lowercased().contains("race")
        let aheadText: String = ab.0.map { String(format: "−%.1f s", $0) } ?? "—"
        let behindText: String = ab.1.map { String(format: "+%.1f s", $0) } ?? "—"
        let incText: String = inc.map { "\($0)x" } ?? "—"
        let leftText: String = { () -> String in
            if let n = lapsLeft { return t("lt_laps", n) }
            if let s = timeLeft { return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
            return "—"
        }()
        let title: String = ses.map { $0.track.isEmpty ? t("tab_telemetry") : $0.track } ?? t("tab_telemetry")
        VStack(spacing: 10) {
            Panel {
                Text(title).font(.headline.weight(.black)).lineLimit(1)
                if !kind.isEmpty { Text(kind).font(.caption).foregroundColor(Theme.muted) }
                HStack(spacing: 8) {
                    Metric(label: t("lt_position"), value: posText, sub: lapSub)
                    Metric(label: "Delta", value: dltText, color: dltColor, sub: bestSub)
                }
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Metric(label: t("lt_last"), value: lapTime(last), color: lastColor, sub: lastSub)
                    Metric(label: t("lt_fuel"), value: fuelText, sub: fuelSub)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            Panel {
                SectionLabel(text: (isRace ? t("lt_race") : t("lt_session")).uppercased())
                InfoRow(label: t("lt_ahead"), value: aheadText)
                InfoRow(label: t("lt_behind"), value: behindText)
                InfoRow(label: t("lt_incidents"), value: incText, color: (inc ?? 0) >= 8 ? Theme.bad : Theme.fg)
                InfoRow(label: t("lt_left"), value: leftText)
            }
        }
    }
}

/// the delta bar: a track with the delta from its centre (one second to each side) and the value in a pill
struct LiveDeltaBarView: View {
    @ObservedObject var live: Live
    var body: some View {
        let d = liveDelta(live)
        Panel {
            SectionLabel(text: t("lt_deltabar").uppercased())
            HStack {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.surface2)
                        if let d {
                            let f = CGFloat(min(max(d, -1), 1)), w = abs(f) * g.size.width / 2
                            Rectangle().fill(d <= 0 ? Theme.good : Theme.bad).frame(width: w).offset(x: f < 0 ? g.size.width / 2 - w : g.size.width / 2)
                        }
                        Rectangle().fill(Theme.fg).frame(width: 2).offset(x: g.size.width / 2 - 1)
                    }
                }
                .frame(height: 14)
                Text(d.map { signedS($0, 2) } ?? "—").font(.system(size: 16, weight: .black, design: .monospaced))
                    .foregroundColor(d == nil ? Theme.fg : d! <= 0 ? Theme.good : Theme.bad).frame(minWidth: 64, alignment: .trailing)
            }
        }
    }
}

/// the relative: the cars just ahead and behind you on track, with the time to them
struct LiveRelativeView: View {
    @ObservedObject var live: Live
    var body: some View {
        let rows = live.relative(3)
        Panel {
            SectionLabel(text: t("lt_relative").uppercased())
            if rows.isEmpty { Text(t("lt_no_cars")).font(.caption).foregroundColor(Theme.muted) }
            ForEach(rows) { r in
                HStack(spacing: 4) {
                    Text(r.pos > 0 ? "P\(r.pos)" : "").foregroundColor(Theme.muted).frame(width: 34, alignment: .leading)
                    Text(r.d.map { "#" + $0.number } ?? "").foregroundColor(Theme.muted).frame(width: 36, alignment: .leading)
                    LiveName(r: r)
                    Spacer()
                    if let lic = r.d?.lic, !lic.isEmpty { Text(String(lic.split(separator: " ").first ?? "")).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted) }
                    Text(r.me ? "—" : r.gap.map { signedS($0) } ?? "—").bold().frame(minWidth: 48, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.vertical, 4).padding(.horizontal, 4)
                .background(r.me ? Theme.accent.opacity(0.12) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

/// the standings: every car in order, its last and best lap and its gap to the leader
struct LiveStandingsView: View {
    @ObservedObject var live: Live
    @State private var cls = ""
    @State private var interval = false
    var body: some View {
        let all = live.standings()
        let classes = all.compactMap { r -> String? in guard let c = r.d?.cls, !c.isEmpty else { return nil }; return c }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let rows = classes.count > 1 && !cls.isEmpty ? all.filter { $0.d?.cls == cls } : all
        let bestAll = rows.compactMap { $0.best }.min()
        let lead = rows.first?.gap ?? 0
        Panel {
            SectionLabel(text: t("tab_standings").uppercased() + (rows.isEmpty ? "" : " · " + t("lt_drivers_n", rows.count)))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    LiveChip(label: t("lm_to_leader"), on: !interval) { interval = false }
                    LiveChip(label: t("lm_interval"), on: interval) { interval = true }
                    if classes.count > 1 {
                        LiveChip(label: t("lm_all_classes"), on: cls.isEmpty) { cls = "" }.padding(.leading, 6)
                        ForEach(classes, id: \.self) { c in LiveChip(label: c, on: cls == c) { cls = c } }
                    }
                }
            }
            if rows.isEmpty { Text(t("lt_no_cars")).font(.caption).foregroundColor(Theme.muted) }
            if !rows.isEmpty {
                HStack(spacing: 4) {
                    Text("P").frame(width: 30, alignment: .leading)
                    Text("#").frame(width: 34, alignment: .leading)
                    Text(t("lt_driver"))
                    Spacer()
                    Text(t("last")).frame(width: 62, alignment: .leading)
                    Text(t("best")).frame(width: 62, alignment: .leading)
                    Text(interval ? t("lm_int") : t("lt_gap")).frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted)
            }
            ForEach(Array(rows.enumerated()), id: \.element.id) { k, r in
                HStack(spacing: 4) {
                    Text("\(r.pos)").foregroundColor(r.me ? Theme.accent : Theme.muted).frame(width: 30, alignment: .leading)
                    Text(r.d?.number ?? "").foregroundColor(Theme.muted).frame(width: 34, alignment: .leading)
                    LiveName(r: r)
                    Spacer()
                    Text(r.last.map { lapTime($0) } ?? "—").frame(width: 62, alignment: .leading)
                    Text(r.best.map { lapTime($0) } ?? "—").foregroundColor(r.best != nil && r.best == bestAll ? Theme.purple : Theme.fg).frame(width: 62, alignment: .leading)
                    let gp: Double? = k == 0 ? nil : interval ? rows[k - 1].gap.flatMap { p in r.gap.map { $0 - p } } : r.gap.map { $0 - lead }
                    Text(k == 0 ? "—" : gp.map { String(format: "+%.1f", $0) } ?? "—").frame(width: 44, alignment: .trailing)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.vertical, 4)
                .background(r.me ? Theme.accent.opacity(0.12) : Color.clear).clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }
}

/// the fuel: what is in the tank, how many laps it lasts and the use per lap
struct LiveFuelView: View {
    @ObservedObject var live: Live
    var body: some View {
        let fuel = live.num("FuelLevel"), per = live.num("FuelUsePerLap").flatMap { $0 > 0.01 ? $0 : nil }
        Panel {
            SectionLabel(text: t("lt_fuel").uppercased())
            HStack(spacing: 8) {
                Metric(label: t("lt_in_tank"), value: fuel.map { String(format: "%.1f L", $0) } ?? "—")
                Metric(label: t("lt_laps_fuel"), value: fuel != nil && per != nil ? String(format: "%.1f", fuel! / per!) : "—")
                Metric(label: t("lt_per_lap"), value: per.map { String(format: "%.2f L", $0) } ?? "—")
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// your incidents in this session
struct LiveIncidentsView: View {
    @ObservedObject var live: Live
    var body: some View {
        let inc = live.num("PlayerCarMyIncidentCount").map { Int($0) }
        Panel {
            SectionLabel(text: t("lt_incident_log").uppercased())
            Text(inc.map { "\($0)x" } ?? "—").font(.system(size: 30, weight: .black)).foregroundColor((inc ?? 0) >= 8 ? Theme.bad : Theme.fg)
            if inc == 0 { Text(t("lt_clean")).font(.caption).foregroundColor(Theme.good) }
        }
    }
}

/// the live map: the track's layout drawn by the community, as a road with depth, the start/finish line with the
/// direction, the official turns, and every car where its lap distance puts it (you in amber)
struct LiveMapView: View {
    @ObservedObject var live: Live
    @EnvironmentObject var account: Account
    @State private var key: Int64 = 0
    @State private var layout: ([Double], [Double])?
    @State private var turns: [Double] = []
    var body: some View {
        let tid = live.session?.trackId ?? 0
        Panel {
            SectionLabel(text: t("lt_map").uppercased())
            if let lay = layout, key == tid, lay.0.count > 20 {
                Canvas { ctx, size in draw(ctx, size, lay.0, lay.1) }.frame(height: 240)
            } else {
                Text(tid > 0 ? t("lt_map_none") : t("lt_no_cars")).font(.caption).foregroundColor(Theme.muted)
            }
        }
        // the layouts and turns are per game: the one your PC reads
        .task(id: "\(tid)-\(live.source)") {
            guard tid > 0 else { return }
            let g = live.source.isEmpty ? "iracing" : live.source
            layout = await account.trackLayout(trackId: tid, game: g)
            turns = await account.turns(trackId: tid, game: g)
            key = tid
        }
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize, _ xs: [Double], _ ys: [Double]) {
        let n = xs.count, pad: CGFloat = 22
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let k = min((size.width - 2 * pad) / CGFloat(max(1e-6, maxX - minX)), (size.height - 2 * pad) / CGFloat(max(1e-6, maxY - minY)))
        let ox = (size.width - 2 * pad - CGFloat(maxX - minX) * k) / 2, oy = (size.height - 2 * pad - CGFloat(maxY - minY) * k) / 2
        func pt(_ i: Int) -> CGPoint { CGPoint(x: pad + CGFloat(xs[i] - minX) * k + ox, y: size.height - pad - CGFloat(ys[i] - minY) * k - oy) }
        func at(_ f: Double) -> CGPoint {
            let q = (f.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1) * Double(n)
            let i = Int(q) % n, j = (i + 1) % n, r = CGFloat(q - Double(Int(q)))
            let a = pt(i), b = pt(j)
            return CGPoint(x: a.x + (b.x - a.x) * r, y: a.y + (b.y - a.y) * r)
        }
        var track = Path()
        for i in 0..<n { if i == 0 { track.move(to: pt(i)) } else { track.addLine(to: pt(i)) } }
        track.closeSubpath()
        let w: CGFloat = 11
        // the track as a road with depth: its shadow, the rim and the darker asphalt inside
        ctx.stroke(track.offsetBy(dx: 1.5, dy: 2.5), with: .color(.black.opacity(0.38)), style: StrokeStyle(lineWidth: w + 2, lineCap: .round, lineJoin: .round))
        ctx.stroke(track, with: .color(Color(red: 0x3F / 255, green: 0x49 / 255, blue: 0x56 / 255)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        ctx.stroke(track, with: .color(Color(red: 0x15 / 255, green: 0x1A / 255, blue: 0x21 / 255)), style: StrokeStyle(lineWidth: w - 3.5, lineCap: .round, lineJoin: .round))
        // the start/finish line across the road and the way the cars go beside it
        let p0 = pt(0), p1 = pt(max(2, n / 60))
        let dx = p1.x - p0.x, dy = p1.y - p0.y, m = max(1e-6, hypot(dx, dy)), ux = dx / m, uy = dy / m
        var nx = -uy, ny = ux
        if (p0.x - size.width / 2) * nx + (p0.y - size.height / 2) * ny < 0 { nx = -nx; ny = -ny }
        var sf = Path(); sf.move(to: CGPoint(x: p0.x - nx * w / 2, y: p0.y - ny * w / 2)); sf.addLine(to: CGPoint(x: p0.x + nx * w / 2, y: p0.y + ny * w / 2))
        ctx.stroke(sf, with: .color(.white), lineWidth: 3.5)
        let bx = p0.x + nx * (w / 2 + 8), by = p0.y + ny * (w / 2 + 8), tx = bx + ux * 18, ty = by + uy * 18, h: CGFloat = 6
        var shaft = Path(); shaft.move(to: CGPoint(x: bx, y: by)); shaft.addLine(to: CGPoint(x: tx - ux * h, y: ty - uy * h))
        ctx.stroke(shaft, with: .color(Theme.fg), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        var head = Path(); head.move(to: CGPoint(x: tx, y: ty)); head.addLine(to: CGPoint(x: tx - ux * h + nx * h * 0.6, y: ty - uy * h + ny * h * 0.6)); head.addLine(to: CGPoint(x: tx - ux * h - nx * h * 0.6, y: ty - uy * h - ny * h * 0.6)); head.closeSubpath()
        ctx.fill(head, with: .color(Theme.fg))
        // the official turns, beside the road
        for (ti, f) in turns.enumerated() {
            let i = min(max(Int(f * Double(n)), 0), n - 1), q = pt(i), q1 = pt((i + 2) % n), q0 = pt((i - 2 + n) % n)
            let tmx = q1.x - q0.x, tmy = q1.y - q0.y, tm = max(1e-3, hypot(tmx, tmy))
            var qx = -tmy / tm, qy = tmx / tm
            if (q.x - size.width / 2) * qx + (q.y - size.height / 2) * qy < 0 { qx = -qx; qy = -qy }
            ctx.draw(Text("\(ti + 1)").font(.system(size: 9, weight: .bold)).foregroundColor(Theme.muted), at: CGPoint(x: q.x + qx * (w / 2 + 9), y: q.y + qy * (w / 2 + 9)))
        }
        // the cars: you on top, the others dimmed in the pits, laps up red and down blue
        let pct = live.arrays["CarIdxLapDistPct"] ?? [], laps = live.arrays["CarIdxLap"] ?? [], pit = live.arrays["CarIdxOnPitRoad"] ?? []
        let me = live.meIdx
        let myLap = (me >= 0 && me < laps.count ? laps[me] : 0) + (me >= 0 && me < pct.count ? pct[me] : 0)
        let shown = pct.indices.filter { i in
            guard pct[i] >= 0 else { return false }
            if let d = live.session?.drivers[i], d.pace || d.spectator { return false }
            return true
        }
        let order = shown.filter { $0 != me } + shown.filter { $0 == me } // you drawn last, on top
        for i in order {
            let p = at(pct[i]), diff = (i < laps.count ? laps[i] : 0) + pct[i] - myLap
            let col = i == me ? Theme.accent : diff > 0.5 ? Theme.bad : diff < -0.5 ? Theme.blue : Theme.fg
            let r: CGFloat = i == me ? 7 : 5, a = (i < pit.count && pit[i] != 0) ? 0.45 : 1.0
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r - 1.5, y: p.y - r - 1.5, width: 2 * r + 3, height: 2 * r + 3)), with: .color(Theme.ink.opacity(a)))
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)), with: .color(col.opacity(a)))
        }
    }
}

/// the tyres: each one's three zones (outer, middle, inner) by temperature, the wear and the cold pressure, from the
/// last stop in the pit box (iRacing sends them only then)
struct LiveTyresView: View {
    @ObservedObject var live: Live
    var body: some View {
        let has = ["LF", "RF", "LR", "RR"].contains { live.num($0 + "tempCM") != nil }
        Panel {
            SectionLabel(text: t("tab_tyres").uppercased())
            Text(t("lt_tyres_note")).font(.caption).foregroundColor(Theme.muted).padding(.bottom, 6)
            if !has {
                Text(t("lt_tyres_none")).font(.caption).foregroundColor(Theme.muted)
            } else {
                HStack(spacing: 8) { tyre("LF", t("lt_fl")); tyre("RF", t("lt_fr")) }
                HStack(spacing: 8) { tyre("LR", t("lt_rl")); tyre("RR", t("lt_rr")) }
            }
        }
    }

    private func heat(_ v: Double?) -> Color {
        guard let v else { return Theme.surface2 }
        let f = min(max((v - 60) / 50, 0), 1)
        return f < 0.5 ? mix(Theme.blue, Theme.good, f * 2) : mix(Theme.good, Theme.bad, (f - 0.5) * 2)
    }

    private func mix(_ a: Color, _ b: Color, _ f: Double) -> Color {
        let ua = UIColor(a), ub = UIColor(b)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0, r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        ua.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        ub.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        let k = CGFloat(f)
        return Color(red: Double(r1 + (r2 - r1) * k), green: Double(g1 + (g2 - g1) * k), blue: Double(b1 + (b2 - b1) * k))
    }

    private func tyre(_ c: String, _ name: String) -> some View {
        let left = c.hasPrefix("L")
        let zones: [(String, String)] = left ? [("tempCL", "O"), ("tempCM", "M"), ("tempCR", "I")] : [("tempCL", "I"), ("tempCM", "M"), ("tempCR", "O")]
        let temps = zones.map { live.num(c + $0.0) }
        let wear = ["wearL", "wearM", "wearR"].map { live.num(c + $0) }
        let avg: Double? = temps.allSatisfy { $0 != nil } ? temps.compactMap { $0 }.reduce(0, +) / 3 : nil
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(c) · \(name)").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted).lineLimit(1)
                Spacer()
                Text(avg.map { String(format: "%.0f°", $0) } ?? "—").font(.system(size: 12, design: .monospaced))
            }
            HStack(spacing: 3) {
                ForEach(0..<3, id: \.self) { k in
                    VStack(spacing: 0) {
                        Text(temps[k].map { String(format: "%.0f", $0) } ?? "–").font(.system(size: 12, weight: .black))
                        Text(zones[k].1).font(.system(size: 9))
                    }
                    .foregroundColor(Theme.ink).frame(maxWidth: .infinity).padding(.vertical, 6)
                    .background(heat(temps[k])).clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            HStack {
                ForEach(0..<3, id: \.self) { k in
                    Text(wear[k].map { "\(Int(($0 * 100).rounded()))%" } ?? "–").font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted)
                    if k < 2 { Spacer() }
                }
            }
            if let wl = wear.compactMap({ $0 }).min() {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.line)
                        Capsule().fill(wl > 0.7 ? Theme.good : wl > 0.4 ? Theme.accent : Theme.bad).frame(width: g.size.width * CGFloat(min(max(wl, 0), 1)))
                    }
                }
                .frame(height: 5)
            }
            if let p = live.num(c + "coldPressure") { Text(t("lt_cold", String(format: "%.0f kPa", p))).font(.system(size: 10)).foregroundColor(Theme.muted) }
        }
        .padding(8).frame(maxWidth: .infinity).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// ---------- Telemetry's modes: Basic, Full (the lap's traces) and Compare laps (live), like the PC and the web ----------

/// a small on/off chip, like the web's
struct LiveChip: View {
    let label: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label).font(.system(size: 11, weight: .bold)).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.accent : Theme.surface2).foregroundColor(on ? Theme.bg : Theme.muted).clipShape(Capsule())
        }
    }
}

/// the rows of a lap against another, along the lap: speed, throttle and brake, the delta and the gear. A is drawn up
/// to `upto` (the point of the lap now), B whole.
struct LapRowsView: View {
    let a: RecLap
    let b: RecLap?
    let upto: Int
    let total: Int
    var bCol: Color = Theme.purple
    var body: some View {
        Canvas { ctx, size in
            let n = max(total, a.size, b?.size ?? 0, 2)
            let gap: CGFloat = 8, rh = (size.height - gap * 3) / 4
            func x(_ i: Int) -> CGFloat { CGFloat(i) / CGFloat(n - 1) * size.width }
            let top = (0..<4).map { CGFloat($0) * (rh + gap) }
            for y in top { ctx.fill(Path(CGRect(x: 0, y: y, width: size.width, height: rh)), with: .color(Theme.surface2)) }
            func line(_ vals: (Int) -> Double?, _ count: Int, _ row: Int, _ lo: Double, _ hi: Double, _ col: Color, _ w: CGFloat) {
                var p = Path(); var on = false
                for i in 0..<max(0, count) {
                    guard let v = vals(i) else { continue }
                    let f = min(max((v - lo) / max(1e-6, hi - lo), 0), 1)
                    let pt = CGPoint(x: x(i), y: top[row] + rh - CGFloat(f) * rh)
                    if on { p.addLine(to: pt) } else { p.move(to: pt); on = true }
                }
                ctx.stroke(p, with: .color(col), lineWidth: w)
            }
            func g<T>(_ a: [T], _ i: Int) -> T? { i >= 0 && i < a.count ? a[i] : nil }
            let vmax = max(a.sp.max() ?? 1, b?.sp.max() ?? 1, 1) * 1.05
            let aN = min(upto + 1, a.size)
            if let b {
                line({ g(b.sp, $0) }, b.size, 0, 0, vmax, bCol.opacity(0.8), 1.2)
                line({ g(b.thr, $0) }, b.size, 1, 0, 1, Theme.good.opacity(0.35), 1)
                line({ g(b.brk, $0) }, b.size, 1, 0, 1, Theme.bad.opacity(0.35), 1)
                line({ g(b.gear, $0).map(Double.init) }, b.size, 3, 0, 8, bCol.opacity(0.7), 1.2)
                // the delta: A's time against B's at the same point, ± from the middle of its row
                let ds = (0..<max(0, min(aN, b.size))).map { a.t[$0] - b.t[$0] }
                let m = max(0.3, ds.map { abs($0) }.max() ?? 0.3)
                var mid = Path(); mid.move(to: CGPoint(x: 0, y: top[2] + rh / 2)); mid.addLine(to: CGPoint(x: size.width, y: top[2] + rh / 2))
                ctx.stroke(mid, with: .color(Theme.line), lineWidth: 1)
                line({ g(ds, $0) }, ds.count, 2, -m, m, (ds.last ?? 0) <= 0 ? Theme.good : Theme.bad, 1.8)
            }
            line({ g(a.sp, $0) }, aN, 0, 0, vmax, Theme.accent, 1.8)
            line({ g(a.thr, $0) }, aN, 1, 0, 1, Theme.good, 1.6)
            line({ g(a.brk, $0) }, aN, 1, 0, 1, Theme.bad, 1.6)
            line({ g(a.gear, $0).map(Double.init) }, aN, 3, 0, 8, Theme.accent, 1.6)
            var cur = Path(); cur.move(to: CGPoint(x: x(max(0, aN - 1)), y: 0)); cur.addLine(to: CGPoint(x: x(max(0, aN - 1)), y: size.height))
            ctx.stroke(cur, with: .color(Theme.fg.opacity(0.5)), lineWidth: 1)
            for (k, s) in [t("lr_speed"), t("lr_pedals"), "Delta", t("lr_gear")].enumerated() {
                ctx.draw(Text(s).font(.system(size: 9, weight: .bold)).foregroundColor(Theme.muted), at: CGPoint(x: 4, y: top[k] + 3), anchor: .topLeading)
            }
        }
        .frame(height: 250)
    }
}

/// Full mode: the lap now drawn as it goes, against your best lap seen here
struct LiveTracesView: View {
    @ObservedObject var live: Live
    var body: some View {
        let _ = live.recVer
        let a = live.rec.cur, b = live.rec.best()
        let total = Int((live.session?.trackLen ?? 0) / 5)
        Panel {
            SectionLabel(text: t("lm_traces").uppercased())
            if let a, a.size >= 2 {
                HStack(spacing: 12) {
                    Text("● " + t("lm_now")).foregroundColor(Theme.accent)
                    if let b { Text("● " + t("lm_my_best") + " " + lapTime(b.time)).foregroundColor(Theme.purple) }
                }
                .font(.system(size: 11, weight: .bold))
                LapRowsView(a: a, b: b, upto: a.size - 1, total: total)
            } else {
                Text(t("lm_wait_lap")).font(.caption).foregroundColor(Theme.muted)
            }
        }
    }
}

/// Compare laps, live: the lap now against the one you choose (your best in purple, the last one, any other lap seen
/// here), the delta now and corner by corner by the official turns
struct LiveCompareView: View {
    @ObservedObject var live: Live
    @EnvironmentObject var account: Account
    @State private var pick = "best"
    @State private var turns: [Double] = []
    @State private var turnsFor: Int = 0
    var body: some View {
        let _ = live.recVer
        let rec = live.rec
        let total = Int((live.session?.trackLen ?? 0) / 5)
        let best = rec.best(), last = rec.last()
        let b: RecLap? = pick == "best" ? best : pick == "last" ? last : (rec.laps.first { "lap:\($0.n)" == pick } ?? best)
        Panel {
            SectionLabel(text: t("lm_cmp").uppercased())
            if let a = rec.cur, !rec.laps.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        LiveChip(label: t("lm_my_best"), on: pick == "best") { pick = "best" }
                        LiveChip(label: t("lm_last"), on: pick == "last") { pick = "last" }
                        ForEach(Array(rec.laps.filter { $0.time > 0 && $0 !== best && $0 !== last }.suffix(8).reversed().enumerated()), id: \.offset) { _, l in
                            LiveChip(label: t("lm_lap_n", l.n + 1) + " · " + lapTime(l.time), on: pick == "lap:\(l.n)") { pick = "lap:\(l.n)" }
                        }
                    }
                }
                let i = a.size - 1
                let now: Double? = (b != nil && i > 3 && i < b!.t.count) ? a.t[i] - b!.t[i] : nil
                HStack(spacing: 8) {
                    Metric(label: t("lm_best"), value: best.map { lapTime($0.time) } ?? "—", color: Theme.purple)
                    Metric(label: t("lm_last"), value: last.map { lapTime($0.time) } ?? "—")
                    Metric(label: t("lm_now_vs"), value: now.map { signedS($0, 2) } ?? "—", color: now == nil ? Theme.fg : (now! <= 0 ? Theme.good : Theme.bad))
                }
                if let b {
                    LapRowsView(a: a, b: b, upto: i, total: total, bCol: b === best ? Theme.purple : Theme.blue)
                    // corner by corner: from the middle of the straight before each turn to the middle of the one after it
                    let n = max(total, b.size)
                    if !turns.isEmpty && n > 0 {
                        let cuts = turns.map { Int($0 * Double(n)) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(Array(cuts.enumerated()), id: \.offset) { k, c in
                                    let s0 = k == 0 ? 0 : (cuts[k - 1] + c) / 2
                                    let e0 = k == cuts.count - 1 ? min(n - 1, c + (n - c) / 2) : (c + cuts[k + 1]) / 2
                                    let d: Double? = (e0 < a.size && e0 < b.size && s0 < e0) ? (a.t[e0] - a.t[s0]) - (b.t[e0] - b.t[s0]) : nil
                                    VStack(spacing: 1) {
                                        Text("T\(k + 1)").font(.system(size: 10, weight: .bold)).foregroundColor(Theme.muted)
                                        Text(d.map { signedS($0, 2) } ?? "·").font(.system(size: 11, design: .monospaced)).foregroundColor(d == nil ? Theme.muted : (d! <= 0 ? Theme.good : Theme.bad))
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 5).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                    }
                }
            } else {
                Text(t("lm_wait_cmp")).font(.caption).foregroundColor(Theme.muted)
            }
        }
        .task(id: "\(live.session?.trackId ?? 0)-\(live.source)") {
            let tid = live.session?.trackId ?? 0
            if tid > 0 { turns = await account.turns(trackId: tid, game: live.source.isEmpty ? "iracing" : live.source) }
        }
    }
}

/// your place at the end of every lap of this session
struct PosHistoryView: View {
    @ObservedObject var live: Live
    var body: some View {
        let _ = live.recVer
        let h = live.rec.posHist
        if h.count >= 2 {
            let lo = h.map { $0.pos }.min()!, hi = max(h.map { $0.pos }.max()!, lo + 1)
            Panel {
                SectionLabel(text: t("lm_pos_hist").uppercased())
                Canvas { ctx, size in
                    var p = Path()
                    for (k, e) in h.enumerated() {
                        let pt = CGPoint(x: CGFloat(k) / CGFloat(h.count - 1) * size.width, y: CGFloat(e.pos - lo) / CGFloat(hi - lo) * (size.height - 8) + 4)
                        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                    }
                    ctx.stroke(p, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
                }
                .frame(height: 110)
                HStack {
                    Text("P\(lo)").foregroundColor(Theme.muted)
                    Spacer()
                    Text(t("lt_lap_of", "\(h.last!.lap)")).foregroundColor(Theme.muted)
                    Spacer()
                    Text("P\(h.last!.pos)").foregroundColor(Theme.accent).bold()
                }
                .font(.system(size: 10))
            }
        }
    }
}
