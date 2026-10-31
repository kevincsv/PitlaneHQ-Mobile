import SwiftUI

// ---------- pieces ----------

struct Panel<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        // Track First's card: 16 rounded corners, a hairline edge
        VStack(alignment: .leading, spacing: 4) { content }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct SectionLabel: View {
    let text: String
    var body: some View {
        // the section titles: condensed capitals, spaced out
        Text(text.uppercased()).font(.display(14, .bold)).tracking(1.6).foregroundColor(Theme.muted).lineLimit(1)
    }
}

struct Metric: View {
    let label: String
    let value: String
    var color = Theme.fg
    var sub: String? = nil
    var body: some View {
        // a tile: the label in small mono capitals, the number big in mono, a grey line under it
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.mono(11, .semibold)).tracking(0.6).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(value).font(.mono(24, .bold)).foregroundColor(color).lineLimit(1).minimumScaleFactor(0.5)
            if let sub { Text(sub).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1) }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct StatusPill: View {
    let text: String
    let color: Color
    var body: some View {
        Text(text).font(.mono(10, .bold)).foregroundColor(color)
            .padding(.horizontal, 9).padding(.vertical, 5)
            .overlay(Capsule().stroke(color, lineWidth: 1))
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var color = Theme.fg
    var body: some View {
        HStack {
            Text(label).font(.ui(15)).foregroundColor(Theme.muted)
            Spacer()
            Text(value).font(.mono(15, .bold)).foregroundColor(color)
        }
        .padding(.vertical, 2)
    }
}

struct ActionRow: View {
    let title: String
    let sub: String
    let icon: String
    var body: some View {
        Panel {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundColor(Theme.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.ui(17, .black)).foregroundColor(Theme.fg)
                    Text(sub).font(.ui(12)).foregroundColor(Theme.muted)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(Theme.muted)
            }
        }
    }
}

struct MetricData {
    let label: String
    let value: String
    var color = Theme.fg
    var sub: String? = nil
}

/// Metric boxes in rows of the same height, so every box lines up.
struct MetricGrid: View {
    let items: [MetricData]
    let columns: Int
    var body: some View {
        let rows: [[MetricData]] = stride(from: 0, to: items.count, by: columns).map { Array(items[$0..<min($0 + columns, items.count)]) }
        VStack(spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, m in
                        Metric(label: m.label, value: m.value, color: m.color, sub: m.sub)
                    }
                    ForEach(0..<(columns - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Licence summary, like the web's Home: one card per discipline (its symbol and colour), your iRating with what your
/// last races of it gave, and the licence (class and safety rating) as the PC last saw them (the game only says the
/// discipline of the session you are in, so each updates when you drive it with Pitlane HQ open).
struct Licences: View {
    @EnvironmentObject var account: Account
    // a licence you press opens its iRating line under the list; Sports Car is open to start
    @State private var sel = "sports_car"
    var body: some View {
        let all = account.ratings()
        let races = account.races
        // Track First's grid: three small cards a row
        let rows: [[String]] = stride(from: 0, to: DISCS.count, by: 3).map { Array(DISCS[$0..<min($0 + 3, DISCS.count)]) }
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: t("licences")).padding(.top, 6)
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 6) {
                    ForEach(row, id: \.self) { k in
                        Button { sel = k } label: { LicCard(k: k, r: all[k], races: races, on: sel == k) }.buttonStyle(.plain)
                    }
                    ForEach(0..<(3 - row.count), id: \.self) { _ in Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            LicDetail(k: sel, r: all[sel], races: races).id(sel)
            Text(t("lic_note")).font(.ui(11)).foregroundColor(Theme.muted)
        }
    }
}

/// The licence you chose: its iRating and class, what its last races gave and their iRating line, which the finger reads.
struct LicDetail: View {
    let k: String
    let r: (ir: Int, lic: String, at: Double)?
    let races: [Race]
    @State private var pick: Int?
    var body: some View {
        let col = discColor(k)
        let line = irRaces(races, k, 20)
        let chg = line.reduce(0) { $0 + $1.irChange }
        let lic = (r?.lic ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let cls: String? = lic.isEmpty ? nil : (lic.hasPrefix("WC") || lic.hasPrefix("PRO") ? "P" : String(lic.prefix(1)))
        let parts = lic.split(separator: " ")
        let sr: String? = parts.count > 1 ? String(parts[1]) : nil
        let x: Race? = pick.flatMap { $0 < line.count ? line[$0] : nil }
        Panel {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(discName(k)).font(.ui(12, .semibold)).foregroundColor(Theme.muted)
                    Text(r.map { "\($0.ir)" } ?? "–").font(.mono(26, .black)).foregroundColor(r == nil ? Theme.muted : col)
                    if r != nil, let cls { LicBadge(k: cls, sr: sr) }
                    if line.isEmpty {
                        Text(t("no_races_yet").trimmingCharacters(in: CharacterSet(charactersIn: "."))).font(.mono(11)).foregroundColor(Theme.muted)
                    } else {
                        Text(t("lic_gain", signed(chg), line.count)).font(.mono(11)).foregroundColor(chg >= 0 ? Theme.good : Theme.bad)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    if line.count >= 2 {
                        Text(x.map { $0.track + " " + signed($0.irChange) } ?? t("spark_last", line.count)).font(.ui(10)).lineLimit(1)
                            .foregroundColor(x.map { $0.irChange >= 0 ? Theme.good : Theme.bad } ?? Theme.muted)
                        IrLine(vals: irVals(line, r?.ir), col: col, height: 60, sel: $pick, area: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Le Mans Ultimate's Safety Rating and Driver Rank as the PC last saw them ("lmu" in ratings.json, as the game wrote
/// them), like the web's Home; "In development" until the PC has written them.
struct LmuRatings: View {
    @EnvironmentObject var account: Account
    var body: some View {
        let r = account.lmuRating()
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: t("lmu_ratings"))
            Panel {
                if let r {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(Array([("Safety Rating", r.sr), ("Driver Rank", r.dr)].enumerated()), id: \.offset) { _, m in
                            let v = m.1
                            VStack(alignment: .leading, spacing: 3) {
                                Text(m.0).font(.ui(12, .semibold)).foregroundColor(Theme.muted).lineLimit(1)
                                Text(v.isEmpty ? "–" : v).font(.mono(20, .black)).foregroundColor(Theme.fg).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                } else {
                    StatusPill(text: t("in_development"), color: Theme.accent)
                }
            }
        }
    }
}

/// One discipline's card: its symbol, the iRating (with what your last five races of it gave, like the web) and the
/// licence pill ("B 3.21" in the licence's colour); dim while the PC has seen nothing of it.
struct LicCard: View {
    let k: String
    let r: (ir: Int, lic: String, at: Double)?
    let races: [Race]
    var on = false
    var body: some View {
        let lic = (r?.lic ?? "").trimmingCharacters(in: .whitespaces).uppercased()
        let cls: String? = lic.isEmpty ? nil : (lic.hasPrefix("WC") || lic.hasPrefix("PRO") ? "P" : String(lic.prefix(1)))
        let parts = lic.split(separator: " ")
        let sr: String? = parts.count > 1 ? String(parts[1]) : nil
        // Track First's licence card: the discipline small and grey, the iRating in mono, the licence chip; the chosen
        // one has an amber edge
        VStack(alignment: .leading, spacing: 3) {
            Text(discName(k)).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            Text(r.map { "\($0.ir)" } ?? "–").font(.mono(18, .bold)).foregroundColor(r == nil ? Theme.muted : Theme.fg).lineLimit(1)
            if r != nil, let cls { LicBadge(k: cls, sr: sr) }
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : Theme.line, lineWidth: on ? 2 : 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .opacity(r == nil && !on ? 0.55 : 1)
    }
}

/// The discipline's symbol, the same strokes as the web's (our own, never iRacing's), in a rounded square of its colour.
struct DiscIcon: View {
    let k: String
    var size: CGFloat = 30
    var body: some View {
        let col = discColor(k)
        let s = size * 0.6 / 24
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(col.opacity(0.12))
            RoundedRectangle(cornerRadius: 8).stroke(col, lineWidth: 1.5)
            // the symbol is SVG path data (the same as the web's): SwiftUI's Path(String) reads only its own format,
            // so it is parsed here
            if let p = svgPath(DISC_PATHS[k] ?? "") {
                p.applying(CGAffineTransform(scaleX: s, y: s))
                    .stroke(col, style: StrokeStyle(lineWidth: 1.8 * s, lineCap: .round, lineJoin: .round))
                    .frame(width: size * 0.6, height: size * 0.6)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Every corner as a small bar, like the web's analyzer: taller the more time it costs (red; green when it gains), its
/// official turn number under it. Touch one to read it on the map and the charts.
struct CornerStrip: View {
    let cs: [Corner]
    let lapLen: Double
    @Binding var pick: Double?
    var title = true
    var body: some View {
        let mx = max(0.05, cs.map { abs($0.lost) }.max() ?? 0.05)
        Panel {
            if title { SectionLabel(text: t("corners_strip")) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(cs, id: \.self) { k in CornerBar(k: k, f: Double(k.atM) / max(lapLen, 1), mx: mx, pick: $pick) }
                }
            }
        }
    }
}

private struct CornerBar: View {
    let k: Corner
    let f: Double
    let mx: Double
    @Binding var pick: Double?
    var body: some View {
        let on = pick.map { abs($0 - f) < 0.012 } ?? false
        let col: Color = k.lost > 0.02 ? Theme.bad : k.lost < -0.02 ? Theme.good : Theme.muted
        VStack(spacing: 3) {
            ZStack(alignment: .bottom) {
                Color.clear.frame(height: 40)
                RoundedRectangle(cornerRadius: 3).fill(col).frame(width: 14, height: 6 + 34 * abs(k.lost) / mx)
            }
            Text("T\(k.n)").font(.mono(10, .bold)).foregroundColor(on ? Theme.accent : Theme.muted)
            Text((k.lost >= 0 ? "+" : "−") + String(format: "%.2f", abs(k.lost))).font(.mono(9)).foregroundColor(col)
        }
        .frame(width: 36).padding(.vertical, 4)
        .background(on ? Theme.surface2 : Color.clear).cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { pick = f }
    }
}

/// The braking points of lap A against lap B, like the web's analyzer and Android's BrakeTable: per corner (its official
/// turn), where each lap brakes, the gap in metres (+ A later), the speed at each apex, the gear there, the time lost and
/// what to do (the tip in a few words). A row reads that corner on the map and the charts.
struct BrakeTable: View {
    let cs: [Corner]
    let lapLen: Double
    @Binding var pick: Double?
    private let w: [CGFloat] = [40, 62, 62, 44, 54, 54, 44, 58]
    var body: some View {
        let heads = [t("bt_turn"), t("bt_brake_a"), t("bt_brake_b"), "Δ m", t("bt_apex_a"), t("bt_apex_b"), t("gear"), t("bt_loss")]
        Panel {
            SectionLabel(text: t("brake_points"))
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(Array(heads.enumerated()), id: \.offset) { i, h in
                            Text(h.uppercased()).font(.ui(9)).foregroundColor(Theme.muted).lineLimit(1)
                                .frame(width: w[i] - (i == 0 ? 0 : 6), alignment: i == 0 ? .leading : .trailing).padding(.trailing, i == 0 ? 0 : 6)
                        }
                        Text(t("bt_todo").uppercased()).font(.ui(9)).foregroundColor(Theme.muted).lineLimit(1)
                            .frame(width: 204, alignment: .leading).padding(.leading, 6)
                    }
                    .padding(.bottom, 4)
                    ForEach(cs, id: \.self) { k in BrakeRow(k: k, f: Double(k.atM) / max(lapLen, 1), w: w, pick: $pick) }
                }
            }
        }
    }
}

private struct BrakeRow: View {
    let k: Corner
    let f: Double
    let w: [CGFloat]
    @Binding var pick: Double?
    var body: some View {
        let on = pick.map { abs($0 - f) < 0.012 } ?? false
        let dd: Int? = k.lift ? nil : k.dd
        let gear = k.gearA >= 1 && k.gearB >= 1 && k.gearA != k.gearB ? "\(k.gearA) / \(k.gearB)" : k.gearA >= 1 ? "\(k.gearA)" : k.gearB >= 1 ? "\(k.gearB)" : "–"
        let ddText: String = dd.map { abs($0) < 3 ? "≈ 0" : ($0 > 0 ? "+" : "−") + "\(abs($0))" } ?? "–"
        let cells: [(String, Color)] = [
            ("T\(k.n)", Theme.fg),
            (k.dd.map { "\(k.atM + $0) m" } ?? "–", Theme.fg),
            (k.lift ? t("bt_lift") : "\(k.atM) m", k.lift ? Theme.muted : Theme.fg),
            (ddText, dd.map { $0 <= -3 } == true ? Theme.bad : Theme.muted),
            (k.vA.map { String(format: "%.0f", $0) } ?? "–", Theme.fg),
            (String(format: "%.0f", k.vB), Theme.fg),
            (gear, Theme.fg),
            ((k.lost >= 0 ? "+" : "−") + String(format: "%.3f", abs(k.lost)), k.lost > 0.02 ? Theme.bad : k.lost < -0.02 ? Theme.good : Theme.muted),
        ]
        // the web's own "what to do" when the corner comes from pitwall-analysis.js (a copy without it, its tip in a few
        // words), else the fallback's tip in a few words
        let tip: String? = k.text != nil ? (k.todo ?? (k.lost > 0.03 ? k.text.map(tipShort) : nil)) : k.lost > 0.03 ? k.tip.map { tipShort(fillArgs(t($0), k.args)) } : nil
        HStack(alignment: .center, spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, cell in
                Text(cell.0).font(.mono(11, i == 0 ? .bold : .regular)).foregroundColor(i == 0 && on ? Theme.accent : cell.1).lineLimit(1)
                    .frame(width: w[i] - (i == 0 ? 0 : 6), alignment: i == 0 ? .leading : .trailing).padding(.trailing, i == 0 ? 0 : 6)
            }
            Text(tip ?? "–").font(.ui(11)).foregroundColor(tip == nil ? Theme.muted : Theme.fg).fixedSize(horizontal: false, vertical: true)
                .frame(width: 204, alignment: .leading).padding(.leading, 6)
        }
        .padding(.vertical, 5)
        .background(on ? Theme.surface2 : Color.clear).cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture { pick = f }
    }
}

/// Each discipline's colour, the same as the web's Community cards.
func discColor(_ k: String) -> Color {
    switch k {
    case "oval": return Color(red: 1, green: 0.69, blue: 0.18)
    case "sports_car": return Color(red: 0.35, green: 0.66, blue: 1)
    case "formula_car": return Color(red: 0.73, green: 0.55, blue: 1)
    case "dirt_oval": return Color(red: 0.79, green: 0.60, blue: 0.36)
    case "dirt_road": return Color(red: 0.56, green: 0.75, blue: 0.42)
    default: return Theme.fg
    }
}

/// What is only in the web and PC app for now, with a link to open the web.
/// The car card: what this car does on other tracks (its hardest braking, where the fast drivers shift up, its
/// top speed), learnt by the server from its laps everywhere, against what this lap did. Like the web's coach.
struct CarCardView: View {
    let card: [String: Any]
    let trace: Trace
    private func num(_ v: Any?) -> Double? { (v as? NSNumber)?.doubleValue }
    private func kmh(_ v: Double) -> String { "\(Int((v * 3.6).rounded())) km/h" }
    private func gee(_ v: Double) -> String { String(format: "%.2f g", v / 9.81) }
    /// The three lines, worked out away from the view so SwiftUI has nothing to type-check.
    private var lines: (from: String, brake: String, shift: String, vmax: String) {
        let f = lapFacts(trace.rows)
        let n = (card["n"] as? NSNumber)?.intValue ?? 0, tracks = (card["tracks"] as? NSNumber)?.intValue ?? 0
        let cardBrake = num(card["brake"]).flatMap { $0 > 0 ? $0 : nil }
        var brake = t("car_brake") + ": " + (cardBrake.map(gee) ?? "—") + " · "
        if let b = f.brake {
            brake += t("this_lap") + " " + gee(b)
            if let c = cardBrake { brake += " (\(Int((b / c * 100).rounded())) %)" }
        } else { brake += t("car_no_brake") }
        // the gear this lap shifted earliest against the fast drivers (the highest gear when the lap has no gear read)
        var pg = 0, pv = 0.0
        var pm: Double? = nil, pd: Double? = nil
        for p in (card["shifts"] as? [[NSNumber]]) ?? [] where p.count >= 2 {
            let g = p[0].intValue, v = p[1].doubleValue, mv = f.shifts[g], d = mv.map { $0 - v }
            if pg == 0 || (d != nil && (pd == nil || d! < pd!)) { pg = g; pv = v; pm = mv; pd = d }
        }
        var shift = t("car_shifts") + ": "
        if pg > 0 {
            shift += "\(pg)→\(pg + 1) " + kmh(pv)
            if let m = pm { shift += " · " + t("this_lap") + " " + kmh(m) + " (" + (m >= pv ? "+" : "−") + "\(Int((abs(m - pv) * 3.6).rounded())))" }
        } else { shift += t("car_no_shifts") }
        var vmax = t("car_vmax") + ": " + kmh(num(card["vmax"]) ?? 0)
        if let at = card["vmaxTrack"] as? String, !at.isEmpty { vmax += " " + t("car_at", at) }
        if f.vmax > 0 { vmax += " · " + t("this_lap") + " " + kmh(f.vmax) }
        return (t("car_card_from", n, tracks), brake, shift, vmax)
    }
    var body: some View {
        let l = lines
        Panel {
            Text(t("car_card")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            Text(l.from).font(.ui(12)).foregroundColor(Theme.muted)
            Text(l.brake).font(.ui(13)).foregroundColor(Theme.fg).padding(.top, 4)
            Text(l.shift).font(.ui(13)).foregroundColor(Theme.fg)
            Text(l.vmax).font(.ui(13)).foregroundColor(Theme.fg)
        }
    }
}

struct WebNote: View {
    let text: String
    var body: some View {
        Panel {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "info.circle").foregroundColor(Theme.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(text).font(.ui(12)).foregroundColor(Theme.fg)
                    Link(t("open_web"), destination: webApp).font(.ui(12, .bold))
                }
            }
        }
    }
}

/// The phone's short versions say where the full one is: a small grey line with the PC's symbol.
struct ShortNote: View {
    let key: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "desktopcomputer").font(.system(size: 13)).foregroundColor(Theme.muted.opacity(0.7))
            Text(t(key)).font(.ui(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct EmptyNote: View {
    let text: String
    var body: some View { Panel { Text(text).font(.ui(15)).foregroundColor(Theme.muted) } }
}

struct Tabs: View {
    let labels: [String]
    @Binding var selected: Int
    var body: some View {
        // Track First's sub-tabs: one dark well, the chosen tab a raised card; up to four share the width, more scroll
        if labels.count <= 4 {
            HStack(spacing: 2) { ForEach(Array(labels.enumerated()), id: \.offset) { i, l in item(i, l).frame(maxWidth: .infinity) } }
                .padding(3).background(Theme.well)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) { ForEach(Array(labels.enumerated()), id: \.offset) { i, l in item(i, l) } }
                    .padding(3).background(Theme.well)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private func item(_ i: Int, _ l: String) -> some View {
        let on = selected == i
        return Button { selected = i } label: {
            Text(l).font(.ui(13, on ? .semibold : .medium)).lineLimit(1).minimumScaleFactor(0.8)
                .padding(.horizontal, 10).padding(.vertical, 8).frame(maxWidth: labels.count <= 4 ? .infinity : nil)
                .foregroundColor(on ? Theme.fg : Theme.muted)
                .background(on ? Theme.surface : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(on ? Theme.line : Color.clear, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// Banners on top of every screen: no connection, demo data.
struct Banners: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var net: NetMonitor
    @EnvironmentObject var updates: Updates
    var body: some View {
        VStack(spacing: 0) {
            if !net.online { banner(t("showing_saved"), Theme.bad) }
            if account.demo { banner(t("demo_banner"), Theme.accent) }
            if let v = updates.version { Link(destination: updates.page) { banner(t("update_available", v), Theme.good) } }
        }
        .alert(t("update_title", updates.version ?? ""), isPresented: Binding(get: { updates.version != nil && shown != updates.version }, set: { if !$0 { shown = updates.version ?? "" } })) {
            Button(t("whats_new")) { UIApplication.shared.open(changelog(updates.version ?? "")) }
            Button(t("download")) { shown = updates.version ?? ""; UIApplication.shared.open(updates.page) }
            Button(t("later"), role: .cancel) { shown = updates.version ?? "" }
        } message: {
            Text(t("update_body", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""))
        }
    }

    // the notice shows once per version, when the app starts
    @State private var shown = ""
    private func changelog(_ v: String) -> URL { URL(string: changelogURL + "#" + v.replacingOccurrences(of: ".", with: "") + "-beta")! }

    private func banner(_ s: String, _ c: Color) -> some View {
        Text(s).font(.mono(11, .bold)).foregroundColor(Theme.ink)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.vertical, 6).background(c)
    }
}

struct Screen<Content: View>: View {
    let title: String
    var sub = ""
    /// iRacing | LMU under the title (Home, Tracks, Analysis, Community)
    var gameSeg = false
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss
    @Environment(\.isPresented) private var pushed
    var body: some View {
        // Track First's frame: the header stays put (Back, the title in condensed capitals, Info, the game), the
        // screen scrolls under it and ends above the floating tab bar
        VStack(spacing: 0) {
            Banners()
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    if pushed {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .semibold)).foregroundColor(Theme.fg)
                                .frame(width: 32, height: 36, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).accessibilityLabel(t("back"))
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title.uppercased()).font(.display(27, .bold)).tracking(0.5).foregroundColor(Theme.fg).lineLimit(1).minimumScaleFactor(0.7)
                        if !sub.isEmpty { Text(sub).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1) }
                    }
                    Spacer(minLength: 4)
                    InfoButton()
                }
                if gameSeg { GameSeg() }
            }
            .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) { content }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
        }
        .background(Theme.ink.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// The header draws its own Back, so the system bar is hidden; the swipe from the left edge still goes back.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }
    public func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool { viewControllers.count > 1 }
}

/// What a screen loads from the server: data, loading, an error and whether it is the saved copy.
@MainActor
final class Loader<T>: ObservableObject {
    @Published var data: T?
    @Published var loading = false
    @Published var error: String?
    @Published var stale = false

    func load(_ f: @escaping () async throws -> Got<T>) async {
        loading = true
        error = nil
        do {
            let g = try await f()
            data = g.data
            stale = g.stale
        } catch {
            self.error = (error as? AppError)?.key ?? error.localizedDescription
        }
        loading = false
    }
}

// ---------- the game you look at ----------

/// "Beta" beside Le Mans Ultimate wherever it is offered.
struct BetaPill: View {
    var on = false
    var body: some View {
        Text(t("beta")).font(.ui(9, .bold)).lineLimit(1).foregroundColor(on ? Theme.ink : Theme.accent)
            .padding(.horizontal, 5).overlay(Capsule().stroke((on ? Theme.ink : Theme.accent).opacity(0.6), lineWidth: 1))
    }
}

/// A session or race of Le Mans Ultimate, like the vs AI and DRINKS pills.
struct LmuPill: View {
    var body: some View {
        Text("LMU").font(.ui(10, .bold)).tracking(0.4).lineLimit(1).foregroundColor(Theme.purple)
            .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(Theme.purple.opacity(0.55), lineWidth: 1))
    }
}

/// iRacing | LMU in the header of Home, Analysis and Community: what this phone shows, never what your PC reads.
/// The game your PC is reading live is marked ●.
struct GameSeg: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var live: Live
    var body: some View {
        HStack(spacing: 3) {
            ForEach(games, id: \.self) { g in
                let on = account.game == g
                Button { account.setGame(g) } label: {
                    HStack(spacing: 5) {
                        Text(gameShort(g) + (live.pcGame == g ? " ●" : "")).font(.ui(13, on ? .semibold : .medium)).lineLimit(1)
                        if g == "lmu" { BetaPill() }
                    }
                    // the chosen game a raised card in the dark well, like the sub-tabs
                    .foregroundColor(on ? Theme.fg : Theme.muted)
                    .frame(maxWidth: .infinity).padding(.vertical, 7)
                    .background(on ? Theme.surface : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(on ? Theme.line : Color.clear, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3).background(Theme.well).overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// When the app opens, your PC is not live and you drove both games: which one to see (remembered on this phone).
struct GameSheet: View {
    @EnvironmentObject var account: Account
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("gs_title")).font(.ui(20, .black)).foregroundColor(Theme.fg)
            ForEach(games, id: \.self) { g in
                let st = account.gameStats[g] ?? (n: 0, last: 0)
                let on = account.game == g
                Button { account.setGame(g) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) { Text(gameName(g)).font(.ui(17, .black)).foregroundColor(Theme.fg); if g == "lmu" { BetaPill() } }
                        Text([t("gs_sessions", st.n), st.last > 0 ? t("gs_last", day(st.last)) : ""].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted)
                        Text(t("gs_see", gameName(g))).font(.ui(15, .bold)).padding(.horizontal, 14).padding(.vertical, 8)
                            .background(on ? Theme.accent : Theme.surface2).foregroundColor(on ? Theme.ink : Theme.fg).clipShape(RoundedRectangle(cornerRadius: 8)).padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    .background(Theme.ink).overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent : Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium])
    }
}

/// Loading spinner, error with a retry button, and the "saved copy" note.
struct LoadState: View {
    let loading: Bool
    let error: String?
    var stale = false
    let retry: () -> Void
    var body: some View {
        if loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity) }
        if let error {
            Panel {
                Text(t(error)).font(.ui(15)).foregroundColor(Theme.bad)
                Button(t("retry").uppercased(), action: retry).font(.ui(15, .bold))
            }
        } else if stale {
            Text(t("showing_saved")).font(.ui(12)).foregroundColor(Theme.accent)
        }
    }
}

enum Route: Hashable {
    case race(Race)
    case session(CloudSession)
    case lap(CloudSession, CloudLap, [CloudLap])
    case combo(Combo)
    case track(TrackRef)
    /// Analysis on one of its tabs (Laps, Coach, My sessions, My races), on a session or on your newest
    case analysis(Int, CloudSession?)
    case profile(String?)
    case notes
    /// the Planner (in development) and one of its series
    case planner
    case plannerSeries(SSeries)
}

extension View {
    func routes() -> some View {
        navigationDestination(for: Route.self) { r in
            switch r {
            // what the drivers use, for the admin panel: every screen opened
            case let .race(x): RaceView(race: x).onAppear { Usage.count("act:race_summary") }
            case let .session(s): SessionView(session: s).onAppear { Usage.count("view:session") }
            case let .lap(s, l, all): LapView(session: s, lap: l, all: all).onAppear { Usage.count("act:compare") }
            case let .combo(c): ComboView(combo: c).onAppear { Usage.count("act:leaderboard") }
            case let .track(r): TrackPageView(ref: r).onAppear { Usage.count("act:track_page") }
            case let .analysis(tb, s): AnalysisView(startTab: tb, start: s)
            case let .profile(id): ProfileView(lapId: id).onAppear { Usage.count("view:profile") }
            case .notes: TrackNotesList().onAppear { Usage.count("view:notes") }
            case .planner: PlannerView()
            case let .plannerSeries(x): PlannerSeriesView(s: x)
            }
        }
    }
}

// ---------- sign in ----------

struct LoginView: View {
    @EnvironmentObject var account: Account
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Spacer(minLength: 48)
                Text("PITLANE HQ").font(.ui(34, .black)).foregroundColor(Theme.fg)
                Text(t("companion")).font(.mono(12, .bold)).foregroundColor(Theme.accent)
                Panel {
                    Text(t("sign_in").uppercased()).font(.ui(22, .black))
                    Text(t("same_account")).font(.ui(12)).foregroundColor(Theme.muted)
                    SocialSignIn(email: email)
                    TextField(t("email"), text: $email)
                        .textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6)).padding(.top, 10)
                    SecureField(t("password"), text: $password)
                        .textContentType(.password)
                        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    if let e = account.error { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
                    Button {
                        Task { await account.login(email: email, password: password) }
                    } label: {
                        Text((account.busy ? t("signing_in") : t("sign_in")).uppercased()).font(.ui(17, .black)).frame(maxWidth: .infinity).padding(12)
                            .background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .disabled(account.busy || email.isEmpty || password.isEmpty)
                    .padding(.top, 6)
                    HStack {
                        Link(t("create_account"), destination: webApp).font(.ui(12))
                        Spacer()
                        Link(t("forgot"), destination: URL(string: server.absoluteString + "/account/forgot")!).font(.ui(12)).foregroundColor(Theme.muted)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(24)
        }
        .background(Theme.ink.ignoresSafeArea())
        .sheet(isPresented: $account.needCode) { CodeSheet() }
    }
}

/// "Continue with Steam" and "Continue with Discord", above the email form: the sign-in opens in the system's sign-in
/// sheet and comes back to this app. Then the authenticator's code when two-step sign-in is on, and the password once on
/// this phone (the data key comes from it). A Steam or Discord with no account yet opens the new account's form with its
/// name as the public name, linked once created.
struct SocialSignIn: View {
    @EnvironmentObject var account: Account
    let email: String
    @State private var em = ""
    @State private var pw = ""
    @State private var code = ""
    @State private var name = ""
    private static let blurple = Color(red: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255)

    var body: some View {
        let dc = account.socialProv == "discord"
        VStack(alignment: .leading, spacing: 6) {
            Button { Task { await account.socialSignIn("steam") } } label: {
                Text(t("steam_continue")).font(.ui(15, .bold)).frame(maxWidth: .infinity).padding(11)
                    .foregroundColor(Theme.fg).overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
            }
            .disabled(account.socialBusy)
            Button { Task { await account.socialSignIn("discord") } } label: {
                Text(t("discord_continue")).font(.ui(15, .bold)).frame(maxWidth: .infinity).padding(11)
                    .foregroundColor(.white).background(Self.blurple).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(account.socialBusy)
            if !account.socialNeedCode && !account.socialNeedKey && account.socialNew == nil, let e = account.socialError {
                Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad)
            }
            HStack {
                Rectangle().fill(Theme.line).frame(height: 1)
                Text(t("or")).font(.ui(11)).foregroundColor(Theme.muted)
                Rectangle().fill(Theme.line).frame(height: 1)
            }
            .padding(.vertical, 6)
        }
        .padding(.top, 10)
        .sheet(isPresented: Binding(get: { account.socialNeedCode || account.socialNeedKey }, set: { if !$0 && (account.socialNeedCode || account.socialNeedKey) { account.socialCancel() } })) {
            form(title: account.socialNeedCode ? t("two_factor") : t(dc ? "discord_sign_in" : "steam_sign_in")) {
                if account.socialNeedCode {
                    Text(t("two_factor_code")).font(.ui(12)).foregroundColor(Theme.muted)
                    TextField("123 456", text: $code).textContentType(.oneTimeCode).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                        .font(.mono(24, .semibold)).multilineTextAlignment(.center)
                        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    go(t("continue"), enabled: !code.isEmpty) { await account.socialLoginCode(code) }
                } else {
                    Text(t("steam_pw_once")).font(.ui(12)).foregroundColor(Theme.muted)
                    field(t("email"), $em)
                    SecureField(t("password"), text: $pw).textContentType(.password).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    go(account.socialBusy ? t("signing_in") : t("sign_in"), enabled: !em.isEmpty && !pw.isEmpty) { await account.socialKey(email: em, password: pw) }
                }
            }
        }
        .sheet(item: Binding(get: { account.socialNew }, set: { if $0 == nil && account.socialNew != nil { account.socialCancel() } })) { n in
            form(title: t("create_account")) {
                Text(t(dc ? "discord_no_account" : "steam_no_account")).font(.ui(12)).foregroundColor(Theme.accent)
                field(t("email"), $em)
                SecureField(t("password"), text: $pw).textContentType(.newPassword).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                Text(t("pw_short")).font(.ui(11)).foregroundColor(Theme.muted)
                TextField(t("public_name"), text: $name).autocorrectionDisabled().padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                go(t("create_account"), enabled: !em.isEmpty && pw.count >= 10 && !name.trimmingCharacters(in: .whitespaces).isEmpty) { await account.register(email: em, password: pw, name: name) }
            }
            .onAppear { name = String(n.name.prefix(32)) }
        }
        .onAppear { if em.isEmpty { em = email } }
    }

    private func field(_ label: String, _ v: Binding<String>) -> some View {
        TextField(label, text: v).textContentType(.username).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
            .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func go(_ label: String, enabled: Bool, _ run: @escaping () async -> Void) -> some View {
        Button { Task { await run() } } label: {
            Text(label.uppercased()).font(.ui(17, .black)).frame(maxWidth: .infinity).padding(12)
                .background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(account.socialBusy || !enabled)
    }

    private func form<C: View>(title: String, @ViewBuilder _ c: () -> C) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    c()
                    if let e = account.socialError { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
                }
                .padding(20)
            }
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { account.socialCancel() } } }
        }
    }
}

/// The password asked first, for what adds or removes a way into the account (linking, unlinking Steam or Discord).
struct PassAsk: ViewModifier {
    let title: String
    @Binding var ask: String          // "", "link", "unlink"
    let run: (String, String) -> Void // (what, password)
    @State private var pw = ""
    func body(content: Content) -> some View {
        content.alert(title, isPresented: Binding(get: { !ask.isEmpty }, set: { if !$0 { ask = "" } })) {
            SecureField(t("password"), text: $pw)
            Button(ask == "unlink" ? t("unlink") : t("continue"), role: ask == "unlink" ? ButtonRole.destructive : nil) {
                let p = pw, a = ask
                pw = ""
                ask = ""
                run(a, p)
            }
            Button(t("cancel"), role: .cancel) { pw = ""; ask = "" }
        }
    }
}

/// Account → Steam, beside Discord: link it (the password first, then Steam's sign-in), show it on your profile, or
/// unlink it (the password again). Once linked, Steam signs you in on every device.
struct SteamPanel: View {
    @EnvironmentObject var account: Account
    @StateObject private var steam = Loader<SteamLink>()
    @State private var ask = ""

    var body: some View {
        Panel {
            if let d = steam.data {
                if !d.linked {
                    Text(t("steam_intro")).font(.ui(12)).foregroundColor(Theme.muted)
                    Button { ask = "link" } label: {
                        Text(t("steam_link").uppercased()).font(.ui(12, .black)).padding(.horizontal, 14).padding(.vertical, 8).background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(.top, 4)
                } else {
                    HStack(spacing: 8) {
                        Text(d.persona.isEmpty ? t("steam_linked") : d.persona).font(.ui(15, .bold)).lineLimit(1)
                        Text(t("discord_linked_pill")).font(.ui(10, .bold)).lineLimit(1).foregroundColor(Theme.good)
                            .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(Theme.good.opacity(0.55), lineWidth: 1))
                    }
                    Toggle(t("steam_show"), isOn: Binding(get: { d.shown }, set: { v in act { try await account.steamShow(v) } })).font(.ui(15))
                    Button(t("unlink")) { ask = "unlink" }.font(.ui(12, .bold)).foregroundColor(Theme.bad).padding(.top, 4)
                }
            } else if steam.error == nil {
                Text(t("loading")).font(.ui(12)).foregroundColor(Theme.muted)
            }
            if let e = steam.error { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
        }
        .task { await load() }
        .modifier(PassAsk(title: t(ask == "unlink" ? "steam_unlink_ask" : "steam_link"), ask: $ask) { a, p in
            if a == "link" { act { try await account.linkStart("steam", password: p) } } else { act { try await account.socialUnlink("steam", password: p) } }
        })
    }

    private func load() async { await steam.load { try await account.steam() } }

    // a change, then the card read again (an error stays on the card)
    private func act(_ f: @escaping () async throws -> Void) {
        Task {
            do { try await f(); await load() } catch { steam.error = (error as? AppError)?.key ?? error.localizedDescription }
        }
    }
}

/// Second step of the sign-in: the authenticator code (or a recovery code).
struct CodeSheet: View {
    @EnvironmentObject var account: Account
    @State private var code = ""
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(t("two_factor_code")).font(.ui(12)).foregroundColor(Theme.muted)
                TextField("123 456", text: $code).textContentType(.oneTimeCode).keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
                    .font(.mono(24, .semibold)).multilineTextAlignment(.center)
                    .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                if let e = account.error { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
                Button {
                    Task { await account.loginCode(code) }
                } label: {
                    Text((account.busy ? t("signing_in") : t("sign_in")).uppercased()).font(.ui(17, .black)).frame(maxWidth: .infinity).padding(12)
                        .background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .disabled(account.busy || code.isEmpty)
                Spacer()
            }
            .padding(20)
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(t("two_factor"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { account.cancelCode() } } }
        }
        .presentationDetents([.medium])
    }
}

/// Two-step sign-in with an authenticator app: optional, recommended. Setup: password → link/key → first code → recovery codes once.
/// Account → Discord: link it with Discord's sign-in (the password first), show it on your profile so other drivers can
/// find you there (off until you say), or unlink it (the password again). A link the bot's /link made never signs in:
/// "Link it again" does it with Discord's sign-in.
/// Account → Delete account, as on the web: what goes and what stays, and the password again.
struct DeleteAccountPanel: View {
    @EnvironmentObject var account: Account
    @State private var pw = ""
    @State private var busy = false
    @State private var err: String?
    @State private var sure = false
    var body: some View {
        Panel {
            Text(t("delete_account")).font(.subheadline.bold()).foregroundColor(Theme.bad)
            Text(t("delete_account_txt")).font(.caption).foregroundColor(Theme.muted)
            SecureField(t("password"), text: $pw).textContentType(.password).padding(10)
                .background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8))
            if let err { Text(t(err)).font(.caption).foregroundColor(Theme.bad) }
            Button { sure = true } label: {
                Text(t("delete").uppercased()).font(.subheadline.bold()).frame(maxWidth: .infinity).padding(10)
                    .background(Theme.surface2).foregroundColor(Theme.bad).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .disabled(busy || pw.isEmpty)
        }
        .alert(t("delete_account_ask"), isPresented: $sure) {
            Button(t("delete"), role: .destructive) {
                busy = true
                Task { err = await account.deleteAccount(password: pw); busy = false; if err == nil { pw = "" } }
            }
            Button(t("cancel"), role: .cancel) {}
        }
    }
}

/// Account → Notifications: a record of yours beaten, your week on Monday and a reminder 15 minutes before each planned
/// race, on this phone only when turned on (iOS asks for the permission first). Never by email.
struct NotifyPanel: View {
    @EnvironmentObject var account: Account
    @State private var on = Notify.on
    var body: some View {
        Panel {
            Toggle(t("notify_title"), isOn: Binding(get: { on }, set: { v in
                on = v
                Task {
                    on = await Notify.setOn(v, plan: account.plannerPlan)
                    Usage.count(on ? "act:notify_on" : "act:notify_off")
                    await account.setAlertsOn(on)
                }
            }))
            .font(.ui(15, .bold)).tint(Theme.accent)
        }
    }
}

struct DiscordPanel: View {
    @EnvironmentObject var account: Account
    @StateObject private var discord = Loader<DiscordLink>()
    @State private var ask = ""

    var body: some View {
        Panel {
            if let d = discord.data {
                if !d.linked {
                    Text(t("discord_intro")).font(.ui(12)).foregroundColor(Theme.muted)
                    if d.oauth {
                        Button { ask = "link" } label: {
                            Text(t("discord_link").uppercased()).font(.ui(12, .black)).padding(.horizontal, 14).padding(.vertical, 8).background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(.top, 4)
                    } else {
                        Text(t("discord_no_oauth")).font(.ui(12)).foregroundColor(Theme.muted)
                    }
                } else {
                    HStack(spacing: 8) {
                        Text(d.handle.isEmpty ? t("discord_linked") : "@" + d.handle).font(.ui(15, .bold)).lineLimit(1)
                        Text(t("discord_linked_pill")).font(.ui(10, .bold)).lineLimit(1).foregroundColor(Theme.good)
                            .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(Theme.good.opacity(0.55), lineWidth: 1))
                    }
                    if !d.login && d.oauth {
                        Text(t("discord_relink_note")).font(.ui(12)).foregroundColor(Theme.accent)
                        Button(t("discord_relink")) { ask = "link" }.font(.ui(12, .bold)).foregroundColor(Theme.accent)
                    }
                    Toggle(t("discord_show"), isOn: Binding(get: { d.shown }, set: { v in act { try await account.discordShow(v) } })).font(.ui(15))
                    Text(t("discord_show_note")).font(.ui(12)).foregroundColor(Theme.muted)
                    Button(t("discord_unlink")) { ask = "unlink" }.font(.ui(12, .bold)).foregroundColor(Theme.bad).padding(.top, 4)
                }
            } else if discord.error == nil {
                Text(t("loading")).font(.ui(12)).foregroundColor(Theme.muted)
            }
            if let e = discord.error { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
        }
        .task { await load() }
        .modifier(PassAsk(title: t(ask == "unlink" ? "discord_unlink_ask" : "discord_link"), ask: $ask) { a, p in
            if a == "link" { act { try await account.linkStart("discord", password: p) } } else { act { try await account.socialUnlink("discord", password: p) } }
        })
    }

    private func load() async { await discord.load { try await account.discord() } }

    // a change, then the card read again (an error stays on the card)
    private func act(_ f: @escaping () async throws -> Void) {
        Task {
            do { try await f(); await load() } catch { discord.error = (error as? AppError)?.key ?? error.localizedDescription }
        }
    }
}

struct TwoFactorPanel: View {
    @EnvironmentObject var account: Account
    @State private var step = ""          // "", "pw", "scan", "codes", "off"
    @State private var pw = ""
    @State private var code = ""
    @State private var setup: Account.TwoFactorSetup?
    @State private var codes: [String] = []
    @State private var err: String?
    @State private var busy = false

    var body: some View {
        Panel {
            HStack {
                Text(t("two_factor")).font(.ui(15, .bold))
                Spacer()
                Text((account.twoFactor ? t("two_factor_on") : t("recommended")).uppercased()).font(.mono(10, .black)).foregroundColor(account.twoFactor ? Theme.good : Theme.accent)
            }
            Text(account.twoFactor ? t("two_factor_is_on", account.recoveryLeft) : t("two_factor_rec")).font(.ui(12)).foregroundColor(Theme.muted)
            if account.twoFactor {
                Button(t("turn_off").uppercased()) { pw = ""; code = ""; err = nil; step = "off" }.font(.ui(12, .bold)).foregroundColor(Theme.bad).padding(.top, 4)
            } else {
                Button { pw = ""; code = ""; err = nil; step = "pw" } label: {
                    Text(t("turn_on").uppercased()).font(.ui(12, .black)).padding(.horizontal, 14).padding(.vertical, 8).background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: Binding(get: { step != "" }, set: { if !$0 { step = "" } })) { sheet }
    }

    private func field(_ label: String, _ text: Binding<String>, secret: Bool) -> some View {
        Group {
            if secret { SecureField(label, text: text).textContentType(.password) } else { TextField(label, text: text).textContentType(.oneTimeCode).keyboardType(.numbersAndPunctuation).autocorrectionDisabled() }
        }
        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var sheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if step == "pw" {
                        Text(t("two_factor_pw")).font(.ui(12)).foregroundColor(Theme.muted)
                        field(t("password"), $pw, secret: true)
                        action(t("continue"), enabled: !pw.isEmpty) { setup = try await account.setup2fa(password: pw); step = "scan" }
                    } else if step == "scan", let st = setup {
                        Text(t("two_factor_scan")).font(.ui(12)).foregroundColor(Theme.muted)
                        Link(destination: st.url) {
                            Text(t("open_in_app").uppercased()).font(.ui(12, .black)).frame(maxWidth: .infinity).padding(12).background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        Text(t("key") + ": " + st.secret.enumerated().map { $0.offset > 0 && $0.offset % 4 == 0 ? " \($0.element)" : String($0.element) }.joined())
                            .font(.mono(12)).textSelection(.enabled)
                        field(t("code"), $code, secret: false)
                        action(t("turn_on"), enabled: code.count >= 6) { codes = try await account.enable2fa(code: code); step = "codes" }
                    } else if step == "codes" {
                        Text(t("two_factor_codes")).font(.ui(12)).foregroundColor(Theme.muted)
                        Text(codes.joined(separator: "\n")).font(.mono(15)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Button(t("copy")) { UIPasteboard.general.string = codes.joined(separator: "\n") }.foregroundColor(Theme.muted)
                            Spacer()
                            Button(t("saved_them").uppercased()) { step = "" }.font(.ui(12, .black)).padding(.horizontal, 14).padding(.vertical, 8).background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    } else if step == "off" {
                        Text(t("two_factor_off")).font(.ui(12)).foregroundColor(Theme.muted)
                        field(t("password"), $pw, secret: true)
                        field(t("code"), $code, secret: false)
                        action(t("turn_off"), enabled: !pw.isEmpty && !code.isEmpty, danger: true) { try await account.disable2fa(password: pw, code: code); step = "" }
                    }
                    if let e = err { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
                }
                .padding(20)
            }
            .background(Theme.ink.ignoresSafeArea())
            .navigationTitle(t("two_factor"))
            .toolbar { if step != "codes" { ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { step = "" } } } }
        }
        .interactiveDismissDisabled(step == "codes")
    }

    private func action(_ label: String, enabled: Bool, danger: Bool = false, _ run: @escaping () async throws -> Void) -> some View {
        Button {
            busy = true
            err = nil
            Task {
                do { try await run() } catch { err = (error as? AppError)?.key ?? error.localizedDescription }
                busy = false
            }
        } label: {
            Text(label.uppercased()).font(.ui(17, .black)).frame(maxWidth: .infinity).padding(12)
                .background(danger ? Theme.bad : Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(busy || !enabled)
    }
}

// ---------- tabs ----------

struct MainView: View {
    @State private var tab = 0
    @State private var feedback = false
    @State private var toast: String?
    var body: some View {
        // the bar sits under the tabs, never over them: every screen ends above it and scrolls to its last row
        VStack(spacing: 0) {
        TabView(selection: $tab) {
            NavigationStack { HomeView().routes() }.tag(0).toolbar(.hidden, for: .tabBar)
            NavigationStack { TracksView().routes() }.tag(1).toolbar(.hidden, for: .tabBar)
            NavigationStack { LiveView() }.tag(3).toolbar(.hidden, for: .tabBar)
            NavigationStack { CommunityView().routes() }.tag(2).toolbar(.hidden, for: .tabBar)
            NavigationStack { SettingsView() }.tag(4).toolbar(.hidden, for: .tabBar)
        }
        // the feedback button: bottom right, just above the floating tab bar, on every screen (never in demo data), with
        // the count of Support's messages not read (an admin's: the drivers' not read). It opens a small menu (Send
        // feedback, Chat with support); an admin in admin mode goes straight to the support inbox.
        .overlay(alignment: .bottomTrailing) {
            if !account.demo {
                Group {
                    if account.admin {
                        Button { Usage.count("act:feedback_button"); account.openSupport() } label: { fabLabel }
                            .buttonStyle(.plain)
                    } else {
                        Menu {
                            // (a Menu says nothing when it opens: the button counts when one of its items is chosen)
                            Button { Usage.count("act:feedback_button"); feedback = true } label: { Label(t("fb_menu_send"), systemImage: "star") }
                            Button { Usage.count("act:feedback_button"); account.openSupport() } label: {
                                Label(t("fb_menu_chat") + (account.supportUnread > 0 ? " (" + unreadText + ")" : ""), systemImage: "bubble.left")
                            }
                        } label: { fabLabel }
                    }
                }
                .accessibilityLabel(t("fb_title"))
                .padding(.trailing, 16).padding(.bottom, 10)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast).font(.ui(15, .semibold)).foregroundColor(Theme.fg).multilineTextAlignment(.center)
                    .padding(.horizontal, 16).padding(.vertical, 10).background(Theme.navBar).clipShape(Capsule())
                    .overlay(Capsule().stroke(Theme.navEdge, lineWidth: 1)).padding(.horizontal, 16).padding(.bottom, 64)
                    .transition(.opacity)
            }
        }
            bar
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .sheet(isPresented: Binding(get: { account.supportOpen != nil }, set: { if !$0 { account.supportOpen = nil; Task { await account.checkSupport() } } })) {
            SupportSheet(target: account.supportOpen ?? "").id(account.supportOpen ?? "")
        }
        .sheet(isPresented: $feedback) {
            FeedbackSheet { msg in
                feedback = false
                withAnimation { toast = msg }
                Task { try? await Task.sleep(nanoseconds: 2_500_000_000); withAnimation { if toast == msg { toast = nil } } }
            }
        }
        .onReceive(inbox.$goTab.compactMap { $0 }) { t in tab = t; inbox.goTab = nil }
        // what the drivers use: the tabs without sub-tabs (Analysis and Community count theirs)
        .onAppear { countTab(tab) }
        .onChange(of: tab) { v in countTab(v) }
        // "What do you want to see?": when the app opens, your PC is not live and you drove both games
        .sheet(isPresented: Binding(get: { account.askGame && live.pcGame == nil }, set: { if !$0 { account.askGame = false } })) { GameSheet() }
        // nothing chosen on this phone yet: the selector follows the game your PC reads live
        .onChange(of: live.pcGame) { g in if let g, !account.gameChosen, g != account.game { account.setGame(g, remember: false) } }
    }
    @EnvironmentObject private var account: Account
    @EnvironmentObject private var live: Live

    // the round feedback button with the unread count on its top-right corner
    private var fabLabel: some View {
        Image(systemName: "message").font(.system(size: 18, weight: .medium)).foregroundColor(Theme.accent)
            .frame(width: 44, height: 44).background(Theme.navBar).clipShape(Circle())
            .overlay(Circle().stroke(Theme.navEdge, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                if account.supportUnread > 0 {
                    Text(unreadText).font(.mono(10, .black)).foregroundColor(Theme.ink)
                        .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18).background(Theme.accent).clipShape(Capsule()).offset(x: 4, y: -4)
                }
            }
    }
    private var unreadText: String { account.supportUnread > 9 ? "9+" : String(account.supportUnread) }

    private func countTab(_ i: Int) {
        switch i {
        case 0: Usage.count("view:home")
        case 1: Usage.count("view:tracks")
        case 3: Usage.count("view:live")
        case 4: Usage.count("view:me")
        default: break
        }
    }

    // a floating bar over the screen: the chosen tab is a lighter pill with the amber icon
    private var bar: some View {
        HStack(spacing: 0) {
            item(0, t("home"), "house")
            item(1, t("tab_tracks"), "map")
            item(3, t("live"), "antenna.radiowaves.left.and.right")
            item(2, t("community"), "person.3")
            item(4, t("account_tab"), "person")
        }
        // Track First's bar: a floating rounded bar, the chosen tab a lighter pill with the amber icon
        .padding(5)
        .background(Theme.navBar)
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.navEdge, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
        .background(Theme.ink.ignoresSafeArea())
    }

    private func item(_ i: Int, _ label: String, _ icon: String) -> some View {
        let on = tab == i
        return Button { tab = i } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.system(size: 19, weight: .regular)).foregroundColor(on ? Theme.accent : Theme.muted)
                Text(label).font(.ui(10, on ? .medium : .regular)).lineLimit(1).minimumScaleFactor(0.8).foregroundColor(on ? Theme.fg : Theme.muted)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(on ? Theme.navOn : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 13))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
    @EnvironmentObject private var inbox: Inbox
}

/// Share your feedback, like the PC's and the web's window: optional stars, a text box, Cancel and Send, as often as
/// the driver likes.
struct FeedbackSheet: View {
    @EnvironmentObject private var account: Account
    @Environment(\.dismiss) private var dismiss
    let sent: (String) -> Void
    @State private var text = ""
    @State private var stars = 0
    @State private var busy = false
    @State private var err: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("fb_title")).font(.ui(20, .black)).foregroundColor(Theme.fg)
            Text(t("fb_text")).font(.ui(15)).foregroundColor(Theme.muted)
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { k in
                    Button { stars = stars == k ? 0 : k } label: {
                        Text("★").font(.ui(28)).foregroundColor(k <= stars ? Theme.accent : Theme.muted.opacity(0.45)).padding(4)
                    }
                    .buttonStyle(.plain)
                }
            }
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .foregroundColor(Theme.fg)
                .frame(minHeight: 120)
                .padding(6)
                .background(Theme.ink)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .onChange(of: text) { v in if v.count > 4000 { text = String(v.prefix(4000)) } }
            if let err { Text(t(err)).font(.ui(12)).foregroundColor(Theme.bad) }
            HStack(spacing: 8) {
                Spacer()
                Button(t("cancel")) { dismiss() }.foregroundColor(Theme.muted).disabled(busy)
                Button {
                    busy = true; err = nil
                    let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task {
                        do {
                            try await account.sendFeedback(msg, rating: stars > 0 ? stars : nil)
                            busy = false
                            sent(t("fb_thanks"))
                        } catch {
                            busy = false
                            err = (error as? AppError)?.key ?? "server_down"
                        }
                    }
                } label: {
                    Text(t("fb_send")).font(.ui(15, .black)).padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(busy || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }
}

/// The support chat: the driver's thread with Support (`target` ""), the support inbox of an admin in admin mode ("" too,
/// the drivers' conversations) or one driver's thread (an account id, admins). Read when opened and every 30 s.
struct SupportSheet: View {
    @EnvironmentObject private var account: Account
    let target: String
    @State private var thread: String?
    @State private var nick = ""
    var body: some View {
        let id = thread ?? (account.admin ? target : "")
        let inbox = account.admin && id.isEmpty
        let name = account.admin ? (thread == nil ? account.supportNick : nick) : ""
        NavigationStack {
            Group {
                if inbox { SupportInbox { a, n in nick = n; thread = a } }
                else { SupportThread(accountId: id, nick: name).id(id) }
            }
            .background(Theme.surface.ignoresSafeArea())
            .navigationTitle(inbox || !account.admin ? t("sup_title") : (name.isEmpty ? "—" : name))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if account.admin && !inbox {
                    ToolbarItem(placement: .cancellationAction) { Button { thread = ""; nick = "" } label: { Image(systemName: "chevron.left") } }
                }
            }
        }
        .presentationDetents([.large])
    }
}

/// The support inbox (admins): every driver who wrote, the newest first, with the last line, its time and what is unread.
struct SupportInbox: View {
    @EnvironmentObject private var account: Account
    let open: (String, String) -> Void
    @State private var convs: [SupportConv]?
    var body: some View {
        Group {
            if let list = convs {
                if list.isEmpty { VStack { Text(t("sup_none")).font(.ui(15)).foregroundColor(Theme.muted).padding(16); Spacer() } }
                else {
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(list) { c in
                                Button { open(c.accountId, c.nick) } label: {
                                    HStack(spacing: 8) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            HStack {
                                                Text(c.nick.isEmpty ? "—" : c.nick).font(.ui(15, .bold)).foregroundColor(Theme.fg).lineLimit(1)
                                                Spacer()
                                                Text(dayTime(c.created)).font(.ui(11)).foregroundColor(Theme.muted)
                                            }
                                            Text((c.fromSupport ? "↩ " : "") + c.text).font(.ui(12)).foregroundColor(c.unread > 0 ? Theme.fg : Theme.muted).lineLimit(2).multilineTextAlignment(.leading)
                                        }
                                        if c.unread > 0 {
                                            Text(c.unread > 9 ? "9+" : "\(c.unread)").font(.mono(10, .black)).foregroundColor(Theme.ink)
                                                .padding(.horizontal, 4).frame(minWidth: 18, minHeight: 18).background(Theme.accent).clipShape(Capsule())
                                        }
                                    }
                                    .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            } else { VStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }.frame(maxWidth: .infinity) }
        }
        .task {
            while !Task.isCancelled {
                if let l = try? await account.supportInbox() { convs = l }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }
}

/// One thread: the driver's messages on the right and Support's on the left ("Pitlane HQ Support", never an admin's
/// name), the newest at the bottom, then the text box and Send. An admin (`nick` the driver's) sees it the other way
/// round: the driver on the left, Support's replies on the right.
struct SupportThread: View {
    @EnvironmentObject private var account: Account
    let accountId: String
    let nick: String
    @State private var msgs: [SupportMsg]?
    @State private var text = ""
    @State private var busy = false
    @State private var err: String?
    @State private var logText: String?
    private var asAdmin: Bool { !accountId.isEmpty }
    var body: some View {
        VStack(spacing: 0) {
            if let list = msgs {
                if list.isEmpty {
                    VStack { Spacer(); if !asAdmin { Text(t("sup_empty")).font(.ui(15)).foregroundColor(Theme.muted).multilineTextAlignment(.center) }; Spacer() }.frame(maxWidth: .infinity)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(list) { m in bubble(m).id(m.id) }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 8)
                        }
                        .onAppear { if let l = list.last { proxy.scrollTo(l.id, anchor: .bottom) } }
                        .onChange(of: list.count) { _ in if let l = msgs?.last { withAnimation { proxy.scrollTo(l.id, anchor: .bottom) } } }
                    }
                }
            } else { VStack { Spacer(); ProgressView().tint(Theme.accent); Spacer() }.frame(maxWidth: .infinity) }
            if let err { Text(t(err)).font(.ui(12)).foregroundColor(Theme.bad).padding(.horizontal, 16) }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .foregroundColor(Theme.fg)
                    .padding(10)
                    .background(Theme.ink)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: text) { v in if v.count > 4000 { text = String(v.prefix(4000)) } }
                let empty = text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button { send() } label: {
                    Text(t("fb_send")).font(.ui(15, .black)).padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Theme.accent).foregroundColor(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(busy || empty)
                .opacity(busy || empty ? 0.5 : 1)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, asAdmin ? 16 : 4)
            if !asAdmin {
                Button { sendLogs() } label: { Text(t("sup_logs")).font(.ui(12)).foregroundColor(Theme.accent) }
                    .buttonStyle(.plain).disabled(busy)
                    .frame(maxWidth: .infinity, alignment: .trailing).padding(.horizontal, 16).padding(.bottom, 10)
            }
        }
        .sheet(isPresented: Binding(get: { logText != nil }, set: { if !$0 { logText = nil } })) {
            NavigationStack {
                ScrollView {
                    Text(logText ?? "").font(.mono(10)).foregroundColor(Theme.fg).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                }
                .background(Theme.ink)
                .navigationTitle(t("sup_logs_title")).navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("close")) { logText = nil }.tint(Theme.accent) }
                    ToolbarItem(placement: .confirmationAction) { Button(t("copy")) { UIPasteboard.general.string = logText }.tint(Theme.accent) }
                }
            }
        }
        .task {
            while !Task.isCancelled {
                if let l = try? await account.supportThread(accountId) { msgs = l }
                try? await Task.sleep(nanoseconds: 30_000_000_000)
            }
        }
    }

    @ViewBuilder private func bubble(_ m: SupportMsg) -> some View {
        let right = asAdmin ? !m.driver : m.driver
        VStack(alignment: right ? .trailing : .leading, spacing: 2) {
            if !right { Text(asAdmin ? (nick.isEmpty ? "—" : nick) : t("sup_name")).font(.ui(11, .bold)).foregroundColor(Theme.accent).padding(.horizontal, 4) }
            VStack(alignment: .leading, spacing: 2) {
                if (1...5).contains(m.rating) { Text(String(repeating: "★", count: m.rating) + String(repeating: "☆", count: 5 - m.rating)).font(.ui(12)).foregroundColor(Theme.accent) }
                Text(m.text).font(.ui(15)).foregroundColor(Theme.fg).textSelection(.enabled)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(right ? Theme.accent.opacity(0.16) : Theme.surface2)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(right ? Theme.accent.opacity(0.35) : Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .frame(maxWidth: UIScreen.main.bounds.width * 0.78, alignment: right ? .trailing : .leading)
            if asAdmin && m.kind == "logs" && m.view.hasPrefix("log:") {
                Button { Task { logText = (try? await account.adminLog(String(m.view.dropFirst(4)))) ?? "" } } label: {
                    Text(t("sup_logs_open")).font(.ui(12)).foregroundColor(Theme.accent)
                }.buttonStyle(.plain).padding(.horizontal, 4)
            }
            Text(dayTime(m.created)).font(.ui(10)).foregroundColor(Theme.muted).padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: right ? .trailing : .leading)
    }

    private func sendLogs() {
        busy = true; err = nil
        Task {
            do {
                try await account.sendLogs(Reports.log())
                if let l = try? await account.supportThread(accountId) { msgs = l }
            } catch { err = (error as? AppError)?.key ?? "server_down" }
            busy = false
        }
    }

    private func send() {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        busy = true; err = nil
        Task {
            do {
                try await account.supportSend(accountId, msg)
                text = ""
                if let l = try? await account.supportThread(accountId) { msgs = l }
            } catch { err = (error as? AppError)?.key ?? "server_down" }
            busy = false
        }
    }
}

/// One entry of Info: an alert (dismissable) or one of the permanent items (support, feedback).
private struct InfoItem: Identifiable {
    let id: String, icon: String, title: String, text: String
    var keep = false
    let acts: [(String, () -> Void)]
}

/// Info, in the header of every screen: the alerts that matter now (new version, app news, account to-dos) and,
/// always, how to support the app and send feedback. Alerts can be dismissed; the badge counts the new ones.
struct InfoButton: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var updates: Updates
    @EnvironmentObject var inbox: Inbox
    @State private var open = false

    private var alerts: [InfoItem] {
        var a: [InfoItem] = []
        if let v = updates.version {
            a.append(InfoItem(id: "upd:" + v, icon: "arrow.down.circle", title: t("update_title", v), text: t("update_body", Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""), acts: [
                (t("download"), { UIApplication.shared.open(updates.page) }),
                (t("whats_new"), { UIApplication.shared.open(URL(string: changelogURL + "#" + v.replacingOccurrences(of: ".", with: "") + "-beta")!) }),
            ]))
        }
        if !account.twoFactor { a.append(InfoItem(id: "2fa", icon: "lock", title: t("two_factor_rec_short"), text: t("two_factor_rec_sub"), acts: [(t("turn_on"), { inbox.goTab = 4 })])) }
        // Support answered: until the chat is opened (it opens the chat), never for an admin in admin mode
        if account.supportUnread > 0 && !account.admin {
            a.append(InfoItem(id: "support:\(account.supportUnread):" + String(account.supportLast.prefix(40)), icon: "bubble.left.and.bubble.right", title: t("sup_replied"),
                              text: account.supportLast.components(separatedBy: "\n").first ?? "", acts: [(t("open"), { account.openSupport() })]))
        }
        for n in inbox.news {
            var acts: [(String, () -> Void)] = []
            if let u = n.url { acts.append((t("open"), { UIApplication.shared.open(u) })) }
            if let v = n.view { acts.append((t("see_it"), { inbox.goTab = v == "me" ? 4 : v == "community" ? 2 : 0 })) }
            a.append(InfoItem(id: "news:" + n.id, icon: "newspaper", title: n.title, text: n.text + (n.date.isEmpty ? "" : " · " + n.date), acts: acts))
        }
        return a.filter { $0.keep || !inbox.seen.contains($0.id) }
    }

    private var always: [InfoItem] {
        var a: [InfoItem] = []
        if let u = URL(string: patreonURL), !patreonURL.isEmpty { a.append(InfoItem(id: "support", icon: "heart", title: t("support"), text: t("support_sub"), keep: true, acts: [("Patreon", { UIApplication.shared.open(u) })])) }
        a.append(InfoItem(id: "feedback", icon: "bubble.left", title: t("feedback"), text: t("feedback_sub"), keep: true, acts: [(t("send_feedback"), { if account.demo { UIApplication.shared.open(feedbackURL) } else { account.openSupport() } })]))
        return a
    }

    var body: some View {
        let list = alerts
        let fresh = list.filter { !inbox.seen.contains("seen:" + $0.id) }.count
        Button { open = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "info.circle").font(.system(size: 17)).foregroundColor(Theme.muted).frame(width: 32, height: 32)
                if fresh > 0 {
                    Text("\(fresh)").font(.mono(10, .black)).foregroundColor(Theme.ink).padding(.horizontal, 5).frame(minWidth: 16, minHeight: 16).background(Theme.accent).clipShape(Capsule()).offset(x: 4, y: -2)
                }
            }
        }
        .sheet(isPresented: $open, onDismiss: { inbox.mark(list.map { "seen:" + $0.id }) }) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(t("alerts").uppercased()).font(.mono(12, .bold)).foregroundColor(Theme.muted)
                        if list.isEmpty { Text(t("nothing_new")).font(.ui(15)).foregroundColor(Theme.muted).padding(.vertical, 10) }
                        ForEach(list) { it in row(it, dismissable: true) }
                        Text("PITLANE HQ").font(.mono(12, .bold)).foregroundColor(Theme.muted).padding(.top, 8)
                        ForEach(always) { it in row(it, dismissable: false) }
                    }
                    .padding(16)
                }
                .background(Theme.ink.ignoresSafeArea())
                .navigationTitle("Info")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { if list.contains(where: { !$0.keep }) { ToolbarItem(placement: .cancellationAction) { Button(t("clear")) { inbox.mark(list.filter { !$0.keep }.map { $0.id }) } } } }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private func row(_ it: InfoItem, dismissable: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: it.icon).foregroundColor(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(it.title).font(.ui(15, .bold)).foregroundColor(Theme.fg)
                Text(it.text).font(.ui(12)).foregroundColor(Theme.muted)
                HStack(spacing: 6) {
                    ForEach(Array(it.acts.enumerated()), id: \.offset) { i, act in
                        Button { open = false; act.1() } label: {
                            Text(act.0.uppercased()).font(.ui(11, .black)).padding(.horizontal, 12).padding(.vertical, 6)
                                .background(i == 0 ? Theme.accent : Theme.surface2).foregroundColor(i == 0 ? Theme.ink : Theme.fg).clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
            if dismissable && !it.keep { Button { inbox.mark([it.id]) } label: { Image(systemName: "xmark").font(.system(size: 12)).foregroundColor(Theme.muted) } }
        }
        .padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// ---------- Home ----------

/// Your last race on Home: where, the place, what it gave and the way to its summary.
struct LastRaceCard: View {
    let race: Race
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("last_race")).font(.ui(11, .bold)).tracking(1.3).foregroundColor(Theme.accent)
                Spacer()
                Text(day(race.when)).font(.ui(11)).foregroundColor(Theme.muted)
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.track).font(.ui(20, .black)).foregroundColor(Theme.fg).lineLimit(1)
                    Text([race.car, discName(raceDisc(race.cat, race.car))].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                    HStack(spacing: 6) { DrinksBadge(race: race); AiBadge(race: race) }
                }
                Spacer()
                Text(race.dnf ? t("dnf") : "P" + String(race.finish)).font(.ui(34, .black)).foregroundColor(placeTint)
                if !race.dnf { Text("/\(race.field)").font(.ui(14)).foregroundColor(Theme.muted).padding(.top, 12) }
            }
            HStack(spacing: 8) {
                // a race against the AI has no iRating; Le Mans Ultimate none at all, and contacts instead of incident points
                if !race.contacts { stat(t("lr_ir"), race.noIr ? "—" : signed(race.irChange), irTint) }
                stat(t("lr_best"), lapTime(race.best), Theme.purple)
                stat(race.incLabel.uppercased(), race.incText, race.inc >= 8 ? Theme.bad : Theme.fg)
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(t("see_summary")).font(.ui(13, .semibold)).foregroundColor(Theme.accent)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var irTint: Color {
        if race.noIr { return Theme.muted }
        return race.irChange > 0 ? Theme.good : race.irChange < 0 ? Theme.bad : Theme.fg
    }
    private var placeTint: Color { !race.dnf && (1...3).contains(race.finish) ? Theme.accent : Theme.fg }

    private func stat(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(l).font(.ui(10, .semibold)).tracking(1).foregroundColor(Theme.muted).lineLimit(1)
            Text(v).font(.mono(16, .bold)).foregroundColor(c).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.ink).clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// Your rated races of one discipline, oldest first (an offline race's placeholder iRating 1 is none).
func irRaces(_ races: [Race], _ k: String, _ n: Int) -> [Race] {
    Array(races.filter { !$0.noIr && $0.ir != 1 && raceDisc($0.cat, $0.car) == k }.prefix(n).reversed())
}

/// The iRating each of those races left you at: the race's own when it has one, else counted back from the newest
/// known (a race's, or the discipline's rating) with the changes in between.
func irVals(_ rs: [Race], _ now: Int?) -> [Int] {
    var cum: [Int] = []
    var a = 0
    for r in rs { a += r.irChange; cum.append(a) }
    var off = 0
    if let m = rs.lastIndex(where: { $0.ir > 1 }) { off = rs[m].ir + rs[m].irChange - cum[m] }
    else if let n = now, n > 1, let l = cum.last { off = n - l }
    var out: [Int] = []
    for (i, r) in rs.enumerated() { out.append(r.ir > 1 ? r.ir + r.irChange : cum[i] + off) }
    return out
}

/// The iRating after each race as a line that follows the finger: the point under it is picked.
struct IrLine: View {
    let vals: [Int]
    let col: Color
    var height: CGFloat
    @Binding var sel: Int?
    var area = false

    private func pt(_ i: Int, _ sz: CGSize) -> CGPoint {
        let n = max(1, vals.count - 1)
        let lo = Double(vals.min() ?? 0) - 10
        let hi = Double(vals.max() ?? 0) + 10
        let f = (Double(vals[i]) - lo) / max(1, hi - lo)
        return CGPoint(x: sz.width * CGFloat(i) / CGFloat(n), y: 4 + (sz.height - 8) * CGFloat(1 - f))
    }

    private func line(_ sz: CGSize) -> Path {
        var p = Path()
        for i in vals.indices { if i == 0 { p.move(to: pt(i, sz)) } else { p.addLine(to: pt(i, sz)) } }
        return p
    }

    private func fill(_ sz: CGSize) -> Path {
        var p = line(sz)
        p.addLine(to: CGPoint(x: sz.width, y: sz.height))
        p.addLine(to: CGPoint(x: 0, y: sz.height))
        p.closeSubpath()
        return p
    }

    var body: some View {
        GeometryReader { g in
            ZStack {
                if area { fill(g.size).fill(col.opacity(0.10)) }
                line(g.size).stroke(col, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                if let i = sel, i < vals.count { marker(pt(i, g.size), g.size.height) }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in pick(v.location.x, g.size.width) })
        }
        .frame(height: height)
    }

    private func marker(_ p: CGPoint, _ h: CGFloat) -> some View {
        ZStack {
            Path { q in q.move(to: CGPoint(x: p.x, y: 0)); q.addLine(to: CGPoint(x: p.x, y: h)) }.stroke(Theme.fg.opacity(0.5), lineWidth: 1)
            Circle().fill(Theme.ink).overlay(Circle().stroke(col, lineWidth: 2)).frame(width: 10, height: 10).position(p)
        }
    }

    private func pick(_ x: CGFloat, _ w: CGFloat) {
        let n = vals.count
        guard n > 1 else { return }
        let f = Double(x / max(1, w)) * Double(n - 1)
        sel = min(n - 1, max(0, Int(f.rounded())))
    }
}

/// My races: your iRating of one discipline over its last races, a line you read with your finger.
struct IrTrend: View {
    let races: [Race]
    var now: [String: (ir: Int, lic: String, at: Double)] = [:]
    @State private var k = ""
    @State private var sel: Int?

    private var discs: [String] { DISCS.filter { irRaces(races, $0, 2).count >= 2 } }
    private var disc: String {
        let ds = discs
        if ds.contains(k) { return k }
        if let r = races.first(where: { !$0.noIr && $0.ir != 1 }) {
            let d = raceDisc(r.cat, r.car)
            if ds.contains(d) { return d }
        }
        return ds.first ?? ""
    }

    var body: some View {
        let ds: [String] = discs
        let d: String = disc
        let rs: [Race] = irRaces(races, d, 12)
        if rs.count >= 2 {
            Panel {
                if ds.count > 1 { chips(ds, d) }
                header(rs, irVals(rs, now[d]?.ir), d)
                IrLine(vals: irVals(rs, now[d]?.ir), col: Theme.accent, height: 110, sel: $sel, area: true).padding(.top, 6)
            }
        }
    }

    private func chips(_ ds: [String], _ d: String) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(ds, id: \.self) { x in
                    Button { k = x; sel = nil } label: {
                        Text(discName(x)).font(.ui(11, .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(x == d ? Theme.accent : Theme.surface2).foregroundColor(x == d ? Theme.ink : Theme.muted).clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.bottom, 6)
    }

    @ViewBuilder private func header(_ rs: [Race], _ vals: [Int], _ d: String) -> some View {
        let i: Int = min(sel ?? (rs.count - 1), rs.count - 1)
        let x: Race = rs[i]
        let total: Int = rs.reduce(0) { $0 + $1.irChange }
        HStack {
            SectionLabel(text: t("ir_trend", discName(d).uppercased()))
            Spacer()
            Text(String(vals[i])).font(.mono(18, .bold))
            Text(signed(x.irChange)).font(.mono(12, .bold)).foregroundColor(x.irChange >= 0 ? Theme.good : Theme.bad)
        }
        if sel == nil {
            Text(t("spark_last", rs.count) + " · " + signed(total)).font(.ui(12)).foregroundColor(Theme.muted)
        } else {
            NavigationLink(value: Route.race(x)) {
                Text(raceLine(x)).font(.ui(12)).foregroundColor(Theme.accent).lineLimit(1)
            }.buttonStyle(.plain)
        }
    }

    private func raceLine(_ x: Race) -> String {
        let place: String = x.dnf ? t("dnf") : "P" + String(x.finish)
        return x.track + " · " + place + " · " + day(x.when) + "  ›"
    }
}

struct RaceRow: View {
    let race: Race
    var body: some View {
        Panel {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(race.track).font(.ui(17, .black)).foregroundColor(Theme.fg).lineLimit(1)
                    HStack(spacing: 6) { DrinksBadge(race: race); AiBadge(race: race) }
                    Text(race.car).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                    Text([day(race.when), race.official ? t("official") : t("unofficial"), race.sof > 0 ? "SOF \(race.sof)" : ""].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.ui(11)).foregroundColor(Theme.muted)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(race.dnf ? t("dnf") : "P\(race.finish)/\(race.field)").font(.mono(17, .semibold).weight(.black)).foregroundColor(race.finish == 1 ? Theme.purple : Theme.fg)
                    // a race against the AI has no iRating
                    if !race.noIr {
                        Text("iR " + signed(race.irChange)).font(.mono(12, .bold))
                            .foregroundColor(race.irChange > 0 ? Theme.good : race.irChange < 0 ? Theme.bad : Theme.muted)
                    }
                    Text(race.incText).font(.mono(11)).foregroundColor(race.inc >= 8 ? Theme.bad : Theme.muted)
                }
            }
        }
    }
}

/// DRINKS mode: a race a friend drove (any lap): "DRINKS · Ana", or "DRINKS · Multiple drivers" when several drove
/// it; tapped, who drove it, their laps and their best lap
struct DrinksBadge: View {
    let race: Race
    var names = false
    @State private var open = false
    private var who: String {
        let ds = race.drivers
        if ds.isEmpty { return race.drinks.joined(separator: "\n") }
        return ds.map { d in d.name + ": " + t("drinks_laps", d.laps, lapTime(d.best)) }.joined(separator: "\n")
    }
    var body: some View {
        if !race.drinks.isEmpty {
            let many = race.drinks.count > 1
            VStack(alignment: .leading, spacing: 4) {
                Text("DRINKS · " + (many ? t("drinks_multiple") + " ▾" : race.drinks[0]))
                    .font(.ui(10, .bold)).tracking(0.4).lineLimit(1).foregroundColor(Color(red: 1, green: 0.886, blue: 0.659))
                    .padding(.horizontal, 8).padding(.vertical, 2)
                    .background(Capsule().fill(Theme.accent.opacity(0.22))).overlay(Capsule().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                    .onTapGesture { if many { open = true } }
                if names && many { Text(t("drinks_by", race.drinks.joined(separator: ", "))).font(.ui(12)).foregroundColor(Theme.muted) }
            }
            .alert("DRINKS · " + t("drinks_who"), isPresented: $open) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(who)
            }
        }
    }
}

/// A race against iRacing's AI drivers
struct AiBadge: View {
    let race: Race
    var body: some View {
        if race.game == "lmu" { LmuPill() }
        if race.ai {
            Text(t("vs_ai")).font(.ui(10, .bold)).tracking(0.4).lineLimit(1).foregroundColor(Theme.blue)
                .padding(.horizontal, 8).padding(.vertical, 2).overlay(Capsule().stroke(Theme.blue.opacity(0.55), lineWidth: 1))
        }
    }
}

struct HomeView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject private var inbox: Inbox
    @EnvironmentObject var live: Live
    @State private var sessions: [CloudSession] = []
    /// the month's numbers as the server counts them (nil: still asked), for the game in statsGame
    @State private var stats: MonthStats?
    @State private var statsFailed = false
    @State private var statsGame = ""

    /// The sessions and the month's numbers of the chosen game, asked again whenever the account is read (the app came
    /// back, the live room's nudge) and when the game changes.
    private func reload() async {
        let gm = account.game
        if statsGame != gm { stats = nil; statsFailed = false; statsGame = gm }
        if let g = try? await account.sessions(), gm == account.game { sessions = g.data }
        do {
            let m = try await account.monthStats()
            if gm == account.game { stats = m.data; statsFailed = false }
        } catch {
            if !Task.isCancelled && gm == account.game { statsFailed = true }
        }
    }

    var body: some View {
        let races = account.races
        let hr = Calendar.current.component(.hour, from: Date())
        let hi = t(hr < 6 || hr >= 21 ? "hm_evening" : hr < 13 ? "hm_morning" : "hm_afternoon")
        // like the web and the PC: the greeting and your PC, four numbers of the month, your last race, the recent
        // sessions, the licence summary and the days you drove, each on its card
        Screen(title: account.display.isEmpty ? hi : hi + ", " + account.display, gameSeg: true) {
            HStack(spacing: 8) {
                if account.admin || (account.supporter && !account.supporterHidden) { MyBadges() }
                Text("●").font(.ui(12)).foregroundColor(live.pcOnline ? Theme.good : Theme.muted)
                Text(t(live.pcOnline ? "hm_pc_on" : "hm_pc_off")).font(.ui(12)).foregroundColor(Theme.muted)
                Spacer()
            }
            if live.pcOnline && live.simConnected {
                Button { inbox.goTab = 3 } label: {
                    Panel {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("hm_on_track")).font(.ui(17, .black)).foregroundColor(Theme.fg)
                                Text(t("hm_open_live")).font(.ui(12)).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            Text("›").font(.ui(22)).foregroundColor(Theme.muted)
                        }
                    }
                }.buttonStyle(.plain)
            }
            // the Planner, in development: admins with admin mode on, on iRacing
            if account.admin && account.game == "iracing" { PlannerCard() }
            // the server's count, the same as the PC's and the web's; what the phone has only when the server cannot say
            HomeKpis(stats: stats ?? (statsFailed ? localMonthStats(sessions: sessions, races: races) : nil), races: races)
            if let x = races.first {
                HomeLastRace(race: x)
            }
            HomeRecent(races: Array(races.dropFirst()), sessions: sessions)
            if races.isEmpty && sessions.isEmpty { EmptyNote(text: t("no_races")) }
            // Le Mans Ultimate has no iRating nor licences: its Safety Rating and Driver Rank in their place
            if account.game == "iracing" { Licences() } else if account.game == "lmu" { LmuRatings() }
            DaysDriven(races: races)
            // no sync card (the sync is automatic): only what went wrong, when something did
            if let e = account.error { Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad) }
        }
        .task(id: "\(account.game)|\(account.refreshTick)") { await reload() }
        .refreshable {
            let tick = account.refreshTick
            await account.sync()
            if account.refreshTick == tick { await reload() } // else the new read asks again by itself
        }
    }
}

/// "3 h ago", "2 days ago"
func agoText(_ ms: Double) -> String {
    let m = Int((Date().timeIntervalSince1970 * 1000 - ms) / 60000)
    if m < 60 { return t("ago_min", max(1, m)) }
    if m < 60 * 24 { return t("ago_h", m / 60) }
    if m < 60 * 48 { return t("ago_1d") }
    if m < 60 * 24 * 30 { return t("ago_d", m / 60 / 24) }
    return day(ms)
}

/// A small tag of the kind of session: Race, Qualifying, Practice, Test drive
struct KindTag: View {
    let kind: String
    var body: some View {
        let x = kind.lowercased()
        let (l, c): (String, Color) = x.contains("race") ? (t("kind_race"), Theme.accent) : x.contains("qual") ? (t("kind_qual"), Theme.purple)
            : (x.contains("test") || x.contains("offline")) ? (t("kind_test"), Theme.muted) : (t("kind_prac"), Theme.blue)
        // Track First's tag: small capitals in a thin capsule of its colour
        Text(l.uppercased()).font(.ui(10, .semibold)).tracking(0.4).foregroundColor(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 7).padding(.vertical, 1).overlay(Capsule().stroke(c, lineWidth: 1))
    }
}

/// The four numbers of the month: your laps and the hours on track, the races (and how many in the top 5) and the best
/// result, as the server counts them over every session of the account for the chosen game (nil: still asked).
struct HomeKpis: View {
    let stats: MonthStats?
    let races: [Race]
    var body: some View {
        let secs = stats?.secs ?? 0
        let h = secs / 3600
        let hTxt = secs <= 0 ? "–" : h >= 10 ? "\(Int(h.rounded())) h" : h >= 1 ? String(format: "%.1f h", h) : "\(Int((secs / 60).rounded())) min"
        // the server's best place of the month; without one, the races the phone has (this month's, else every one), like the web
        let best = stats.flatMap { $0.best ?? bestRace(self.races) }
        let n = stats?.sessions ?? 0, days = stats?.days ?? 0, races = stats?.races ?? 0
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Metric(label: t("hm_laps_month"), value: stats.map { "\($0.laps)" } ?? "–", sub: n > 0 ? t("hm_in_sessions", n) : nil)
                Metric(label: t("hm_hours_month"), value: hTxt, sub: days > 0 ? t("hm_days_driven", days) : nil)
            }
            HStack(spacing: 8) {
                Metric(label: t("hm_races_month"), value: stats.map { "\($0.races)" } ?? "–", sub: races > 0 ? t("hm_top5", stats?.top5 ?? 0) : nil)
                Metric(label: t("hm_best_result"), value: best.map { "P\($0.pos)" } ?? "–", color: Theme.accent, sub: best.map { $0.car + " · " + $0.track })
            }
        }
    }
}

/// Your last race: the place against the start, the position lap by lap, the iRating, incidents and best lap
struct HomeLastRace: View {
    let race: Race
    var body: some View {
        let x = race
        let gain = x.start > 0 && x.finish > 0 && !x.dnf ? x.start - x.finish : 0
        let pos = x.laps.map { $0.pos }.filter { $0 > 0 }
        let ir: Int? = x.noIr || x.irChange == 0 ? nil : x.irChange
        // like the web's Home and Track First: a titled card (the amber mark, when), the place out of the field, the
        // track and car with the position lap by lap, then iRating, incidents and best lap in a row, and two links
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(width: 3, height: 14)
                Text(t("hm_last_race").uppercased()).font(.display(15, .semibold)).tracking(1.7).foregroundColor(Theme.fg).lineLimit(1)
                Spacer()
                Text(agoText(x.when)).font(.ui(12)).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Rectangle().fill(Theme.line).frame(height: 1)
            NavigationLink(value: Route.race(x)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .lastTextBaseline, spacing: 0) {
                                Text(x.dnf ? t("dnf") : "P\(x.finish)").font(.mono(40, .semibold)).foregroundColor(x.dnf ? Theme.bad : Theme.fg).lineLimit(1).minimumScaleFactor(0.6)
                                Text("/\(x.field)").font(.mono(15)).foregroundColor(Theme.fg)
                            }
                            if gain != 0 { Text((gain > 0 ? "▲ " : "▼ ") + "\(abs(gain)) " + t("hm_from") + " P\(x.start)").font(.ui(12)).foregroundColor(gain > 0 ? Theme.good : Theme.bad) }
                        }
                        .frame(width: 96, alignment: .leading)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) { Text(x.track).font(.ui(15)).foregroundColor(Theme.fg).lineLimit(1); KindTag(kind: "race") }
                            HStack(spacing: 6) { DrinksBadge(race: x); AiBadge(race: x) }
                            HStack(spacing: 6) { Circle().fill(discColor(raceDisc(x.cat, x.car))).frame(width: 7, height: 7); Text(x.car).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1) }
                            if pos.count > 1 {
                                let lo = pos.min()!, hi = max(pos.max()!, lo + 1)
                                Canvas { ctx, size in
                                    var p = Path()
                                    for (k, v) in pos.enumerated() {
                                        let pt = CGPoint(x: CGFloat(k) / CGFloat(pos.count - 1) * size.width, y: 2 + CGFloat(v - lo) / CGFloat(hi - lo) * (size.height - 4))
                                        if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                                    }
                                    ctx.stroke(p, with: .color(Theme.accent), style: StrokeStyle(lineWidth: 1.6, lineJoin: .round))
                                }
                                .frame(height: 34).padding(.top, 4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack(alignment: .top, spacing: 18) {
                        // Le Mans Ultimate: no iRating, and contacts instead of incident points
                        if !x.contacts { stat(t("lr_ir"), ir.map { signed($0) } ?? "–", ir == nil ? Theme.fg : ir! > 0 ? Theme.good : Theme.bad) }
                        stat(x.incLabel, x.incText, x.inc >= 8 ? Theme.bad : Theme.fg)
                        stat(t("lr_best"), lapTime(x.best), Theme.fg)
                    }
                }
                .padding(14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 20) {
                NavigationLink(value: Route.race(x)) { Text(t("hm_race_summary")).font(.ui(13, .semibold)).foregroundColor(Theme.accent) }
                NavigationLink(value: Route.analysis(0, nil)) { Text(t("hm_analyse_laps")).font(.ui(13, .semibold)).foregroundColor(Theme.accent) }
            }
            .padding(.horizontal, 14).padding(.bottom, 14)
        }
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func stat(_ l: String, _ v: String, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(l).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
            Text(v).font(.mono(15, .semibold)).foregroundColor(c).lineLimit(1)
        }
    }
}

/// The recent sessions: the races and the other sessions (practice, qualifying, test drives) together, newest first
struct HomeRecent: View {
    let races: [Race]
    let sessions: [CloudSession]
    private enum Item { case race(Race), ses(CloudSession) }
    var body: some View {
        let items: [(Double, Item)] = (races.map { ($0.when, Item.race($0)) } + sessions.filter { !$0.kind.lowercased().contains("race") }.map { ($0.started, Item.ses($0)) })
            .sorted { $0.0 > $1.0 }.prefix(6).map { $0 }
        if !items.isEmpty {
            // a section title with See all, then the rows on the page itself, a hairline between them
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel(text: t("hm_recent"))
                    Spacer()
                    NavigationLink(value: Route.analysis(2, nil)) { Text(t("see_all")).font(.ui(12, .medium)).foregroundColor(Theme.accent) }
                }
                .padding(.top, 6).padding(.bottom, 2)
                ForEach(Array(items.enumerated()), id: \.offset) { k, e in
                    if k > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    switch e.1 {
                    case .race(let r):
                        NavigationLink(value: Route.race(r)) {
                            homeRow(r.dnf ? t("dnf") : "P\(r.finish)", r.dnf ? Theme.bad : Theme.fg, r.track, "race", raceDisc(r.cat, r.car), r.car + " · " + agoText(r.when), r.laps.count, r.best) {
                                HStack(spacing: 6) { DrinksBadge(race: r); AiBadge(race: r) }
                            }
                        }.buttonStyle(.plain)
                    case .ses(let x):
                        NavigationLink(value: Route.session(x)) {
                            homeRow(x.place, x.pos != nil ? Theme.fg : Theme.muted, fixText(x.track), x.kind, x.cat ?? "", fixText(x.car) + " · " + agoText(x.started), x.laps, x.best, x.inClass && x.pos != nil ? t("in_class") : "") { SessionBadges(x: x) }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

/// One row of the recent sessions (and of a track's sessions and races): the place, the track or car with the kind of
/// session, the car's discipline and when, the laps and the fastest lap.
func homeRow<B: View>(_ place: String, _ pc: Color, _ track: String, _ kind: String, _ disc: String, _ sub: String, _ laps: Int, _ best: Double?, _ placeSub: String = "", @ViewBuilder _ badges: () -> B) -> some View {
    // Track First's row: the place in mono, the track with its tag over the car and when, then the laps and the time
    HStack(spacing: 10) {
        // the place ("P3", a session's "P3/20"), with "class" under it when it counts within your class
        VStack(alignment: .leading, spacing: 0) {
            Text(place).font(.mono(14, .semibold)).foregroundColor(pc).lineLimit(1).minimumScaleFactor(0.6)
            if !placeSub.isEmpty { Text(placeSub).font(.ui(9)).foregroundColor(Theme.muted).lineLimit(1) }
        }
        .frame(width: 44, alignment: .leading)
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) { Text(track).font(.ui(13)).foregroundColor(Theme.fg).lineLimit(1); KindTag(kind: kind) }
            badges()
            HStack(spacing: 6) {
                Circle().fill(disc.isEmpty ? Theme.muted : discColor(disc)).frame(width: 7, height: 7)
                Text(sub).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        Text(t("laps_n", laps)).font(.mono(12, .medium)).foregroundColor(Theme.muted).lineLimit(1).fixedSize()
        Text(lapTime(best)).font(.mono(13, .semibold)).foregroundColor(Theme.fg).lineLimit(1).frame(minWidth: 64, alignment: .trailing)
    }
    .padding(.vertical, 10).contentShape(Rectangle())
}

/// The days you drove, like the web and the PC: the last 26 weeks in squares, brighter the more races and sessions that day.
/// A day opens what you drove: the race summaries and the sessions.
struct DaysDriven: View {
    let races: [Race]
    @EnvironmentObject var account: Account
    @State private var sessions: [CloudSession] = []
    @State private var open: Date?
    private let weeks = 26
    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    private func dayKey(_ ms: Double) -> Date { cal.startOfDay(for: Date(timeIntervalSince1970: ms / 1000)) }
    private var byRace: [Date: [Race]] { Dictionary(grouping: races) { dayKey($0.when) } }
    private var bySes: [Date: [CloudSession]] { Dictionary(grouping: sessions) { dayKey($0.started) } }
    private var today: Date { cal.startOfDay(for: Date()) }
    private var start: Date {
        let wd = (cal.component(.weekday, from: today) + 5) % 7 // days since Monday
        return cal.date(byAdding: .day, value: -(wd + (weeks - 1) * 7), to: today)!
    }
    private func count(_ d: Date) -> Int { (byRace[d]?.count ?? 0) + (bySes[d]?.count ?? 0) }

    var body: some View {
        let s = start, r = byRace, se = bySes
        let all: [Date] = (0..<(weeks * 7)).map { cal.date(byAdding: .day, value: $0, to: s)! }
        let mx: Int = max(1, all.map { (r[$0]?.count ?? 0) + (se[$0]?.count ?? 0) }.max() ?? 1)
        let driven: Int = all.filter { $0 <= today && ((r[$0]?.count ?? 0) + (se[$0]?.count ?? 0)) > 0 }.count
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: t("days_driven"))
                Spacer()
                Text(t("days_in_6m", driven)).font(.ui(11)).foregroundColor(Theme.muted)
            }
            Panel {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(0..<weeks, id: \.self) { w in
                            VStack(spacing: 2) {
                                ForEach(0..<7, id: \.self) { d in cell(all[w * 7 + d], mx) }
                            }
                        }
                    }
                }
            }
        }
        .task(id: "\(account.game)|\(account.refreshTick)") { if let g = try? await account.sessions() { sessions = g.data } }
        .sheet(item: Binding(get: { open.map { DayRef(day: $0) } }, set: { open = $0?.day })) { ref in
            NavigationStack {
                List {
                    ForEach(byRace[ref.day] ?? []) { x in
                        NavigationLink(value: Route.race(x)) { Text("\(x.track) · P\(x.finish)/\(x.field) · \(x.incText)").bold() }
                    }
                    ForEach(bySes[ref.day] ?? []) { x in
                        NavigationLink(value: Route.session(x)) { Text("\(kindText(x.kind)) · \(x.track) · \(x.car) · \(lapTime(x.best))") }
                    }
                }
                .navigationTitle(ref.day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                .routes()
                .toolbar { Button(t("close")) { open = nil } }
            }
        }
    }

    @ViewBuilder private func cell(_ d: Date, _ mx: Int) -> some View {
        let n = count(d)
        let a: Double = n == 0 ? 0 : [0.35, 0.6, 0.8, 1.0][max(0, min(3, Int((Double(n) / Double(mx) * 4).rounded(.up)) - 1))]
        let fill: Color = d > today ? .clear : n == 0 ? Theme.surface2 : Theme.accent.opacity(a)
        RoundedRectangle(cornerRadius: 3).fill(fill).frame(width: 11, height: 11)
            .onTapGesture { if n > 0 { open = d } }
    }
}

private struct DayRef: Identifiable { let day: Date; var id: Double { day.timeIntervalSince1970 } }

struct RaceView: View {
    let race: Race
    @EnvironmentObject var account: Account
    @State private var editing: RaceResult?
    var body: some View {
        let x = race
        let best = x.laps.filter { $0.time > 0 && !$0.cut }.map(\.time).min()
        Screen(title: x.track, sub: x.car + " · " + dayTime(x.when)) {
            if !x.drinks.isEmpty || x.ai || x.game == "lmu" { HStack(spacing: 6) { DrinksBadge(race: x, names: true); AiBadge(race: x) } }
            MetricGrid(items: ([
                MetricData(label: t("start"), value: "P\(x.start)"),
                MetricData(label: t("finish"), value: x.dnf ? t("dnf") : "P\(x.finish)", color: x.finish == 1 ? Theme.purple : Theme.fg),
                // a race against the AI has no iRating; Le Mans Ultimate none at all (nor a strength of field): the drivers and the best lap instead
                x.contacts ? MetricData(label: t("rs_drivers"), value: "\(x.field)") : x.ai ? MetricData(label: "iRating", value: "—", color: Theme.muted, sub: t("vs_ai")) : MetricData(label: "iRating", value: signed(x.irChange), color: x.irChange > 0 ? Theme.good : x.irChange < 0 ? Theme.bad : Theme.fg, sub: x.ir > 0 ? "\(x.ir) → \(x.ir + x.irChange)" : nil),
                MetricData(label: x.incLabel, value: x.incText, color: x.inc >= 8 ? Theme.bad : Theme.fg),
                MetricData(label: t("pos_gain"), value: signed(x.start - x.finish), color: x.start > x.finish ? Theme.good : x.start < x.finish ? Theme.bad : Theme.fg),
                x.contacts ? MetricData(label: t("best_lap"), value: lapTime(x.best), color: Theme.purple) : MetricData(label: t("sof"), value: x.sof > 0 ? "\(x.sof)" : "—"),
            ] as [MetricData?]).compactMap { $0 }, columns: 3)
            Panel {
                InfoRow(label: t("best_lap"), value: lapTime(x.best), color: Theme.purple)
                InfoRow(label: t("field_best"), value: lapTime(x.fieldBest))
                InfoRow(label: t("average"), value: lapTime(x.avg))
                InfoRow(label: t("consistency"), value: x.consistency.map { String(format: "±%.3f s", $0) } ?? "—")
                InfoRow(label: t("pits"), value: "\(x.pits)")
                InfoRow(label: t("fuel_used"), value: x.fuelUsed.map { String(format: "%.1f L", $0) } ?? "—")
                InfoRow(label: t("laps"), value: "\(x.laps.count) · " + t("drivers", x.field))
            }
            if !x.laps.isEmpty {
                SectionLabel(text: t("laps").uppercased())
                Panel {
                    let drk = !x.drivers.isEmpty
                    ForEach(x.laps, id: \.n) { l in
                        HStack {
                            Text("L\(l.n)").foregroundColor(Theme.muted).frame(width: 44, alignment: .leading)
                            // DRINKS mode: who drove each lap
                            if drk { Text(x.driverOf(l)).font(.ui(12)).lineLimit(1).frame(width: 78, alignment: .leading) }
                            Text(lapTime(l.time)).foregroundColor(l.cut ? Theme.muted : l.time == best ? Theme.purple : Theme.fg).strikethrough(l.cut).opacity(l.cut ? 0.6 : 1)
                            Spacer()
                            Text("P\(l.pos)").foregroundColor(Theme.muted).strikethrough(l.cut).frame(width: 44, alignment: .leading)
                            Text([l.cut ? t("invalid").lowercased() : nil, l.pit ? t("pit") : nil, l.inc > 0 ? (x.contacts ? "\(l.inc)" : "\(l.inc)x") : nil].compactMap { $0 }.joined(separator: " · "))
                                .font(.mono(11)).foregroundColor(l.pit && !l.cut ? Theme.blue : Theme.bad).frame(minWidth: 40, alignment: .leading)
                        }
                        .font(.mono(12))
                    }
                }
            }
            if !x.results.isEmpty {
                SectionLabel(text: t("results"))
                Panel {
                    Text(t("tap_driver_note")).font(.ui(11)).foregroundColor(Theme.muted)
                    ForEach(x.results, id: \.pos) { p in
                        let me = x.results.contains(where: { $0.me }) ? p.me : p.pos == x.finish
                        let note = me ? nil : account.noteFor(p.k, p.name)
                        // your note on a driver: their tag before the name; tap a driver to mark them
                        HStack {
                            Text("\(p.pos)").foregroundColor(me ? Theme.accent : Theme.muted).frame(width: 28, alignment: .leading)
                            if let n = note, !n.tag.isEmpty { TagIcon(tag: n.tag).frame(width: 14, height: 14) }
                            // your car in a DRINKS race: who drove it
                            Text((me && !x.drivers.isEmpty ? x.drivers.map { $0.name }.joined(separator: ", ") : p.name) + ((note?.note.isEmpty ?? true) ? "" : " ✎")).fontWeight(me ? .black : .regular).foregroundColor(me ? Theme.accent : Theme.fg).lineLimit(1)
                            if p.ai { Text(t("ai_driver")).font(.ui(10, .bold)).foregroundColor(Theme.blue) }
                            // laps more (red) or less (blue) than you, like the relative
                            let myLaps = x.results.first(where: { x.results.contains(where: { $0.me }) ? $0.me : $0.pos == x.finish })?.laps ?? 0
                            let dl = !me && p.laps > 0 && myLaps > 0 ? p.laps - myLaps : 0
                            if dl != 0 { Text((dl > 0 ? "+" : "−") + "\(abs(dl))L").font(.mono(10, .bold)).foregroundColor(dl > 0 ? Theme.bad : Theme.blue) }
                            Spacer()
                            Text(p.ir > 0 && !x.noIr ? "\(p.ir)" : "").foregroundColor(Theme.muted).frame(width: 44, alignment: .trailing)
                            Text(lapTime(p.best)).frame(width: 66, alignment: .trailing)
                            Text(x.contacts ? "\(p.inc)" : "\(p.inc)x").foregroundColor(Theme.muted).frame(width: 30, alignment: .trailing)
                        }
                        .font(.mono(12))
                        .contentShape(Rectangle())
                        .onTapGesture { if !me && !p.ai { editing = p } }
                    }
                }
            }
        }
        .onAppear { account.loadDriverNotes() }
        .sheet(item: $editing) { d in DriverNoteSheet(driver: d, cur: account.noteFor(d.k, d.name)) }
    }
}

// ---------- driver notes ----------

private let tagColors: [String: Color] = ["danger": Color(red: 1, green: 0x5B / 255, blue: 0x5B / 255), "careful": Color(red: 1, green: 0xB0 / 255, blue: 0x2E / 255),
                                          "clean": Color(red: 0x38 / 255, green: 0xC9 / 255, blue: 0x7C / 255), "friend": Color(red: 0x4C / 255, green: 0x9B / 255, blue: 0xFF / 255)]

/// The icon of a tag, the same as the PC's and the web's: a red triangle, an amber circle, a green tick, a blue star.
struct TagIcon: View {
    let tag: String
    var body: some View {
        Canvas { ctx, size in
            let u = size.width / 16
            guard let col = tagColors[tag] else { return }
            let ink: Color = tag == "careful" ? Color(red: 0x14 / 255, green: 0x17 / 255, blue: 0x1C / 255) : .white
            func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat) {
                var p = Path(); p.move(to: CGPoint(x: x0 * u, y: y0 * u)); p.addLine(to: CGPoint(x: x1 * u, y: y1 * u))
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.9 * u, lineCap: .round, lineJoin: .round))
            }
            func dot(_ x: CGFloat, _ y: CGFloat) { ctx.fill(Path(ellipseIn: CGRect(x: (x - 1.1) * u, y: (y - 1.1) * u, width: 2.2 * u, height: 2.2 * u)), with: .color(ink)) }
            if tag == "danger" {
                var p = Path(); p.move(to: CGPoint(x: 8 * u, y: 0.6 * u)); p.addLine(to: CGPoint(x: 15.8 * u, y: 14.6 * u)); p.addLine(to: CGPoint(x: 0.2 * u, y: 14.6 * u)); p.closeSubpath()
                ctx.fill(p, with: .color(col)); line(8, 5, 8, 9.6); dot(8, 12.1)
                return
            }
            ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: 16 * u, height: 16 * u)), with: .color(col))
            switch tag {
            case "careful": line(8, 3.8, 8, 9); dot(8, 11.7)
            case "clean":
                var p = Path(); p.move(to: CGPoint(x: 4.4 * u, y: 8.2 * u)); p.addLine(to: CGPoint(x: 7 * u, y: 10.9 * u)); p.addLine(to: CGPoint(x: 11.8 * u, y: 5.4 * u))
                ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 1.9 * u, lineCap: .round, lineJoin: .round))
            case "friend":
                var p = Path()
                for i in 0..<10 {
                    let r: CGFloat = i % 2 == 0 ? 5 : 2.1, a = -Double.pi / 2 + Double(i) * Double.pi / 5
                    let pt = CGPoint(x: (8 + r * CGFloat(cos(a))) * u, y: (8 + r * CGFloat(sin(a))) * u)
                    if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
                }
                p.closeSubpath(); ctx.fill(p, with: .color(ink))
            default: break
            }
        }
    }
}

/// Mark a driver: one tag (or none) and a note only you see.
struct DriverNoteSheet: View {
    let driver: RaceResult
    let cur: DriverNote?
    @EnvironmentObject var account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var tag = ""
    @State private var note = ""
    @State private var busy = false
    @State private var err: String?
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(["danger", "careful", "clean", "friend"], id: \.self) { tg in
                        Button { tag = tag == tg ? "" : tg } label: {
                            HStack(spacing: 10) {
                                TagIcon(tag: tg).frame(width: 18, height: 18)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("tag_" + tg)).fontWeight(.bold).foregroundColor(Theme.fg)
                                    Text(t("tag_" + tg + "_hint")).font(.ui(12)).foregroundColor(Theme.muted)
                                }
                                Spacer()
                            }
                            .padding(10)
                            .background(tag == tg ? Theme.accent.opacity(0.12) : Color.clear)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(tag == tg ? Theme.accent : Theme.line, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }
                    TextField(t("driver_note_hint"), text: $note, axis: .vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                    if let err { Text(t(err)).foregroundColor(Theme.bad).font(.ui(12)) }
                    if cur != nil { Button(t("remove"), role: .destructive) { save("", "") }.disabled(busy).padding(.top, 4) }
                }
                .padding(16)
            }
            .navigationTitle(driver.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(t("save")) { save(tag, note) }.disabled(busy) }
            }
        }
        .onAppear { tag = cur?.tag ?? ""; note = cur?.note ?? "" }
    }
    private func save(_ tg: String, _ n: String) {
        busy = true; err = nil
        Task {
            do { try await account.setDriverNote(key: driver.k, name: driver.name, tag: tg, note: n); dismiss() }
            catch { err = (error as? AppError)?.key ?? error.localizedDescription }
            busy = false
        }
    }
}

// ---------- Analysis ----------

/// Analysis, as on the PC and the web: Laps (the laps of the session you chose), Coach (its best lap against the model's
/// next level), My sessions (every session in the account, filtered like the web's "Choose a session") and My races.
struct AnalysisView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var net: NetMonitor
    @EnvironmentObject private var inbox: Inbox
    /// the tab it opens on and the session (nil: your newest)
    var startTab = 0
    var start: CloudSession? = nil
    @State private var started = false
    @StateObject private var sessions = Loader<[CloudSession]>()
    @StateObject private var bests = Loader<[PersonalBest]>()
    @StateObject private var laps = Loader<[CloudLap]>()
    @State private var tab = 0
    // the tab a session chosen in My sessions opens: Laps, or the Coach when you came from it
    @State private var pickFor = 0
    @State private var onlyBest = false
    @State private var cur: CloudSession?
    @State private var coach: LapAnalysis?
    @State private var coachKey = ""
    @State private var coachBusy = false
    @State private var coachErr: String?
    @State private var fCat = ""
    @State private var fCar = ""
    @State private var fTrack = ""
    @State private var fKind = ""
    @State private var fDay = ""
    @State private var showDays = false
    @State private var lastDemo = false
    @State private var lastGame = ""

    private func load() async {
        if tab == 3 { await account.sync(quiet: true); return }
        if tab == 2 && onlyBest { await bests.load { try await account.bests() }; return }
        await sessions.load { try await account.sessions() }
        // Laps and the Coach open on your newest session until you choose another
        if cur == nil, let s = sessions.data?.first { await open(s, go: false) }
        else if let c = cur, tab < 2 { await loadLaps(c) }
    }
    private func loadLaps(_ s: CloudSession) async {
        await laps.load { try await account.laps(s.id) }
        if tab == 1 { await loadCoach() }
    }
    private func open(_ s: CloudSession, go: Bool = true) async {
        cur = s
        laps.data = nil
        coach = nil
        coachKey = ""
        if go { tab = pickFor }
        await loadLaps(s)
    }
    /// the coach: your best lap of the session (a friend's lap in DRINKS mode is never the account's) against the next level
    private func loadCoach() async {
        guard let s = cur, let ls = laps.data else { return }
        let ok = ls.filter { $0.valid && $0.time > 0 }
        guard let best = ok.filter({ $0.drv.isEmpty }).min(by: { $0.time < $1.time }) ?? ok.min(by: { $0.time < $1.time }) else { coach = nil; coachKey = ""; return }
        let key = s.id + "|" + best.id
        if key == coachKey && (coach != nil || coachBusy) { return }
        coachKey = key
        coachBusy = true
        coachErr = nil
        do {
            let a = try await account.analyse(session: s, lap: best, all: ls, kind: .level, withLaps: true)
            if coachKey == key { coach = a }
        } catch {
            coachErr = (error as? AppError)?.key ?? error.localizedDescription
        }
        coachBusy = false
    }

    // the car and the track are two filters: with many of each, one list of every pair gets long
    // a car or a track is known by its name without accents or broken characters, so one track never shows twice
    private func trackName(_ x: CloudSession) -> String { fixText(x.track) + (x.trackConfig.isEmpty ? "" : " · " + fixText(x.trackConfig)) }
    private func trackKey(_ x: CloudSession) -> String { nameKey(trackName(x)) }
    private func carKey(_ x: CloudSession) -> String { nameKey(carFam(x.car)) }
    /// the choices of one filter: (key, name, sessions), by name
    private func group(_ l: [CloudSession], _ key: (CloudSession) -> String, _ name: (CloudSession) -> String) -> [(String, String, Int)] {
        var out: [String: (String, Int)] = [:]
        for x in l { let k = key(x); out[k] = (out[k]?.0 ?? name(x), (out[k]?.1 ?? 0) + 1) }
        return out.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1.lowercased() < $1.1.lowercased() }
    }
    /// the day of a session, as the calendar keys it ("y-m-d")
    private func dayKey(_ x: CloudSession) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: x.started / 1000))
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
    /// its discipline (iRacing) or its class (Le Mans Ultimate)
    private func catKey(_ x: CloudSession) -> String { catOf(x.game, x.cat, x.cls, x.car) }
    /// every filter but one (what that one can still choose)
    private func match(_ x: CloudSession, skip: String = "") -> Bool {
        (skip == "cat" || fCat.isEmpty || catKey(x) == fCat) && (skip == "car" || fCar.isEmpty || carKey(x) == fCar) && (skip == "track" || fTrack.isEmpty || trackKey(x) == fTrack) &&
            (skip == "kind" || fKind.isEmpty || kindOf(x.kind) == fKind) && (skip == "day" || fDay.isEmpty || dayKey(x) == fDay)
    }

    /// four small menus (discipline, kind of session, car, track) and the days you drove behind one button,
    /// like the web's "Choose a session"
    @ViewBuilder private func filters(_ all: [CloudSession], _ forCat: [CloudSession], _ forKind: [CloudSession], _ forCar: [CloudSession], _ forTrack: [CloudSession], _ forDay: [CloudSession], _ shown: Int) -> some View {
        // iRacing's disciplines, or Le Mans Ultimate's classes (no filter with one class only)
        let gm = account.game
        let cats: [(String, String, Int)] = catKeys(gm, Set(all.map { catKey($0) })).filter { k in all.contains { catKey($0) == k } }.map { k in (k, catName(gm, k), forCat.filter { catKey($0) == k }.count) }
        let kinds: [(String, String, Int)] = ["race", "qual", "prac", "test"].map { k in (k, t("filt_" + k), forKind.filter { kindOf($0.kind) == k }.count) }.filter { $0.2 > 0 || $0.0 == fKind }
        let cars = group(forCar, carKey) { carFam($0.car) }
        let tracks = group(forTrack, trackKey, trackName)
        let days: [String: Int] = forDay.reduce(into: [String: Int]()) { $0[dayKey($1), default: 0] += 1 }
        let dayLabel: String = (fDay.isEmpty ? t("days_drove") : t("days_drove") + " · " + fDay) + (showDays ? " ▴" : " ▾")
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if gm != "lmu" || !cats.isEmpty { FilterMenu(all: t(gm == "lmu" ? "class_all" : "lic_all_full"), total: forCat.count, items: cats, value: $fCat) }
                FilterMenu(all: t("kind_all"), total: forKind.count, items: kinds, value: $fKind)
            }
            HStack(spacing: 6) {
                FilterMenu(all: t("every_car"), total: forCar.count, items: cars, value: $fCar)
                FilterMenu(all: t("every_track"), total: forTrack.count, items: tracks, value: $fTrack)
            }
            HStack {
                Button(dayLabel) { showDays.toggle() }.font(.ui(12, .bold)).foregroundColor(Theme.accent)
                Spacer()
                if !(fCat + fCar + fTrack + fKind + fDay).isEmpty {
                    Button(t("clear_filters") + " · \(shown)/\(all.count)") { fCat = ""; fCar = ""; fTrack = ""; fKind = ""; fDay = "" }.font(.ui(12, .bold)).foregroundColor(Theme.accent)
                }
            }
            if showDays {
                Panel { DayGrid(days: days, selected: fDay) { k in fDay = fDay == k ? "" : k } }
            }
        }
    }

    /// Laps and the Coach: the session you chose (the newest until you choose another)
    @ViewBuilder private var lapsAndCoach: some View {
        if let s = cur {
            SessionHead(x: s) { pickFor = tab; tab = 2 }
            LoadState(loading: laps.loading, error: laps.error, stale: laps.stale) { Task { await loadLaps(s) } }
            if let ls = laps.data {
                if tab == 0 { SessionLaps(session: s, laps: ls) }
                else if !ls.contains(where: { $0.valid && $0.time > 0 }) { EmptyNote(text: t("coach_no_lap")) }
                else {
                    LoadState(loading: coachBusy, error: coachErr) { coachKey = ""; Task { await loadCoach() } }
                    if let an = coach, coachKey.hasPrefix(s.id + "|") { CoachBody(an: an) }
                }
            }
        } else {
            LoadState(loading: sessions.loading, error: sessions.error, stale: sessions.stale) { Task { await load() } }
            if sessions.data != nil { EmptyNote(text: t("no_sessions")) }
        }
    }

    /// My sessions: every session in the account, or only your fastest lap of each car and track
    @ViewBuilder private var mySessions: some View {
        HStack {
            Button { onlyBest.toggle() } label: {
                Text(t("only_fastest")).font(.ui(12, .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                    .background(onlyBest ? Theme.accent : Theme.surface2).foregroundColor(onlyBest ? Theme.ink : Theme.muted).clipShape(Capsule())
            }
            Spacer()
        }
        if onlyBest {
            LoadState(loading: bests.loading, error: bests.error, stale: bests.stale) { Task { await load() } }
            if let b = bests.data, b.isEmpty { EmptyNote(text: t("no_sessions")) }
            ForEach(bests.data ?? []) { x in
                let s = x.bestSessionId.map { CloudSession(id: $0, started: x.last, track: x.track, trackConfig: x.trackConfig, car: x.car, kind: "", laps: x.laps, best: x.best, game: x.game) }
                Button { if let s { Task { await open(s) } } } label: {
                    Panel {
                        Text(fixText(x.track) + (x.trackConfig.isEmpty ? "" : " · " + fixText(x.trackConfig))).font(.ui(17, .black)).foregroundColor(Theme.fg).lineLimit(1)
                        Text(fixText(x.car)).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                        HStack {
                            Text([day(x.last), t("laps_n", x.laps)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted)
                            Spacer()
                            Text(lapTime(x.best)).font(.mono(15, .bold)).foregroundColor(Theme.purple)
                        }
                        .padding(.top, 4)
                    }
                }
                .buttonStyle(.plain)
                .disabled(s == nil)
            }
        } else {
            LoadState(loading: sessions.loading, error: sessions.error, stale: sessions.stale) { Task { await load() } }
            // many cars, tracks and sessions make a long list: the discipline, the kind of session, the car and track,
            // a day you drove (the calendar), like the web's "Choose a session"
            let all = sessions.data ?? []
            let forCat = all.filter { match($0, skip: "cat") }, forKind = all.filter { match($0, skip: "kind") }
            let forCar = all.filter { match($0, skip: "car") }, forTrack = all.filter { match($0, skip: "track") }, forDay = all.filter { match($0, skip: "day") }
            let list = all.filter { match($0) }
            if all.count > 1 { filters(all, forCat, forKind, forCar, forTrack, forDay, list.count) }
            if sessions.data != nil && list.isEmpty { EmptyNote(text: t("no_sessions")) }
            ForEach(list) { x in
                Button { Task { await open(x) } } label: { SessionRow(x: x, on: x.id == cur?.id) }.buttonStyle(.plain)
            }
        }
    }

    var body: some View {
        Screen(title: t("analysis"), gameSeg: true) {
            Tabs(labels: [t("tab_laps"), t("tab_coach"), t("tab_my_sessions"), t("tab_my_races")], selected: $tab)
                .onAppear { Usage.count("view:" + ["laps", "coach", "cloudlaps", "races"][min(max(tab, 0), 3)]) }
                .onChange(of: tab) { v in Usage.count("view:" + ["laps", "coach", "cloudlaps", "races"][min(max(v, 0), 3)]) }
            ShortNote(key: "an_short")
            switch tab {
            case 0, 1: lapsAndCoach
            case 2: mySessions
            default:
                if account.races.isEmpty { EmptyNote(text: t("no_races")) }
                else { IrTrend(races: account.races, now: account.ratings()) }
                ForEach(account.races) { r in
                    NavigationLink(value: Route.race(r)) { RaceRow(race: r) }.buttonStyle(.plain)
                }
            }
        }
        .refreshable { await load() }
        .task(id: "\(tab)-\(onlyBest)-\(account.demo)-\(account.game)") {
            if account.demo != lastDemo || account.game != lastGame {
                lastDemo = account.demo; lastGame = account.game; fCat = ""; cur = nil; sessions.data = nil; bests.data = nil; laps.data = nil; coach = nil; coachKey = ""
            }
            if !started {
                started = true
                cur = start
                if startTab != tab { tab = startTab; return } // the task runs again for the new tab
            }
            if tab < 2 { pickFor = tab }
            if tab == 1 && laps.data != nil { await loadCoach() }
            if tab == 3 { return }
            if ((tab == 2 && onlyBest) ? bests.data == nil : sessions.data == nil) { await load() }
        }
        .onChange(of: net.cameBack) { _ in Task { await load() } }
        // the account was read again (the app came back, the live room's nudge): the session list too
        .onChange(of: account.refreshTick) { _ in if sessions.data != nil { Task { await sessions.load { try await account.sessions() } } } }
    }
}

struct SessionView: View {
    @EnvironmentObject var account: Account
    let session: CloudSession
    @StateObject private var laps = Loader<[CloudLap]>()

    var body: some View {
        Screen(title: session.track, sub: session.car) {
            ShortNote(key: "an_short")
            LoadState(loading: laps.loading, error: laps.error, stale: laps.stale) { Task { await laps.load { try await account.laps(session.id) } } }
            if !sessCat(session).isEmpty {
                HStack(spacing: 6) { Text(t("viewing", session.car, sessCat(session))).font(.ui(12)).foregroundColor(Theme.muted); LicBadge(k: session.lic); Spacer() }
            }
            SessionBadges(x: session)
            if let ls = laps.data { SessionLaps(session: session, laps: ls) }
        }
        .task { if laps.data == nil { await laps.load { try await account.laps(session.id) } } }
    }
}

/// A lap next to its lap B: the driver's own best lap of the session, or the model's next level or record.
struct LapView: View {
    @EnvironmentObject var account: Account
    let session: CloudSession
    let lap: CloudLap
    let all: [CloudLap]
    @State private var kind = RefKind.myBest
    @State private var loading = false
    @State private var error: String?
    @State private var trace: Trace?
    @State private var ref: Trace?
    @State private var refLabel = ""
    @State private var refTime: Double?
    @State private var refSectors: [Double] = []
    @State private var pick: Double?
    @State private var car: [String: Any]?
    @State private var turns: [Double] = [] // the official turn numbers of this track, when an admin placed them
    @State private var layout: ([Double], [Double])? // the community's layout, the map's road (the lap's path only without it)
    @State private var coachOff: Set<String> = [] // the kinds of tip an admin turned off for a speed of corner (coach_off)
    @State private var js: [String: JsResult]? // the web's analysis (pitwall-analysis.js), by language
    private var jsNow: JsResult? { js?[I18n.shared.lang] }

    private func load() async {
        loading = true
        error = nil
        do {
            let a = try await account.analyse(session: session, lap: lap, all: all, kind: kind)
            trace = a.trace
            ref = a.ref
            refLabel = a.refLabel
            refTime = a.refTime
            refSectors = a.refSectors
            car = a.car
            turns = a.turns
            layout = a.layout
            coachOff = a.coach?.off ?? []
            js = a.js
        } catch {
            self.error = (error as? AppError)?.key ?? error.localizedDescription
        }
        loading = false
    }

    private func speedSeries(_ c: Compared, _ refName: String) -> [Series] {
        var out = [Series(label: t("you"), values: c.speedA, color: Theme.accent)]
        if let b = c.speedB { out.append(Series(label: refName, values: b, color: Theme.blue)) }
        return out
    }

    var body: some View {
        let d = refTime.map { lap.time - $0 }
        Screen(title: t("lap_analysis") + " · L\(lap.n)", sub: session.track + " · " + session.car) {
            ShortNote(key: "an_short")
            HStack(spacing: 8) {
                Text(t("compare_with")).font(.ui(12)).foregroundColor(Theme.muted)
                Tabs(labels: [t("my_best"), "▲ " + t("next_level"), "★ " + t("record")], selected: Binding(get: { kind == .myBest ? 0 : kind == .level ? 1 : 2 }, set: { kind = $0 == 0 ? .myBest : $0 == 1 ? .level : .record }))
            }
            LoadState(loading: loading, error: error) { Task { await load() } }
            HStack(spacing: 8) {
                Metric(label: t("you"), value: lapTime(lap.time), color: Theme.accent, sub: lapFlags(trace))
                Metric(label: refLabel.isEmpty ? t("ref") : refLabel, value: lapTime(refTime), color: Theme.blue)
                Metric(label: t("delta"), value: d.map { String(format: "%+.3f", $0) } ?? "—", color: d == nil ? Theme.fg : d! <= 0 ? Theme.good : Theme.bad)
            }
            .fixedSize(horizontal: false, vertical: true)
            // every corner as a small bar under the key facts, like the web's analyzer: touch one to read it on the map and the charts
            if let trace, ref != nil {
                let cc = compare(trace, ref)
                let cs = jsNow?.corners ?? corners(cc, turns: turns)
                if !cs.isEmpty { CornerStrip(cs: cs, lapLen: Double(cc.speedA.count) * cc.step, pick: $pick) }
            }
            // the car card: what this car does on other tracks against this lap, like the web's coach
            if let car, let trace { CarCardView(card: car, trace: trace) }
            if !loading {
                if let trace {
                    let c = compare(trace, ref)
                    if ref == nil { Text(t("no_reference")).font(.ui(12)).foregroundColor(Theme.muted) }
                    let refName = refLabel.isEmpty ? t("ref") : refLabel
                    let card: (Int) -> AnyView = { i in AnyView(PointCard(c: c, i: i, refName: refName, sec: lap.sectors, refSec: refSectors)) }
                    if trace.hasShape || layout != nil { TrackMapView(c: c, trace: trace, pick: $pick, turns: turns, road: layout, cs: jsNow?.corners) }
                    Chart(title: t("speed") + " (km/h)", series: speedSeries(c, refName), step: c.step, fmt: { String(format: "%.0f", $0) },
                          pick: $pick, card: card)
                    if let delta = c.delta {
                        Chart(title: t("delta") + " (s)", series: [Series(label: t("delta"), values: delta, color: Theme.purple)], step: c.step, fmt: { String(format: "%+.3f", $0) }, zero: true,
                              pick: $pick)
                    }
                    Chart(title: t("inputs"), series: [Series(label: t("throttle"), values: c.thrA, color: Theme.good), Series(label: t("brake"), values: c.brkA, color: Theme.bad)],
                          step: c.step, fmt: { String(format: "%.0f%%", $0 * 100) }, fixedMax: 1,
                          pick: $pick)
                    if ref != nil {
                        let bcs = jsNow?.corners ?? corners(c, turns: turns, off: coachOff)
                        if !bcs.isEmpty { BrakeTable(cs: bcs, lapLen: Double(c.speedA.count) * c.step, pick: $pick) }
                        PhaseCoach(c: c, turns: turns, cs0: jsNow?.corners)
                    }
                } else if error == nil {
                    EmptyNote(text: t("no_trace"))
                }
            }
            // the web's sectors (the game's when both laps have them, else thirds of the lap from the traces), else the game's
            if let s = jsNow?.secs, !s.isEmpty { SectorTable(a: s.map { $0.0 }, b: s.map { $0.1 }) }
            else if !lap.sectors.isEmpty { SectorTable(a: lap.sectors, b: refSectors) }
        }
        .task(id: kind) { await load() }
    }
}

struct Series {
    let label: String
    let values: [Double]
    let color: Color
}

/// The track, the community's layout (else this lap's own path, only for the road's shape), coloured where you gain
/// (green) or lose (red) time against the reference, like the map in the web and the PC app. Touch
/// or drag on it to read that point: the charts follow it (`pick` is the fraction of the lap).
struct TrackMapView: View {
    let c: Compared
    let trace: Trace
    @Binding var pick: Double?
    @State private var showInc = true
    @State private var showBrk = true
    @State private var showCoach = true
    private let xs: [Double], ys: [Double]
    /// the metres between the road's points: the lap's length over the layout's points, else the trace's
    private let bin: Double
    private let brkA: [Double], brkB: [Double]
    private let rings: [Corner]
    private let minX: Double, maxX: Double, minY: Double, maxY: Double

    init(c: Compared, trace: Trace, pick: Binding<Double?>, turns: [Double] = [], road: ([Double], [Double])? = nil, cs: [Corner]? = nil) {
        self.c = c
        self.trace = trace
        self._pick = pick
        // the road is the track's layout drawn by the community (road); only when there is none, this lap's own path.
        // No lap's line is drawn on it: everything on the map sits where its lap distance puts it, the layout's points
        // spread over the lap's length (the trace's own points every trace.bin)
        let useRoad = (road?.0.count ?? 0) >= 20 && road?.0.count == road?.1.count
        let rx: [Double] = useRoad ? (road?.0 ?? []) : (trace.hasShape ? (trace.x ?? []) : [])
        let ry: [Double] = useRoad ? (road?.1 ?? []) : (trace.hasShape ? (trace.y ?? []) : [])
        xs = rx
        ys = ry
        bin = useRoad ? Double(c.speedA.count - 1) * c.step / Double(max(1, rx.count - 1)) : trace.bin
        brkA = brakePoints(c.brkA, c.step)
        brkB = brakePoints(c.brkB, c.step)
        // the coach's rings: the web's corners that cost time (Models.swift's when the phone cannot run the web's analysis)
        rings = c.delta != nil ? (cs ?? corners(c, turns: turns)).filter { $0.lost > 0.05 } : []
        minX = xs.min() ?? 0; maxX = xs.max() ?? 1; minY = ys.min() ?? 0; maxY = ys.max() ?? 1
    }

    private var n: Int { xs.count }
    private var m: Int { c.speedA.count }

    private func point(_ i: Int, _ size: CGSize) -> CGPoint {
        guard n > 1, i >= 0, i < n else { return .zero }
        let pad: Double = 18
        let k: Double = min((size.width - 2 * pad) / max(1e-6, maxX - minX), (size.height - 2 * pad) / max(1e-6, maxY - minY))
        let ox: Double = (size.width - 2 * pad - (maxX - minX) * k) / 2
        let oy: Double = (size.height - 2 * pad - (maxY - minY) * k) / 2
        return CGPoint(x: pad + (xs[i] - minX) * k + ox, y: size.height - pad - (ys[i] - minY) * k - oy)
    }


    /// The arrow beside the start/finish line: its base, its tip and the side away from the map's centre.
    private func dirGeom(_ size: CGSize) -> (b: CGPoint, t: CGPoint, ux: CGFloat, uy: CGFloat, nx: CGFloat, ny: CGFloat)? {
        guard n > 20 else { return nil }
        let p0 = point(0, size), p1 = point(max(2, n / 60), size)
        let dx = p1.x - p0.x, dy = p1.y - p0.y, m = max(1e-6, (dx * dx + dy * dy).squareRoot())
        let ux = dx / m, uy = dy / m
        var nx = -uy, ny = ux
        if (p0.x - size.width / 2) * nx + (p0.y - size.height / 2) * ny < 0 { nx = -nx; ny = -ny }
        let b = CGPoint(x: p0.x + nx * 13, y: p0.y + ny * 13)
        return (b, CGPoint(x: b.x + ux * 18, y: b.y + uy * 18), ux, uy, nx, ny)
    }

    private func dirArrow(_ size: CGSize) -> Path {
        var p = Path()
        guard let g = dirGeom(size) else { return p }
        p.move(to: g.b)
        p.addLine(to: CGPoint(x: g.t.x - g.ux * 6, y: g.t.y - g.uy * 6))
        return p
    }

    private func dirHead(_ size: CGSize) -> Path {
        var p = Path()
        guard let g = dirGeom(size) else { return p }
        p.move(to: g.t)
        p.addLine(to: CGPoint(x: g.t.x - g.ux * 6 + g.nx * 3.6, y: g.t.y - g.uy * 6 + g.ny * 3.6))
        p.addLine(to: CGPoint(x: g.t.x - g.ux * 6 - g.nx * 3.6, y: g.t.y - g.uy * 6 - g.ny * 3.6))
        p.closeSubpath()
        return p
    }

    private func path(_ from: Int, _ to: Int, _ size: CGSize, close: Bool = false) -> Path {
        var p = Path()
        for i in from...to {
            let q = point(i, size)
            if i == from { p.move(to: q) } else { p.addLine(to: q) }
        }
        if close { p.closeSubpath() }
        return p
    }

    private func pickAt(_ loc: CGPoint, _ size: CGSize) {
        var bi = 0
        var bd: Double = .greatestFiniteMagnitude
        for i in 0..<n {
            let q = point(i, size)
            let d: Double = (q.x - loc.x) * (q.x - loc.x) + (q.y - loc.y) * (q.y - loc.y)
            if d < bd { bd = d; bi = i }
        }
        if bd < 60 * 60 { pick = Double(bi) / Double(max(1, n - 1)) }
    }

    private var selected: Int? {
        guard let f = pick, m > 1 else { return nil }
        return max(0, min(m - 1, Int((f * Double(m - 1)).rounded())))
    }

    private struct Seg: Identifiable {
        let id: Int
        let from: Int
        let to: Int
        let color: Color
    }

    private var stroke: StrokeStyle { StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round) }

    /// 48 stretches of the lap, coloured where lap A gains or loses time against the reference.
    private var segments: [Seg] {
        guard let delta = c.delta, m > 2, n > 2 else { return [] }
        let segs = 48
        var vals: [Double] = []
        for j in 0..<segs {
            let a: Int = j * (m - 1) / segs
            let b: Int = (j + 1) * (m - 1) / segs
            vals.append(delta[b] - delta[a])
        }
        var mx: Double = 0.01
        for v in vals { mx = max(mx, abs(v)) }
        var out: [Seg] = []
        for j in 0..<segs {
            let v: Double = vals[j]
            if abs(v) < 0.003 { continue }
            let alpha: Double = 0.3 + 0.7 * min(1, abs(v) / mx)
            let base: Color = v > 0 ? Theme.bad : Theme.good
            out.append(Seg(id: j, from: j * (n - 1) / segs, to: (j + 1) * (n - 1) / segs, color: base.opacity(alpha)))
        }
        return out
    }

    private var selectedRow: Int? {
        guard let s = selected else { return nil }
        let i: Int = Int(((Double(s) * c.step) / bin).rounded())
        return max(0, min(n - 1, i))
    }

    var body: some View {
        Panel {
            SectionLabel(text: t("track_map").uppercased())
            GeometryReader { g in
                map(g.size)
            }
            .frame(height: 230)
            Text(readout).font(.mono(11)).foregroundColor(Theme.muted)
            // the same switches as the web and the race summary: braking, incidents, coach
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(t("map_braking"), $showBrk)
                    if !incidents.isEmpty { chip("✕ " + t("map_incidents"), $showInc) }
                    if !rings.isEmpty { chip("Coach", $showCoach) }
                }
            }
            if !incidents.isEmpty { Text(incSummary).font(.ui(12)).foregroundColor(Theme.bad) }
            if showInc, let s = selected {
                let d: Double = Double(s) * c.step
                ForEach(Array(incidents.filter { abs($0.d - d) < 60 }.enumerated()), id: \.offset) { _, e in
                    Text(incName(e.kind) + " (\(e.pts)x)").font(.mono(11)).foregroundColor(Theme.bad)
                }
            }
        }
    }

    private func map(_ size: CGSize) -> some View {
        ZStack {
            // the track as a road with some depth: its shadow, the rim and the darker asphalt inside (like the web)
            path(0, n - 1, size, close: true).stroke(Color.black.opacity(0.38), style: StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round)).offset(x: 1.5, y: 2.5)
            path(0, n - 1, size, close: true).stroke(Theme.line.opacity(0.95), style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round)).brightness(0.08)
            path(0, n - 1, size, close: true).stroke(Color(red: 0x15 / 255, green: 0x1A / 255, blue: 0x21 / 255), style: StrokeStyle(lineWidth: 7.5, lineCap: .round, lineJoin: .round))
            // the way the cars go, like iRacing's maps: an arrow beside the start/finish line, on the outside
            dirArrow(size).stroke(Theme.bad, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            dirHead(size).fill(Theme.bad)
            ForEach(segments) { s in
                path(s.from, s.to, size).stroke(s.color, style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round))
            }
            brakeMarks(size)
            incMarks(size)
            dots(size)
        }
        .contentShape(Rectangle())
        .onTapGesture { loc in pickAt(loc, size) }
        .simultaneousGesture(DragGesture(minimumDistance: 6).onChanged { v in pickAt(v.location, size) })
    }

    private var incidents: [(d: Double, pts: Int, kind: String)] { trace.incidents }

    /// An incident as the game names it, from its points: 1x off track, 2x loss of control (or a slight contact), 4x car contact.
    private func incName(_ kind: String) -> String { t(kind == "contact" ? "inc_contact" : kind == "light" ? "inc_light" : kind == "loss" ? "inc_loss" : "inc_off") }

    private func cross(_ q: CGPoint) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: q.x - 6, y: q.y - 6)); p.addLine(to: CGPoint(x: q.x + 6, y: q.y + 6))
        p.move(to: CGPoint(x: q.x + 6, y: q.y - 6)); p.addLine(to: CGPoint(x: q.x - 6, y: q.y + 6))
        return p
    }

    private func row(_ d: Double) -> Int { max(0, min(n - 1, Int((d / bin).rounded()))) }

    @ViewBuilder private func incMarks(_ size: CGSize) -> some View {
        if showInc {
            ForEach(Array(incidents.enumerated()), id: \.offset) { _, e in
                let q = point(row(e.d), size)
                cross(q).stroke(Theme.bad, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                Text("\(e.pts)x").font(.mono(9, .black)).foregroundColor(Theme.bad).position(x: q.x + 14, y: q.y - 10)
            }
        }
    }

    /// Where each lap brakes (you in the accent colour, the reference in blue) and the coach's corners.
    @ViewBuilder private func brakeMarks(_ size: CGSize) -> some View {
        if showCoach {
            ForEach(Array(rings.enumerated()), id: \.offset) { _, k in
                let q = point(row(Double(k.atM)), size)
                Circle().fill(Theme.purple.opacity(0.18)).frame(width: 28, height: 28).position(q)
                Circle().stroke(Theme.purple, lineWidth: 2.5).frame(width: 28, height: 28).position(q)
            }
        }
        if showBrk {
            ForEach(Array(brkB.enumerated()), id: \.offset) { _, d in
                Circle().fill(Theme.blue).frame(width: 10, height: 10).overlay(Circle().stroke(Theme.bg, lineWidth: 2)).position(point(row(d), size))
            }
            ForEach(Array(brkA.enumerated()), id: \.offset) { _, d in
                Circle().fill(Theme.accent).frame(width: 12, height: 12).overlay(Circle().stroke(Theme.bg, lineWidth: 2)).position(point(row(d), size))
            }
        }
    }

    private func chip(_ label: String, _ on: Binding<Bool>) -> some View {
        Button { on.wrappedValue.toggle() } label: {
            Text(label).font(.ui(11, .bold)).foregroundColor(on.wrappedValue ? Theme.bg : Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 5).background(on.wrappedValue ? Theme.accent : Theme.surface2).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var incSummary: String {
        let pts: Int = incidents.reduce(0) { $0 + $1.pts }
        var by: [String: Int] = [:]
        for e in incidents { by[incName(e.kind), default: 0] += 1 }
        let parts: [String] = by.keys.sorted().map { "\(by[$0]!) \($0.lowercased())" }
        return t("incidents_sum", incidents.count, pts) + ": " + parts.joined(separator: " · ")
    }

    /// A short line across the track at row `i` (the start/finish line, a sector cut).
    private func bar(_ i: Int, _ len: Double, _ size: CGSize) -> Path {
        let q = point(i, size), q2 = point(min(n - 1, i + 3), size)
        let tx = q2.x - q.x, ty = q2.y - q.y, tm = max(1e-3, (tx * tx + ty * ty).squareRoot()), nx = -ty / tm, ny = tx / tm
        var p = Path()
        p.move(to: CGPoint(x: q.x - nx * len, y: q.y - ny * len)); p.addLine(to: CGPoint(x: q.x + nx * len, y: q.y + ny * len))
        return p
    }

    /// Where the S1, S2, S3 label of sector `k` goes: the middle of the sector, on the inside of the track.
    private func secLabel(_ k: Int, _ size: CGSize) -> CGPoint {
        let i = max(0, min(n - 1, Int((Double(k) + 0.5) * Double(n - 1) / 3)))
        let q = point(i, size), q2 = point(min(n - 1, i + 3), size)
        let tx = q2.x - q.x, ty = q2.y - q.y, tm = max(1e-3, (tx * tx + ty * ty).squareRoot())
        var nx = -ty / tm, ny = tx / tm
        if nx * (q.x - size.width / 2) + ny * (q.y - size.height / 2) > 0 { nx = -nx; ny = -ny }
        return CGPoint(x: q.x + nx * 22, y: q.y + ny * 22)
    }

    // the sectors like the web: the start/finish line, a cut at each sector change, S1, S2, S3 in the middle of each
    @ViewBuilder private func dots(_ size: CGSize) -> some View {
        bar(0, 10, size).stroke(Theme.fg, style: StrokeStyle(lineWidth: 4, dash: [3, 3]))
        bar((n - 1) / 3, 8, size).stroke(Theme.fg.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        bar(2 * (n - 1) / 3, 8, size).stroke(Theme.fg.opacity(0.8), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
        ForEach(0..<3, id: \.self) { k in
            Text("S\(k + 1)").font(.mono(11, .black)).foregroundColor(Theme.accent).position(secLabel(k, size))
        }
        if let i = selectedRow {
            Circle().fill(Theme.fg).frame(width: 18, height: 18).position(point(i, size))
            Circle().fill(Theme.accent).frame(width: 12, height: 12).position(point(i, size))
        }
    }

    private var readout: String {
        guard let s = selected else { return c.delta != nil ? t("map_hint") : t("map_hint_a") }
        var out = "\(Int((Double(s) * c.step).rounded())) m · \(String(format: "%.0f", c.speedA[s])) km/h"
        if let b = c.speedB, s < b.count { out += " · " + t("ref") + " " + String(format: "%.0f", b[s]) }
        if let d = c.delta, s < d.count { out += String(format: " · %+.3f s", d[s]) }
        return out
    }
}

/// The coach in four phases (braking, entry, apex, exit), like the web's and Android's.
struct PhaseCoach: View {
    let c: Compared
    var turns: [Double] = []
    var cs0: [Corner]? = nil   // the web's corners (pitwall-analysis.js), else Models.swift's

    var body: some View {
        let cs = cs0 ?? corners(c, turns: turns)
        VStack(alignment: .leading, spacing: 10) {
            if cs.isEmpty { fallback } else { phases(cs) }
        }
    }

    // traces without the reference's pedals: where time goes in 250 m stretches
    @ViewBuilder private var fallback: some View {
        let ls = losses(c)
        SectionLabel(text: t("where_time"))
        if ls.isEmpty { EmptyNote(text: t("all_clean")) }
        ForEach(ls, id: \.self) { lo in
            Panel {
                HStack {
                    Text(t("at_m", lo.fromM)).font(.ui(17, .black))
                    Spacer()
                    Text(t("lost", String(format: "%.3f", lo.lost))).font(.mono(15, .bold)).foregroundColor(Theme.bad)
                }
                Text(t("min_speed", String(format: "%.0f", lo.minA), String(format: "%.0f", lo.minB))).font(.ui(12)).foregroundColor(Theme.muted)
            }
        }
    }

    private func total(_ cs: [Corner], _ k: String) -> Double { cs.reduce(0) { $0 + max(0, $1.phases[k] ?? 0) } }

    @ViewBuilder private func phases(_ cs: [Corner]) -> some View {
        let totals: [(String, Double)] = phaseKeys.map { ($0, total(cs, $0)) }
        let worst = totals.max { $0.1 < $1.1 }
        let ca = cs.reduce(0) { $0 + $1.coastA }, cb = cs.reduce(0) { $0 + $1.coastB }
        let top = Array(cs.filter { $0.tip != nil }.sorted { $0.lost > $1.lost }.prefix(5))
        SectionLabel(text: t("by_phase"))
        MetricGrid(items: totals.map { kv in MetricData(label: t("phase_" + kv.0), value: (kv.1 > 0 ? "+" : "") + String(format: "%.2f", kv.1), color: kv.1 > 0.03 ? Theme.bad : Theme.muted) }, columns: 4)
        if let w = worst, w.1 > 0.05 { Text(t("most_phase", t("phase_" + w.0).lowercased())).font(.ui(12)).foregroundColor(Theme.muted) }
        else { Text(t("no_phase")).font(.ui(12)).foregroundColor(Theme.muted) }
        Panel { InfoRow(label: t("coasting"), value: "\(Int(ca)) m · " + t("ref") + " \(Int(cb)) m", color: ca - cb > 20 ? Theme.bad : Theme.fg) }
        SectionLabel(text: t("where_time"))
        if top.isEmpty { EmptyNote(text: t("all_clean")) }
        ForEach(top, id: \.self) { k in
            Panel {
                HStack {
                    Text(t("corner_n", k.n)).font(.ui(15, .black)).foregroundColor(Theme.accent)
                    Text(t("at_m", k.atM) + " · " + t("phase_" + (k.phase ?? ""))).font(.ui(12)).foregroundColor(Theme.muted)
                    Spacer()
                    Text(String(format: "+%.2f", k.lost)).font(.mono(15, .bold)).foregroundColor(Theme.bad)
                }
                Text(tipText(k)).font(.ui(15))
                if let lt = k.lineTip { Text(fill(t(lt), k.lineArgs)).font(.ui(13)).foregroundColor(Theme.accent) }
            }
        }
    }

    private func tipText(_ k: Corner) -> String { k.text ?? fill(t(k.tip ?? ""), k.args) }
    private func fill(_ s0: String, _ args: [String]) -> String {
        var s = s0
        for (i, a) in args.enumerated() { s = s.replacingOccurrences(of: "{\(i)}", with: a) }
        return s
    }
}

/// Everything at one point of the lap, like the box that follows the mouse on the web and the PC:
/// distance and sector, speed, throttle, brake and gear of both laps, the gap there and the sector
/// times.
struct PointCard: View {
    let c: Compared
    let i: Int
    let refName: String
    let sec: [Double]
    let refSec: [Double]

    private func at(_ a: [Double]?) -> Double? {
        guard let a, i < a.count else { return nil }
        return a[i]
    }

    private func row(_ name: String, _ color: Color, _ spd: Double?, _ thr: Double?, _ brk: Double?, _ gear: Double?) -> some View {
        let vals: [String] = [
            spd.map { String(format: "%.0f", $0) } ?? "–",
            thr.map { String(format: "%.0f%%", $0 * 100) } ?? "–",
            brk.map { String(format: "%.0f%%", $0 * 100) } ?? "–",
            gear.map { String(format: "%.0f", $0) } ?? "–",
        ]
        return HStack(spacing: 4) {
            Text(name).foregroundColor(color).bold().lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<4, id: \.self) { k in
                Text(vals[k]).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .font(.mono(12))
    }

    var body: some View {
        let n: Int = c.speedA.count
        let ns: Int = max(1, min(3, sec.count))
        let s: Int = min(ns, i / max(1, n / ns) + 1)
        let d: Double? = at(c.delta)
        let a: Double? = s - 1 < sec.count ? sec[s - 1] : nil
        let b: Double? = s - 1 < refSec.count ? refSec[s - 1] : nil
        let heads: [String] = ["km/h", t("throttle"), t("brake"), t("gear")]
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("\(Int((Double(i) * c.step).rounded())) m · S\(s)").font(.mono(13, .black))
                Spacer()
                if let d {
                    Text(String(format: "%+.3f s", d)).font(.mono(13, .bold)).foregroundColor(d <= 0 ? Theme.good : Theme.bad)
                }
            }
            HStack(spacing: 4) {
                Text(" ").frame(maxWidth: .infinity)
                ForEach(0..<4, id: \.self) { k in
                    Text(heads[k]).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .font(.ui(10)).foregroundColor(Theme.muted)
            row(t("you"), Theme.accent, at(c.speedA), at(c.thrA), at(c.brkA), at(c.gearA))
            if c.speedB != nil {
                row(refName, Theme.blue, at(c.speedB), at(c.thrB), at(c.brkB), at(c.gearB))
            }
            if let a {
                HStack {
                    Text("S\(s)").foregroundColor(Theme.muted)
                    Text(String(format: "%.3f", a) + (b.map { " · " + String(format: "%.3f", $0) } ?? ""))
                    Spacer()
                    if let b {
                        Text(String(format: "%+.3f", a - b)).bold().foregroundColor(a <= b ? Theme.good : Theme.bad)
                    }
                }
                .font(.mono(12))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .leading)
        .background(Theme.surface2)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Practice, qualifying or race, from iRacing's session type.
func kindText(_ k: String) -> String {
    let x = k.lowercased()
    if x.contains("race") { return t("kind_race") }
    if x.contains("qual") { return t("kind_qual") }
    if x.contains("warm") { return t("kind_warm") }
    if x.contains("practice") || x.contains("test") || x.contains("offline") { return t("kind_prac") }
    return k
}

/// A line chart over the lap distance. Tap, or touch and hold and drag, to read the values at
/// that point, like hovering in the web and PC app. The charts of a lap share the point ([pick],
/// a fraction of the lap); the first one shows [card], everything at that point, the others the line
/// and their values.
struct Chart: View {
    let title: String
    let series: [Series]
    let step: Double
    let fmt: (Double) -> String
    var zero = false
    var fixedMax: Double? = nil
    var pick: Binding<Double?>? = nil
    var card: ((Int) -> AnyView)? = nil
    @State private var own: Double?

    private var count: Int { series.map { $0.values.count }.max() ?? 0 }

    private var frac: Double? { pick != nil ? pick!.wrappedValue : own }

    private func set(_ x: CGFloat, _ width: CGFloat) {
        let f: Double = Double(max(0, min(1, x / max(1, width))))
        if let pick { pick.wrappedValue = f } else { own = f }
    }

    private func index(_ width: CGFloat) -> Int? {
        guard let f = frac, count > 1 else { return nil }
        return max(0, min(count - 1, Int((f * Double(count - 1)).rounded())))
    }

    var body: some View {
        let all: [Double] = series.flatMap { $0.values }.filter { $0.isFinite }
        let mn: Double = all.min() ?? 0
        let mx: Double = all.max() ?? 1
        let lo: Double = fixedMax != nil ? 0 : (zero ? min(mn, 0) : mn)
        let hi: Double = fixedMax ?? (zero ? max(mx, 0) : mx)
        let span: Double = hi - lo > 1e-9 ? hi - lo : 1
        Panel {
            SectionLabel(text: title.uppercased())
            if let card {
                // its place is kept before you touch, so the chart does not move under your finger
                if let i = index(1) {
                    card(i)
                } else {
                    Text(t("hold_hint")).font(.ui(12)).foregroundColor(Theme.muted)
                        .frame(maxWidth: .infinity, minHeight: 108)
                        .background(Theme.surface2)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            GeometryReader { g in
                let w: Double = Double(g.size.width)
                let h: Double = Double(g.size.height)
                let idx = index(g.size.width)
                VStack(alignment: .leading, spacing: 4) {
                    if card == nil || idx == nil { readout(idx).frame(height: 14) }
                    ZStack(alignment: .topLeading) {
                        if zero {
                            Path { p in
                                let y: Double = (h - 18) * (1 - (0 - lo) / span)
                                p.move(to: CGPoint(x: 0, y: y))
                                p.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(Theme.line, lineWidth: 1)
                        }
                        ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                            line(s.values, w, h - 18, lo, span).stroke(s.color, lineWidth: 1.5)
                        }
                        if let idx {
                            let x: Double = w * Double(idx) / Double(max(1, count - 1))
                            Path { p in
                                p.move(to: CGPoint(x: x, y: 0))
                                p.addLine(to: CGPoint(x: x, y: h - 18))
                            }
                            .stroke(Theme.fg.opacity(0.6), lineWidth: 1)
                            ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                                if idx < s.values.count {
                                    let y: Double = (h - 18) * (1 - (s.values[idx] - lo) / span)
                                    Circle().fill(s.color).frame(width: 7, height: 7).position(x: x, y: y)
                                }
                            }
                        }
                    }
                    .contentShape(Rectangle())
                    // at once: a tap picks the point, sliding sideways follows it (up and down still scrolls)
                    .onTapGesture { location in set(location.x, g.size.width) }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 6)
                            .onChanged { v in
                                let dx: CGFloat = abs(v.translation.width)
                                let dy: CGFloat = abs(v.translation.height)
                                if dx > dy { set(v.location.x, g.size.width) }
                            }
                    )
                }
            }
            .frame(height: 150)
            HStack {
                Text(fixedMax == 1 ? "0%" : fmt(lo))
                Spacer()
                Text(String(format: "%.1f km", Double(max(0, count - 1)) * step / 1000))
                Spacer()
                Text(fixedMax == 1 ? "100%" : fmt(hi))
            }
            .font(.ui(10)).foregroundColor(Theme.muted)
        }
    }

    // the values under the finger
    @ViewBuilder private func readout(_ idx: Int?) -> some View {
        if let idx {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Text("\(Int((Double(idx) * step).rounded())) m").foregroundColor(Theme.muted)
                    ForEach(Array(series.enumerated()), id: \.offset) { _, s in
                        if idx < s.values.count { Text(s.label + " " + fmt(s.values[idx])).foregroundColor(s.color).bold() }
                    }
                }
                .font(.mono(11))
            }
        } else {
            Text(" ").font(.ui(11))
        }
    }

    private func line(_ v: [Double], _ w: Double, _ h: Double, _ lo: Double, _ span: Double) -> Path {
        Path { p in
            guard v.count > 1 else { return }
            let last: Double = Double(v.count - 1)
            for i in 0..<v.count {
                let px: Double = w * Double(i) / last
                let py: Double = h * (1 - (v[i] - lo) / span)
                if i == 0 { p.move(to: CGPoint(x: px, y: py)) } else { p.addLine(to: CGPoint(x: px, y: py)) }
            }
        }
    }
}

// ---------- Community ----------

// the disciplines iRacing splits its licenses into, and the license classes, like on the web
let DISCS = ["oval", "sports_car", "formula_car", "dirt_oval", "dirt_road"]
/// The disciplines' symbols as SVG path data (24 × 24), the same strokes as the web's DISC_IC.
/// SVG path data ("M8.5 6h7a6 6 0 0 1 6 6…", as the web's symbols are written) as a SwiftUI Path: M/m, L/l, H/h, V/v,
/// C/c, S/s, Q/q, T/t, A/a and Z/z, with repeated coordinates after one command; nil when the data is not understood.
func svgPath(_ d: String) -> Path? {
    var path = Path()
    var i = d.startIndex
    let end = d.endIndex
    var cmd: Character = " "
    var cur = CGPoint.zero, start = CGPoint.zero, lastCtl: CGPoint? = nil, lastCmd: Character = " "
    func skip() { while i < end, d[i] == " " || d[i] == "," || d[i] == "\n" || d[i] == "\t" { i = d.index(after: i) } }
    func number() -> CGFloat? {
        skip()
        var j = i, seenDot = false, seenE = false, s = ""
        while j < end {
            let c = d[j]
            if c.isNumber { s.append(c) }
            else if c == "." && !seenDot && !seenE { seenDot = true; s.append(c) }
            else if (c == "-" || c == "+") && (j == i || (seenE && (d[d.index(before: j)] == "e" || d[d.index(before: j)] == "E"))) { s.append(c) }
            else if (c == "e" || c == "E") && !seenE && !s.isEmpty { seenE = true; s.append(c) }
            else { break }
            j = d.index(after: j)
        }
        guard let v = Double(s) else { return nil }
        i = j
        return CGFloat(v)
    }
    func flag() -> Bool? {
        skip()
        guard i < end, d[i] == "0" || d[i] == "1" else { return nil }
        let f = d[i] == "1"; i = d.index(after: i); return f
    }
    // an SVG arc (endpoint form) as cubic curves, each a quarter turn at most
    func arc(to p: CGPoint, rx rx0: CGFloat, ry ry0: CGFloat, rot: CGFloat, large: Bool, sweep: Bool) {
        if cur == p { return }
        var rx = abs(rx0), ry = abs(ry0)
        if rx == 0 || ry == 0 { path.addLine(to: p); return }
        let phi = rot * CGFloat.pi / 180, cp = cos(phi), sp = sin(phi)
        let dx2 = (cur.x - p.x) / 2, dy2 = (cur.y - p.y) / 2
        let x1 = cp * dx2 + sp * dy2, y1 = -sp * dx2 + cp * dy2
        let lam = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
        if lam > 1 { rx *= sqrt(lam); ry *= sqrt(lam) }
        let num = max(0, rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1)
        let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coef = den == 0 ? 0 : sqrt(num / den)
        if large == sweep { coef = -coef }
        let cx1 = coef * rx * y1 / ry, cy1 = -coef * ry * x1 / rx
        let cx = cp * cx1 - sp * cy1 + (cur.x + p.x) / 2, cy = sp * cx1 + cp * cy1 + (cur.y + p.y) / 2
        func ang(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let dot = ux * vx + uy * vy, len = sqrt((ux * ux + uy * uy) * (vx * vx + vy * vy))
            var a = acos(max(-1, min(1, dot / max(len, 1e-12))))
            if ux * vy - uy * vx < 0 { a = -a }
            return a
        }
        let t1 = ang(1, 0, (x1 - cx1) / rx, (y1 - cy1) / ry)
        var dt = ang((x1 - cx1) / rx, (y1 - cy1) / ry, (-x1 - cx1) / rx, (-y1 - cy1) / ry)
        if !sweep && dt > 0 { dt -= 2 * CGFloat.pi } else if sweep && dt < 0 { dt += 2 * CGFloat.pi }
        let n = max(1, Int(ceil(abs(dt) / (CGFloat.pi / 2))))
        let step = dt / CGFloat(n), k = (4.0 / 3.0) * tan(step / 4)
        var t = t1
        for _ in 0..<n {
            let t2 = t + step
            let e1 = CGPoint(x: cos(t), y: sin(t)), e2 = CGPoint(x: cos(t2), y: sin(t2))
            func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: cp * rx * x - sp * ry * y + cx, y: sp * rx * x + cp * ry * y + cy) }
            let c1 = pt(e1.x - k * e1.y, e1.y + k * e1.x), c2 = pt(e2.x + k * e2.y, e2.y - k * e2.x), q = pt(e2.x, e2.y)
            path.addCurve(to: q, control1: c1, control2: c2)
            t = t2
        }
        path.addLine(to: p) // lands exactly on the end point
    }
    while true {
        skip()
        guard i < end else { break }
        let before = i
        let c = d[i]
        if c.isLetter { cmd = c; i = d.index(after: i) }
        else if cmd == "M" { cmd = "L" } else if cmd == "m" { cmd = "l" } // numbers after a move are lines
        let rel = cmd.isLowercase
        func abs2(_ x: CGFloat, _ y: CGFloat) -> CGPoint { rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y) }
        switch cmd.uppercased() {
        case "M":
            guard let x = number(), let y = number() else { return nil }
            cur = abs2(x, y); start = cur; path.move(to: cur); lastCtl = nil
        case "L":
            guard let x = number(), let y = number() else { return nil }
            cur = abs2(x, y); path.addLine(to: cur); lastCtl = nil
        case "H":
            guard let x = number() else { return nil }
            cur = CGPoint(x: rel ? cur.x + x : x, y: cur.y); path.addLine(to: cur); lastCtl = nil
        case "V":
            guard let y = number() else { return nil }
            cur = CGPoint(x: cur.x, y: rel ? cur.y + y : y); path.addLine(to: cur); lastCtl = nil
        case "C":
            guard let x1 = number(), let y1 = number(), let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return nil }
            let c1 = abs2(x1, y1), c2 = abs2(x2, y2), p = abs2(x, y)
            path.addCurve(to: p, control1: c1, control2: c2); lastCtl = c2; cur = p
        case "S":
            guard let x2 = number(), let y2 = number(), let x = number(), let y = number() else { return nil }
            let c1 = (lastCmd.uppercased() == "C" || lastCmd.uppercased() == "S") && lastCtl != nil ? CGPoint(x: 2 * cur.x - lastCtl!.x, y: 2 * cur.y - lastCtl!.y) : cur
            let c2 = abs2(x2, y2), p = abs2(x, y)
            path.addCurve(to: p, control1: c1, control2: c2); lastCtl = c2; cur = p
        case "Q":
            guard let x1 = number(), let y1 = number(), let x = number(), let y = number() else { return nil }
            let c1 = abs2(x1, y1), p = abs2(x, y)
            path.addQuadCurve(to: p, control: c1); lastCtl = c1; cur = p
        case "T":
            guard let x = number(), let y = number() else { return nil }
            let c1 = (lastCmd.uppercased() == "Q" || lastCmd.uppercased() == "T") && lastCtl != nil ? CGPoint(x: 2 * cur.x - lastCtl!.x, y: 2 * cur.y - lastCtl!.y) : cur
            let p = abs2(x, y)
            path.addQuadCurve(to: p, control: c1); lastCtl = c1; cur = p
        case "A":
            guard let rx = number(), let ry = number(), let rot = number(), let large = flag(), let sweep = flag(), let x = number(), let y = number() else { return nil }
            let p = abs2(x, y)
            arc(to: p, rx: rx, ry: ry, rot: rot, large: large, sweep: sweep); cur = p; lastCtl = nil
        case "Z":
            path.closeSubpath(); cur = start; lastCtl = nil
        default:
            return nil
        }
        lastCmd = cmd
        if i == before { return nil } // nothing read: data that is not understood, never a loop
    }
    return path
}

let DISC_PATHS: [String: String] = [
    "oval": "M8.5 6h7a6 6 0 0 1 6 6a6 6 0 0 1-6 6h-7a6 6 0 0 1-6-6a6 6 0 0 1 6-6zM9.5 10h5a2 2 0 0 1 2 2a2 2 0 0 1-2 2h-5a2 2 0 0 1-2-2a2 2 0 0 1 2-2zM12 6v4",
    "sports_car": "M3 15.5v-2.2l2.6-.9 3-3h5.6l3.4 3 2.4.6v2.5H3zM9.3 16a1.8 1.8 0 1 1-3.6 0a1.8 1.8 0 1 1 3.6 0zM18.3 16a1.8 1.8 0 1 1-3.6 0a1.8 1.8 0 1 1 3.6 0zM9.6 9.4l-.6 3h6l-1.2-3",
    "formula_car": "M8 4h8M7 20h10M12 4v16M11.2 9.5h1.6a1.2 1.2 0 0 1 1.2 1.2v2.6a1.2 1.2 0 0 1-1.2 1.2h-1.6a1.2 1.2 0 0 1-1.2-1.2v-2.6a1.2 1.2 0 0 1 1.2-1.2zM5.5 6h1a1 1 0 0 1 1 1v2.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM17.5 6h1a1 1 0 0 1 1 1v2.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM5.5 13.5h1a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-2.5a1 1 0 0 1 1-1zM17.5 13.5h1a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-2.5a1 1 0 0 1 1-1z",
    "dirt_oval": "M7.5 6.5h4a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5h-4A5.5 5.5 0 0 1 2 12a5.5 5.5 0 0 1 5.5-5.5zM7.5 10.5h4a1.5 1.5 0 0 1 1.5 1.5a1.5 1.5 0 0 1-1.5 1.5h-4A1.5 1.5 0 0 1 6 12a1.5 1.5 0 0 1 1.5-1.5zM19.5 8.5h.01M21.5 11.5h.01M19.8 14.5h.01M21.6 17h.01",
    "dirt_road": "M2 15l5-6 3.5 4L14 8.5 22 15M9 21c1.5-2 4.5-2.5 5-5M4 21h.01M18 21h.01M20.5 19h.01",
]
/// The kind of a session for the filter: race, qual(ifying), prac(tice) or test (drive).
func kindOf(_ k: String) -> String {
    let x = k.lowercased()
    return x.contains("race") ? "race" : x.contains("qual") ? "qual" : x.contains("test") ? "test" : (x.contains("prac") || x.contains("warm") || x.contains("offline")) ? "prac" : ""
}
let LICS = ["R", "D", "C", "B", "A", "P"]
func discName(_ k: String?) -> String { k.map { DISCS.contains($0) ? t("disc_" + $0) : "" } ?? "" }
/// The category of a session, a leaderboard or a record in its game: iRacing's discipline, or Le Mans Ultimate's
/// class (Hypercar, LMP2, LMP3, LMGT3, GTE: the server's, else from the car's name).
func catOf(_ game: String, _ cat: String?, _ cls: String?, _ car: String) -> String { game == "lmu" ? lmuClass(cls, car) : (cat ?? "") }
/// Its name: the discipline's in the app's language, or the class itself (a proper name).
func catName(_ game: String, _ k: String?) -> String { game == "lmu" ? (k ?? "") : discName(k) }
/// The categories a filter offers: every discipline, or the classes of Le Mans Ultimate the list has (none with one only).
func catKeys(_ game: String, _ have: Set<String>) -> [String] {
    if game != "lmu" { return DISCS }
    let k = (LMU_CLASSES + have.filter { !$0.isEmpty && !LMU_CLASSES.contains($0) }.sorted()).filter { have.contains($0) }
    return k.count > 1 ? k : []
}
/// A class's colour (Le Mans Ultimate), else the discipline's.
func catColor(_ game: String, _ k: String) -> Color {
    if game != "lmu" { return discColor(k) }
    switch k {
    case "Hypercar": return Color(red: 1, green: 0x63 / 255, blue: 0x63 / 255)
    case "LMP2": return Color(red: 0.35, green: 0.66, blue: 1)
    case "LMP3": return Color(red: 0.73, green: 0.55, blue: 1)
    case "LMGT3": return Color(red: 0x38 / 255, green: 0xC9 / 255, blue: 0x7C / 255)
    case "GTE": return Color(red: 1, green: 0.69, blue: 0.18)
    default: return Theme.muted
    }
}
/// A session's place for its line: "P3/20", "P3/8 class" within your class, or "–" without one.
func placeLine(_ x: CloudSession) -> String { x.place + (x.inClass && x.pos != nil ? " " + t("in_class") : "") }
/// A session's category as its name: the discipline, or its Le Mans Ultimate class.
func sessCat(_ x: CloudSession) -> String { catName(x.game, catOf(x.game, x.cat, x.cls, x.car)) }
private func licColor(_ k: String) -> Color {
    switch k {
    case "R": return Color(red: 1, green: 0x63 / 255, blue: 0x63 / 255)
    case "D": return Color(red: 1, green: 0x8F / 255, blue: 0x45 / 255)
    case "C": return Color(red: 0xF2 / 255, green: 0xC9 / 255, blue: 0x4C / 255)
    case "B": return Color(red: 0x38 / 255, green: 0xC9 / 255, blue: 0x7C / 255)
    case "A": return Color(red: 0x5C / 255, green: 0x9D / 255, blue: 1)
    default: return Color(red: 0xC9 / 255, green: 0xD1 / 255, blue: 0xDC / 255)
    }
}

/// The license class as a small coloured square (R, D, C, B, A, Pro).
struct LicBadge: View {
    let k: String?
    var sr: String? = nil  // the safety rating too ("B 3.21"), when known
    var body: some View {
        if let k, LICS.contains(k) {
            // Track First's chip: the class and safety rating in mono, in the licence's colour on a faint wash of it
            Text((k == "P" ? "Pro" : k) + (sr.map { " " + $0 } ?? "")).font(.mono(11, .bold)).foregroundColor(licColor(k)).lineLimit(1).fixedSize()
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(licColor(k).opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}

/// Your badges, wherever your name shows: Admin, and Supporter unless you hid it.
struct MyBadges: View {
    @EnvironmentObject var account: Account
    var body: some View {
        HStack(spacing: 6) {
            if account.admin { StatusPill(text: "ADMIN", color: Theme.accent) }
            if account.supporter && !account.supporterHidden { SupBadge() }
        }
    }
}

/// What a lap was driven in (the server's wet bits: 1 rain, 2 a wet track, 4 a damp one): small badges beside its time.
struct WetBadges: View {
    let w: Int
    var body: some View {
        if w & 7 != 0 {
            HStack(spacing: 4) {
                if w & 1 != 0 { badge("☂ " + t("badge_rain"), Color(red: 0xB9 / 255, green: 0xD9 / 255, blue: 1), 0.13) }
                if w & 2 != 0 { badge("💧 " + t("badge_wet"), Theme.blue, 0.2) }
                else if w & 4 != 0 { badge("💧 " + t("badge_damp"), Color(red: 0x9F / 255, green: 0xB4 / 255, blue: 0xCC / 255), 0.09) }
            }
        }
    }
    private func badge(_ label: String, _ fg: Color, _ bg: Double) -> some View {
        Text(label).font(.ui(9, .bold)).foregroundColor(fg).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color(red: 0x4F / 255, green: 0x9C / 255, blue: 1).opacity(bg)).clipShape(Capsule())
    }
}

/// The game a record or a leaderboard is of: a small "iRacing" or "LMU" badge.
struct GameBadge: View {
    let game: String
    var body: some View {
        let lmu = game == "lmu"
        let c = lmu ? Color(red: 0x7F / 255, green: 0xD3 / 255, blue: 0xC4 / 255) : Color(red: 0xB9 / 255, green: 0xC4 / 255, blue: 0xD2 / 255)
        Text(lmu ? "LMU" : "iRacing").font(.ui(9, .bold)).foregroundColor(c).lineLimit(1).fixedSize()
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(c.opacity(0.5), lineWidth: 1))
    }
}

/// A driver's country flag before their name, nothing when the country is unknown.
struct CountryFlag: View {
    let cc: String
    var size: CGFloat = 12
    var body: some View {
        let f = countryFlag(cc)
        if !f.isEmpty { Text(f).font(.ui(size)).lineLimit(1).fixedSize() }
    }
}

/// A small clock after the name of a car with a penalty or a slowdown to serve.
struct PenaltyClock: View {
    var size: CGFloat = 12
    var body: some View {
        Image(systemName: "clock.fill").font(.system(size: size - 1)).foregroundColor(Theme.accent).accessibilityLabel(t("penalty_to_serve"))
    }
}

/// The supporter badge: people who donate, given by hand by the owner of Pitlane HQ.
struct SupBadge: View {
    var body: some View {
        Text("♥ SUPPORTER").font(.ui(9, .black)).foregroundColor(Color(red: 1, green: 0.84, blue: 0.9)).padding(.horizontal, 6).padding(.vertical, 1)
            .background(Color(red: 0.91, green: 0.24, blue: 0.55).opacity(0.33)).overlay(Capsule().stroke(Color(red: 0.91, green: 0.24, blue: 0.55).opacity(0.65), lineWidth: 1)).clipShape(Capsule())
    }
}

/// A row of small filters that scrolls sideways.
/// One small filter menu: "Every car (5)" and, when opened, each choice with how many sessions it has.
struct FilterMenu: View {
    let all: String
    let total: Int
    let items: [(String, String, Int)] // value, name, sessions
    @Binding var value: String
    private var label: String {
        if let c = items.first(where: { $0.0 == value }) { return "\(c.1) (\(c.2))" }
        return "\(all) (\(total))"
    }
    var body: some View {
        Menu {
            Button("\(all) (\(total))") { value = "" }
            ForEach(items, id: \.0) { it in Button("\(it.1) (\(it.2))") { value = it.0 } }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(.ui(13)).lineLimit(1).foregroundColor(value.isEmpty ? Theme.fg : Theme.accent)
                Spacer(minLength: 0)
                Text("▾").font(.ui(11)).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(value.isEmpty ? Theme.line : Theme.accent, lineWidth: 1))
        }
    }
}

struct Pills: View {
    let items: [(String, String)] // value, label
    @Binding var selected: String
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.0) { it in
                    Button { selected = selected == it.0 && !it.0.isEmpty ? "" : it.0 } label: {
                        Text(it.1).font(.ui(12, .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                            .background(selected == it.0 ? Theme.accent : Theme.surface2).foregroundColor(selected == it.0 ? Theme.ink : Theme.muted).clipShape(Capsule())
                    }
                }
            }
        }
    }
}

// ---------- Leagues: the hub ----------
/// The league hub (Community → Leagues), the web's on the phone: every league is a post with its disciplines (or
/// Mixed), the days it races on a week strip, the usual start in its zone and in yours, its next race, whether it is
/// looking for drivers, the cars, the language and who posted it. Opening a post counts a view and its Discord or
/// website a click, once per driver and day: only the creator sees them, with the last 14 days. The server opens the
/// hub to everyone with LEAGUES_OPEN=1; until then it answers "in development" and everyone but the admins reads
/// that we are working on it.
struct LeagueHub: View {
    @EnvironmentObject var account: Account
    @State private var list: [League]?
    @State private var err: String?
    @State private var tab = 0
    @State private var cat = ""
    @State private var day = -1
    @State private var onlyOpen = false
    @State private var sortNext = true
    @State private var q = ""
    @State private var openId: String?
    @State private var edit: League?

    private func load() async {
        do { list = try await account.leagues(); err = nil }
        catch { err = (error as? AppError)?.key ?? error.localizedDescription; list = list ?? [] }
    }
    private var closed: Bool { err == "leagues are in development" }
    /// Le Mans Ultimate's leagues have no disciplines: no filter by them
    private var lmu: Bool { account.game == "lmu" }
    private var shown: [League] {
        let all = list ?? []
        var l = tab == 2 ? all.filter { $0.mine } : all.filter { x in
            (lmu || cat.isEmpty || leagueDiscs(x).contains(cat)) && (day < 0 || x.days.contains(day)) && (!onlyOpen || x.open)
                && (q.isEmpty || [x.name, x.about, x.cars, x.lang, x.by].contains { $0.localizedCaseInsensitiveContains(q) })
        }
        if tab == 0 && sortNext {
            l.sort { a, b in
                let na = leagueNext(a), nb = leagueNext(b)
                if (na == nil) != (nb == nil) { return na != nil }
                if let na, let nb, na != nb { return na < nb }
                return a.updated > b.updated
            }
        } else {
            l.sort { $0.created > $1.created }
        }
        return l
    }
    private var opened: Binding<League?> {
        Binding(get: { openId.flatMap { id in (list ?? []).first { $0.id == id } } }, set: { openId = $0?.id })
    }

    var body: some View {
        let all = list ?? []
        VStack(alignment: .leading, spacing: 10) {
            if closed {
                Panel {
                    HStack { Text(t("leagues")).font(.ui(17, .black)).foregroundColor(Theme.fg); Spacer(); StatusPill(text: t("in_development"), color: Theme.accent) }
                    Text(closed ? t("leagues_wip") : t("leagues_admin_hub")).font(.ui(15)).foregroundColor(Theme.muted).padding(.top, 4)
                }
            }
            if !closed {
                Text(t("leagues_hub_sub")).font(.ui(12)).foregroundColor(Theme.muted)
                Tabs(labels: [t("leagues_explore"), edit != nil ? t("leagues_edit") : t("leagues_post"), t("leagues_mine")], selected: $tab)
                if let err { Text(t(err)).font(.ui(12)).foregroundColor(Theme.bad) }
                if tab == 1 {
                    LeagueForm(edit: edit, mine: (list ?? []).filter { $0.mine }.count) { edit = nil; tab = 2; Task { await load() } }
                } else {
                    if tab == 0 {
                        if !lmu { Pills(items: [("", t("disc_all") + " (\(all.count))")] + DISCS.map { k in (k, discName(k) + " (\(all.filter { leagueDiscs($0).contains(k) }.count))") }, selected: $cat) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                TogglePill(text: t("league_any_day"), on: day < 0) { day = -1 }
                                ForEach(0..<7, id: \.self) { d in TogglePill(text: t("wd_\(d)"), on: day == d) { day = day == d ? -1 : d } }
                            }
                        }
                        HStack(spacing: 6) {
                            TogglePill(text: t("league_open"), on: onlyOpen) { onlyOpen.toggle() }
                            Spacer()
                            TogglePill(text: t("league_sort_next"), on: sortNext) { sortNext = true }
                            TogglePill(text: t("league_sort_new"), on: !sortNext) { sortNext = false }
                        }
                        TextField(t("league_search"), text: $q).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    if list != nil && shown.isEmpty { EmptyNote(text: t(tab == 2 ? "leagues_none_mine" : "leagues_none")) }
                    ForEach(shown) { x in LeagueCard(x: x).onTapGesture { openId = x.id } }
                    if tab == 2 && !shown.isEmpty { Text(t("league_stats_note")).font(.ui(11)).foregroundColor(Theme.muted) }
                }
            }
        }
        .task { if list == nil { await load() } }
        // each game has its own leagues
        .onChange(of: account.game) { _ in list = nil; openId = nil; edit = nil; if tab == 1 { tab = 0 }; Task { await load() } }
        .onChange(of: tab) { v in if v != 1 { edit = nil } }
        .sheet(item: opened) { x in
            LeagueDetail(x: x, onEdit: { edit = x; tab = 1; openId = nil }, onChanged: { openId = nil; Task { await load() } })
        }
    }
}

/// A small filter you switch on and off.
struct TogglePill: View {
    let text: String
    let on: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(text).font(.ui(12, .bold)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.accent : Theme.surface2).foregroundColor(on ? Theme.ink : Theme.muted).clipShape(Capsule())
        }
    }
}

/// The days it races as a week strip, the raced ones lit.
struct WeekStrip: View {
    let days: [Int]
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<7, id: \.self) { d in
                let on = days.contains(d)
                Text(String(t("wd_\(d)").prefix(2))).font(.mono(9, .bold)).foregroundColor(on ? Theme.ink : Theme.muted)
                    .frame(width: 22, height: 20).background(on ? Theme.accent : Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 5))
            }
        }
    }
}

/// "20:30 CEST · 18:30 your time", or just the time; nil without one.
func leagueTimeText(_ x: League) -> String? {
    if x.time.isEmpty { return nil }
    guard let next = leagueNext(x), let tz = TimeZone(identifier: x.tz.isEmpty ? "UTC" : x.tz) else { return x.time }
    let f = DateFormatter()
    f.timeZone = tz
    f.dateFormat = "zzz"
    var s = x.time + " " + f.string(from: next)
    let l = DateFormatter()
    l.dateFormat = "HH:mm"
    let lt = l.string(from: next)
    if lt != x.time { s += " · " + t("league_your_time", lt) }
    return s
}

/// "Next: Thu 21:00 · in 2 d 3 h" in your time (true within a day), or "Racing now"; nil without a schedule.
func leagueNextText(_ x: League) -> (String, Bool)? {
    guard let next = leagueNext(x) else { return nil }
    let dt = next.timeIntervalSinceNow
    if dt <= 0 { return (t("league_now"), true) }
    let h = Int((dt / 3600).rounded()), d = h / 24, hs = h % 24
    let ins = d > 0 ? "\(d) d" + (hs > 0 ? " \(hs) h" : "") : h > 0 ? "\(h) h" : "\(max(1, Int((dt / 60).rounded()))) min"
    let f = DateFormatter()
    f.dateFormat = "EEE HH:mm"
    return (t("league_next") + ": " + f.string(from: next) + " · " + t("league_in", ins), dt < 86400)
}

/// One post in the hub; a tap opens it.
struct LeagueCard: View {
    let x: League
    var body: some View {
        // a Le Mans Ultimate league has no disciplines: the game's name instead
        let lmu = x.game == "lmu"
        let cs: [String] = lmu ? [] : leagueDiscs(x)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(cs, id: \.self) { DiscIcon(k: $0, size: 26) }
                VStack(alignment: .leading, spacing: 2) {
                    Text(x.name).font(.ui(17, .black)).foregroundColor(Theme.fg)
                    Text([lmu ? gameName(x.game) : cs.count > 1 ? t("league_mixed") : "", x.lang, t("by_name", x.by)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            if x.open { StatusPill(text: t("league_open"), color: Theme.good) }
            HStack(spacing: 8) {
                WeekStrip(days: x.days)
                Text(leagueTimeText(x) ?? t("league_no_schedule")).font(.mono(12)).foregroundColor(Theme.muted)
            }
            if let n = leagueNextText(x) { Text(n.0).font(.mono(12, .bold)).foregroundColor(n.1 ? Theme.good : Theme.muted) }
            if !x.about.isEmpty { Text(x.about).font(.ui(15)).foregroundColor(Theme.fg).lineLimit(3) }
            if !x.cars.isEmpty { Text("🏁 " + x.cars).font(.ui(12)).foregroundColor(Theme.muted) }
            if x.views >= 0 { Text("👁 \(x.views) · ↗ \(x.clicks)").font(.mono(12, .bold)).foregroundColor(Theme.muted) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(x.open ? Theme.good.opacity(0.5) : Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
    }
}

/// A post opened: everything it says, its links (each counts a click), the link to share; the creator's numbers with
/// the last 14 days, edit and remove. Opening it counts a view.
struct LeagueDetail: View {
    @EnvironmentObject var account: Account
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    let x: League
    let onEdit: () -> Void
    let onChanged: () -> Void
    @State private var days: [LeagueDay]?
    @State private var copied = false
    var body: some View {
        let lmu = x.game == "lmu"
        let cs: [String] = lmu ? [] : leagueDiscs(x)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Group {
                        HStack(spacing: 6) {
                            ForEach(cs, id: \.self) { DiscIcon(k: $0, size: 24) }
                            Text([lmu ? gameName(x.game) : cs.map { discName($0) }.joined(separator: " + "), x.lang, t("by_name", x.by)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted)
                        }
                        if x.open { StatusPill(text: t("league_open"), color: Theme.good) }
                        HStack(spacing: 8) {
                            WeekStrip(days: x.days)
                            Text(leagueTimeText(x) ?? t("league_no_schedule")).font(.mono(12)).foregroundColor(Theme.muted)
                        }
                        if let n = leagueNextText(x) { Text(n.0).font(.mono(12, .bold)).foregroundColor(n.1 ? Theme.good : Theme.muted) }
                        if !x.about.isEmpty { Text(x.about).font(.ui(15)).foregroundColor(Theme.fg) }
                        if !x.cars.isEmpty { Text("🏁 " + x.cars).font(.ui(12)).foregroundColor(Theme.muted) }
                    }
                    HStack(spacing: 10) {
                        if let u = URL(string: x.discord), !x.discord.isEmpty { Button(t("join_discord")) { account.leagueHit(x.id, "discord", mine: x.mine); openURL(u) }.buttonStyle(.borderedProminent).tint(Theme.accent) }
                        if let u = URL(string: x.web), !x.web.isEmpty { Button(t("league_site")) { account.leagueHit(x.id, "web", mine: x.mine); openURL(u) }.foregroundColor(Theme.accent) }
                    }
                    Button(copied ? t("league_link_copied") : t("league_copy_link")) { UIPasteboard.general.string = "https://pitlanehq.app/app?league=" + x.id; copied = true }
                        .font(.ui(12, .bold)).foregroundColor(Theme.accent)
                    if x.views >= 0 {
                        SectionLabel(text: t("league_your_numbers"))
                        Text("👁 \(x.views) \(t("league_views")) · ↗ \(x.clicks) \(t("league_clicks"))").font(.mono(15, .bold)).foregroundColor(Theme.fg)
                        LeagueBars(days: days)
                        Text(t("league_last14")).font(.ui(11)).foregroundColor(Theme.muted)
                    }
                    if x.mine || account.admin {
                        HStack(spacing: 14) {
                            Button(t("edit")) { onEdit() }.foregroundColor(Theme.accent)
                            Button(t("remove")) { Task { try? await account.deleteLeague(x.id); onChanged() } }.foregroundColor(Theme.bad)
                        }
                        .font(.ui(12, .bold))
                    }
                }
                .padding(16)
            }
            .background(Theme.bg)
            .navigationTitle(x.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button(t("close")) { dismiss() } }
        }
        .task { account.leagueHit(x.id, "view", mine: x.mine); if x.views >= 0 { days = (try? await account.leagueDays(x.id)) ?? [] } }
    }
}

/// The creator's last 14 days: views (amber) and clicks (blue) per day.
struct LeagueBars: View {
    let days: [LeagueDay]?
    private var rows: [(String, Int, Int)] {
        let by = Dictionary((days ?? []).map { ($0.day, $0) }, uniquingKeysWith: { a, _ in a })
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return (0..<14).reversed().map { i -> (String, Int, Int) in
            let k = f.string(from: Date().addingTimeInterval(-Double(i) * 86400))
            return (k, by[k]?.views ?? 0, by[k]?.clicks ?? 0)
        }
    }
    var body: some View {
        let r = rows
        let mx = max(1, r.map { max($0.1, $0.2) }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(r.enumerated()), id: \.offset) { _, d in
                HStack(alignment: .bottom, spacing: 1) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.accent).frame(height: max(2, 56 * CGFloat(d.1) / CGFloat(mx)))
                    RoundedRectangle(cornerRadius: 2).fill(Theme.blue).frame(height: max(2, 56 * CGFloat(d.2) / CGFloat(mx)))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 56)
    }
}

/// Post a league, or edit yours: the days it races, the usual start (this phone's time zone), its disciplines, an
/// optional Discord invite and website (one at least), the cars, the language, whether it is looking for drivers.
struct LeagueForm: View {
    @EnvironmentObject var account: Account
    let edit: League?
    var mine = 0
    let onDone: () -> Void
    @State private var name = ""
    @State private var about = ""
    @State private var discord = ""
    @State private var web = ""
    @State private var cars = ""
    @State private var lang = ""
    @State private var time = ""
    @State private var cats: [String] = []
    @State private var days: [Int] = []
    @State private var open = true
    @State private var err: String?
    @State private var busy = false
    private var tz: String { edit.flatMap { $0.tz.isEmpty ? nil : $0.tz } ?? TimeZone.current.identifier }
    /// the game the league races in: the one shown (an edited post keeps its own); Le Mans Ultimate has no disciplines
    private var gm: String { edit?.game ?? account.game }
    private func field(_ label: String, _ v: Binding<String>) -> some View {
        TextField(label, text: v).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
    }
    private func save() {
        let n = name.trimmingCharacters(in: .whitespaces), d = discord.trimmingCharacters(in: .whitespaces), w = web.trimmingCharacters(in: .whitespaces), tm = time.trimmingCharacters(in: .whitespaces)
        if n.count < 3 { err = "league_need_name"; return }
        if !d.isEmpty && d.range(of: "^https://(discord\\.gg|(www\\.)?discord\\.com/invite)/[A-Za-z0-9-]{2,40}/?$", options: .regularExpression) == nil { err = "league_need_discord"; return }
        if !w.isEmpty && w.range(of: "^https://[^\\s\"'<>]{4,190}$", options: .regularExpression) == nil { err = "league_need_web"; return }
        if d.isEmpty && w.isEmpty { err = "league_need_link"; return }
        if !tm.isEmpty && tm.range(of: "^([01]\\d|2[0-3]):[0-5]\\d$", options: .regularExpression) == nil { err = "league_bad_time"; return }
        let l = League(id: edit?.id ?? "", name: n, about: about, cat: nil, discord: d, web: w, schedule: "", cars: cars, lang: lang, cats: gm == "lmu" ? ["sports_car"] : cats, days: days, time: tm, tz: tz, open: open, game: gm)
        busy = true
        Task {
            do { try await account.saveLeague(edit?.id, l); busy = false; err = nil; onDone() }
            catch { busy = false; err = (error as? AppError)?.key ?? error.localizedDescription }
        }
    }
    /// how many leagues you may post (3, 10 as a supporter) and a small way to become one
    @ViewBuilder private var limitNote: some View {
        let lim = account.leagueLimit, used = t("league_used", mine, lim.limit)
        if lim.supporter {
            HStack(spacing: 6) { Text(used).font(.ui(11)).foregroundColor(Theme.muted); Text("♥ Supporter").font(.ui(11, .bold)).foregroundColor(Color(red: 1, green: 0.56, blue: 0.75)) }
        } else {
            Text(used + ". " + t("league_more", lim.supporterLimit)).font(.ui(11)).foregroundColor(Theme.muted)
            if let u = URL(string: patreonURL), !patreonURL.isEmpty {
                Button("♥ " + t("league_donate")) { UIApplication.shared.open(u) }.font(.ui(12, .bold)).foregroundColor(Theme.accent).buttonStyle(.plain)
            }
        }
    }
    var body: some View {
        Panel {
            Group {
                field(t("league_name"), $name)
                if gm != "lmu" {
                    Text(t("league_discs")).font(.ui(11)).foregroundColor(Theme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(DISCS, id: \.self) { k in TogglePill(text: discName(k), on: cats.contains(k)) { if let i = cats.firstIndex(of: k) { cats.remove(at: i) } else { cats.append(k) } } }
                        }
                    }
                }
                Text(t("league_days")).font(.ui(11)).foregroundColor(Theme.muted)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { d in TogglePill(text: t("wd_\(d)"), on: days.contains(d)) { if let i = days.firstIndex(of: d) { days.remove(at: i) } else { days.append(d); days.sort() } } }
                    }
                }
                HStack(spacing: 8) {
                    field(t("league_time") + " (20:30)", $time)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("league_tz")).font(.ui(11)).foregroundColor(Theme.muted)
                        Text(tz.replacingOccurrences(of: "_", with: " ")).font(.ui(12)).foregroundColor(Theme.fg)
                    }
                }
            }
            Group {
                field(t("league_discord"), $discord)
                field(t("league_web"), $web)
                Text(t("league_need_link_note")).font(.ui(11)).foregroundColor(Theme.muted)
                field(t("league_cars"), $cars)
                field(t("league_lang"), $lang)
                Toggle(t("league_open_f"), isOn: $open).font(.ui(15)).tint(Theme.accent)
                field(t("league_about"), $about)
            }
            if let err { Text(t(err)).font(.ui(12)).foregroundColor(Theme.bad) }
            Button(edit != nil ? t("save") : t("league_publish")) { save() }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(busy)
            Text(t("league_note")).font(.ui(11)).foregroundColor(Theme.muted)
            limitNote
        }
        .onAppear {
            if let e = edit { name = e.name; about = e.about; discord = e.discord; web = e.web; cars = e.cars; lang = e.lang; time = e.time; cats = leagueDiscs(e); days = e.days; open = e.open }
        }
    }
}

struct CommunityView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var net: NetMonitor
    @StateObject private var combos = Loader<[Combo]>()
    @StateObject private var reports = Loader<[SharedReport]>()
    @StateObject private var setups = Loader<[SharedSetup]>()
    @State private var tab = 0
    @State private var q = ""
    @State private var lastDemo = false
    @State private var lastGame = ""
    @State private var sec = 0
    @State private var cat = ""

    private func match(_ s: String...) -> Bool { q.isEmpty || s.contains { $0.localizedCaseInsensitiveContains(q) } }

    private func load() async {
        switch tab {
        case 0: await combos.load { try await account.combos() }
        case 1: await reports.load { try await account.reports() }
        default: await setups.load { try await account.setups() }
        }
    }

    private var empty: Bool { tab == 0 ? combos.data == nil : tab == 1 ? reports.data == nil : setups.data == nil }

    var body: some View {
        Screen(title: t("community"), gameSeg: true) {
            Tabs(labels: [t("leaderboards"), t("leagues")], selected: $sec)
                .onAppear { Usage.count(sec == 1 ? "view:leagues" : "view:community") }
                .onChange(of: sec) { v in Usage.count(v == 1 ? "view:leagues" : "view:community") }
            if sec == 1 {
                LeagueHub()
            } else {
            // iRacing's disciplines, or Le Mans Ultimate's classes (no filter with one class only)
            let gm = account.game
            let cats = catKeys(gm, Set((combos.data ?? []).map { catOf(gm, $0.cat, $0.cls, $0.car) }))
            let fc = gm == "lmu" ? (cats.contains(cat) ? cat : "") : cat
            WebNote(text: t("community_web"))
            RecentRecords(cat: fc)
            // setups and shared race analyses are switched off for now: only the leaderboards, by lap time, per discipline
            if !cats.isEmpty {
                Pills(items: [("", t("disc_all"))] + cats.map { k in (k, catName(gm, k) + " (\((combos.data ?? []).filter { catOf(gm, $0.cat, $0.cls, $0.car) == k }.count))") }, selected: $cat)
            }
            TextField(t("search"), text: $q).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
            switch tab {
            case 0:
                let list = (combos.data ?? []).filter { match($0.track, $0.car) && (fc.isEmpty || catOf(gm, $0.cat, $0.cls, $0.car) == fc) }
                LoadState(loading: combos.loading, error: combos.error, stale: combos.stale) { Task { await load() } }
                if combos.data != nil && list.isEmpty { EmptyNote(text: t("nothing_found")) }
                ForEach(list) { x in
                    NavigationLink(value: Route.combo(x)) {
                        Panel {
                            Text(x.track).font(.ui(17, .black)).foregroundColor(Theme.fg).lineLimit(1)
                            Text(x.car).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                            HStack {
                                Text([catName(gm, catOf(gm, x.cat, x.cls, x.car)), t("laps_n", x.laps)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted)
                                Spacer()
                                Text(lapTime(x.best)).font(.mono(15, .bold)).foregroundColor(Theme.purple)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .buttonStyle(.plain)
                }
            case 1:
                let list = (reports.data ?? []).filter { match($0.track, $0.car, $0.alias) }
                LoadState(loading: reports.loading, error: reports.error, stale: reports.stale) { Task { await load() } }
                if reports.data != nil && list.isEmpty { EmptyNote(text: t("nothing_found")) }
                ForEach(list) { x in
                    Panel {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(x.track).font(.ui(17, .black)).lineLimit(1)
                                Text(x.car).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                                Text((x.alias == "Anonymous" ? t("anonymous") : x.alias) + (x.mine ? " · " + t("you_badge") : "") + " · " + day(x.created)).font(.ui(11)).foregroundColor(x.mine ? Theme.accent : Theme.muted)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(x.finish > 0 ? "P\(x.finish)/\(x.field)" : "—").font(.mono(17, .semibold).weight(.black))
                                Text(lapTime(x.best)).font(.mono(12)).foregroundColor(Theme.purple)
                            }
                        }
                    }
                }
            default:
                let list = (setups.data ?? []).filter { match($0.track, $0.car, $0.name, $0.alias) }
                LoadState(loading: setups.loading, error: setups.error, stale: setups.stale) { Task { await load() } }
                if setups.data != nil && list.isEmpty { EmptyNote(text: t("nothing_found")) }
                ForEach(list) { x in
                    Panel {
                        Text(x.name).font(.ui(17, .black)).lineLimit(1)
                        Text([x.car, x.track].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(2)
                        if !x.notes.isEmpty { Text(x.notes).font(.ui(12)).lineLimit(3) }
                        Text(x.alias + " · " + t("downloads", x.downloads) + " · " + day(x.created)).font(.ui(11)).foregroundColor(Theme.muted)
                    }
                }
            }
            }
        }
        .refreshable { await load() }
        .task(id: "\(tab)-\(account.demo)-\(account.game)") {
            if empty || account.demo != lastDemo || account.game != lastGame { if account.game != lastGame { cat = "" }; lastDemo = account.demo; lastGame = account.game; await load() }
        }
        .onChange(of: net.cameBack) { _ in Task { await load() } }
    }
}

/// Recent records: the fastest lap of every car and track, the newest first, with the lap it beat (filtered by the
/// discipline chosen); a row opens its leaderboard, "Track" its track page.
struct RecentRecords: View {
    @EnvironmentObject var account: Account
    let cat: String
    @StateObject private var recs = Loader<[RecordItem]>()
    @State private var all = false
    @State private var open = ""

    private func name(_ a: String?) -> String { a == nil || a == "Anonymous" ? t("anonymous") : a! }

    var body: some View {
        let gm = account.game
        let list = (recs.data ?? []).filter { cat.isEmpty || catOf(gm, $0.cat, $0.cls, $0.car) == cat }
        Panel {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    SectionLabel(text: t("recent_records"))
                    Text(t("recent_records_sub")).font(.ui(12)).foregroundColor(Theme.muted)
                }
                Spacer()
                if !list.isEmpty { Text(t("records_n", list.count)).font(.ui(12)).foregroundColor(Theme.muted) }
            }
            if recs.loading && recs.data == nil {
                Text("…").foregroundColor(Theme.muted)
            } else if let e = recs.error, recs.data == nil {
                Text(t(e)).font(.ui(12)).foregroundColor(Theme.bad)
            } else if list.isEmpty {
                Text(t("no_records")).font(.ui(15)).foregroundColor(Theme.muted)
            }
            // each record a card: its discipline's stripe, the car and track, the time and who set it, the lap it beat as a
            // bar (longer the bigger the margin); touched, its leaderboard, its track page and its driver's profile
            let most = max(0.001, list.compactMap { x in x.prevTime.map { $0 - x.time } }.max() ?? 1)
            ForEach(all ? list : Array(list.prefix(6))) { x in RecordCard(x: x, most: most, open: $open) }
            if list.count > 6 {
                Button(all ? t("fewer") : t("show_all_n", list.count)) { all.toggle() }.font(.ui(15, .bold)).foregroundColor(Theme.accent)
            }
        }
        .task(id: "\(account.demo)-\(account.game)") { await recs.load { try await account.records() } }
    }
}

/// One recent record as a card (Community → Recent records).
struct RecordCard: View {
    @EnvironmentObject var account: Account
    let x: RecordItem
    let most: Double
    @Binding var open: String

    private func name(_ a: String?) -> String { a == nil || a == "Anonymous" ? t("anonymous") : a! }

    var body: some View {
        let on = open == x.id
        VStack(alignment: .leading, spacing: 8) {
            Button { open = on ? "" : x.id } label: { head }.buttonStyle(.plain)
            beat
            if on { actions }
        }
        .padding(12)
        .background(Theme.ink)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? Theme.accent.opacity(0.45) : Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.top, 8)
    }

    private var head: some View {
        HStack(spacing: 10) {
            let gm = account.game
            let k = catOf(gm, x.cat, x.cls, x.car)
            RoundedRectangle(cornerRadius: 2).fill(catColor(gm, k)).frame(width: 4)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    GameBadge(game: x.game)
                    Text([day(x.created), catName(gm, k)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(1)
                }
                Text(x.car).font(.ui(14, .bold)).foregroundColor(Theme.fg).lineLimit(1)
                Text(x.track).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 2) {
                Text(lapTime(x.time)).font(.mono(15, .bold)).foregroundColor(Theme.purple)
                WetBadges(w: x.wet)
                Text(name(x.alias) + (x.mine ? " · " + t("you_badge") : "")).font(.ui(12, .semibold)).foregroundColor(x.mine ? Theme.accent : Theme.fg).lineLimit(1)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .contentShape(Rectangle())
    }

    private var beat: some View {
        let by: Double? = x.prevTime.map { $0 - x.time }
        let f: CGFloat = by.map { CGFloat(min(1, max(0.06, $0 / most))) } ?? 1
        let text: String = by.map { t("record_beat", name(x.prevAlias), String(format: "%.3f", $0)) } ?? t("record_first")
        return HStack(spacing: 8) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(Theme.purple).frame(width: g.size.width * f)
                }
            }
            .frame(height: 6)
            Text(text).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
        }
    }

    private var actions: some View {
        HStack(spacing: 6) {
            NavigationLink(value: Route.combo(x.combo)) { pill(t("rec_board"), true) }.buttonStyle(.plain)
            NavigationLink(value: Route.track(TrackRef(id: x.trackId, name: x.track))) { pill(t("track_page_short"), false) }.buttonStyle(.plain)
            if x.prof { NavigationLink(value: Route.profile(x.id)) { pill(t("profile"), false) }.buttonStyle(.plain) }
        }
    }

    private func pill(_ s: String, _ main: Bool) -> some View {
        Text(s).font(.ui(12, .semibold)).lineLimit(1)
            .frame(maxWidth: .infinity, minHeight: 36)
            .foregroundColor(main ? Theme.ink : Theme.fg)
            .background(main ? Theme.accent : Color.clear)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(main ? Color.clear : Theme.line, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// The track page: the map with the official turns and the direction arrow, how many drivers and laps the track has,
/// and the record of every car on it.
/// A track's hub: you here (the map, your best against the record, your sessions and races here, the coach for this
/// track), its leaderboard (the record of every car) and your notes.
struct TrackPageView: View {
    @EnvironmentObject var account: Account
    let ref: TrackRef
    @StateObject private var page = Loader<TrackPage>()
    @State private var sessions: [CloudSession] = []
    @State private var tab = 0

    var body: some View {
        let d = page.data
        let name = (d?.track.isEmpty == false ? d?.track : nil) ?? ref.name
        let mine = myTracks(sessions, account.races).first { sameTrack($0.name, name) }
        let cfg = mine?.sessions.map { fixText($0.trackConfig) }.first { !$0.isEmpty } ?? ""
        Screen(title: name.isEmpty ? t("track_page") : name, sub: cfg) {
            Tabs(labels: [t("hub_you"), t("hub_board"), t("hub_notes")], selected: $tab)
            ShortNote(key: "an_short")
            LoadState(loading: page.loading, error: page.error, stale: page.stale) { Task { await page.load { try await account.trackPage(trackId: ref.id) } } }
            switch tab {
            case 0: you(d, mine, name)
            case 1: board(d)
            default:
                if ref.id > 0 { TrackNotesPanel(trackId: ref.id, track: name) } else { EmptyNote(text: t("nothing_found")) }
            }
        }
        .task(id: ref.id) { await page.load { try await account.trackPage(trackId: ref.id) } }
        .task(id: account.game) { if let g = try? await account.sessions() { sessions = g.data } }
        .onChange(of: tab) { v in Usage.count("view:" + ["track", "trackboard", "tracknotes"][min(max(v, 0), 2)]) }
    }

    @ViewBuilder private func you(_ d: TrackPage?, _ mine: MyTrack?, _ name: String) -> some View {
        Panel {
            if let lay = d?.layout, lay.0.count >= 20 {
                Canvas { ctx, size in drawTrackRoad(ctx, size, lay.0, lay.1, d?.turns ?? []) }.frame(height: 240)
            } else {
                Text(t("track_no_map")).font(.ui(12)).foregroundColor(Theme.muted)
            }
        }
        let bestS = mine?.sessions.filter { ($0.best ?? 0) > 0 }.min { ($0.best ?? 0) < ($1.best ?? 0) }
        let rec = d?.cars.min { $0.time < $1.time }
        HStack(spacing: 8) {
            Metric(label: t("your_best"), value: lapTime(mine?.best), sub: bestS.map { fixText($0.car) })
            Metric(label: t("record"), value: lapTime(rec?.time), color: Theme.purple, sub: rec.map { $0.alias == "Anonymous" ? t("anonymous") : $0.alias })
        }
        .fixedSize(horizontal: false, vertical: true)
        let drives = (mine?.drives ?? []).sorted { $0.started > $1.started }
        if !drives.isEmpty {
            Panel {
                SectionLabel(text: t("sessions_here"))
                ForEach(Array(drives.enumerated()), id: \.offset) { k, x in
                    if k > 0 { Divider().background(Theme.line) }
                    NavigationLink(value: Route.analysis(0, x)) {
                        homeRow(x.place, x.pos != nil ? Theme.fg : Theme.muted, fixText(x.car), x.kind, x.cat ?? "", agoText(x.started), x.laps, x.best, x.inClass && x.pos != nil ? t("in_class") : "") { SessionBadges(x: x) }
                    }.buttonStyle(.plain)
                }
            }
        }
        let rs = (mine?.races ?? []).sorted { $0.when > $1.when }
        if !rs.isEmpty {
            Panel {
                SectionLabel(text: t("races_here"))
                ForEach(Array(rs.enumerated()), id: \.offset) { k, r in
                    if k > 0 { Divider().background(Theme.line) }
                    NavigationLink(value: Route.race(r)) {
                        homeRow(r.dnf ? t("dnf") : "P\(r.finish)", r.dnf ? Theme.bad : Theme.fg, r.car, "race", raceDisc(r.cat, r.car), agoText(r.when), r.laps.count, r.best) {
                            HStack(spacing: 6) { DrinksBadge(race: r); AiBadge(race: r) }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
        // the coach opens on your newest session here
        if let x = mine?.sessions.max(by: { $0.started < $1.started }) {
            NavigationLink(value: Route.analysis(1, x)) {
                Text(t("coach_for", name)).font(.ui(15, .bold)).lineLimit(1).foregroundColor(Theme.ink)
                    .frame(maxWidth: .infinity, minHeight: 48).background(Theme.accent).clipShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
        }
        if mine == nil && !page.loading { EmptyNote(text: t("no_sessions")) }
    }

    @ViewBuilder private func board(_ d: TrackPage?) -> some View {
        if let d {
            HStack(spacing: 6) {
                GameBadge(game: d.game)
                Text(t("track_counts", d.drivers, d.laps, d.cars.count)).font(.ui(12)).foregroundColor(Theme.muted)
            }
            SectionLabel(text: t("records_per_car"))
            if d.cars.isEmpty { EmptyNote(text: t("no_records")) }
            ForEach(d.cars) { x in
                NavigationLink(value: Route.combo(x.combo)) {
                    Panel {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(x.car).font(.ui(17, .black)).foregroundColor(Theme.fg).lineLimit(1)
                                    GameBadge(game: x.game)
                                }
                                Text([catName(account.game, catOf(account.game, x.cat, x.cls, x.car)), (x.alias == "Anonymous" ? t("anonymous") : x.alias) + (x.mine ? " · " + t("you_badge") : ""), t("drivers", x.n), day(x.created)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(lapTime(x.time)).font(.mono(15, .bold)).foregroundColor(Theme.purple)
                                WetBadges(w: x.wet)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// ---------- Tracks ----------

/// A circuit you drove: every session there (races too, for their laps) and every race.
struct MyTrack {
    let name: String
    let sessions: [CloudSession]
    let races: [Race]
    /// practice, qualifying and test drives: the races are in races
    var drives: [CloudSession] { sessions.filter { !$0.kind.lowercased().contains("race") } }
    var count: Int { drives.count + races.count }
    var laps: Int { drives.reduce(0) { $0 + $1.laps } + races.reduce(0) { $0 + $1.laps.count } }
    var best: Double? { (sessions.compactMap(\.best) + races.compactMap(\.best)).filter { $0 > 0 }.min() }
    var last: Double { max(sessions.map(\.started).max() ?? 0, races.map(\.when).max() ?? 0) }
}

/// The same circuit: "Spa-Francorchamps" and "Spa-Francorchamps - Grand Prix" too.
func sameTrack(_ a: String, _ b: String) -> Bool {
    guard !a.isEmpty, !b.isEmpty else { return false }
    let x = a.lowercased(), y = b.lowercased()
    return x == y || x.hasPrefix(y) || y.hasPrefix(x)
}

/// Your circuits, the most driven first (the newest of a tie).
func myTracks(_ sessions: [CloudSession], _ races: [Race]) -> [MyTrack] {
    var names: [String] = []
    func nameOf(_ s: String) -> String {
        let x = fixText(s).trimmingCharacters(in: .whitespaces)
        if let n = names.first(where: { sameTrack($0, x) }) { return n }
        names.append(x)
        return x
    }
    let ss = Dictionary(grouping: sessions) { nameOf($0.track) }
    let rs = Dictionary(grouping: races) { nameOf($0.track) }
    return names.map { MyTrack(name: $0, sessions: ss[$0] ?? [], races: rs[$0] ?? []) }
        .sorted { $0.count != $1.count ? $0.count > $1.count : $0.last > $1.last }
}

/// The community's id of a circuit, found by its name among the leaderboards (0: nobody shared a lap there yet).
func trackIdOf(_ combos: [Combo], _ name: String) -> Int64 {
    (combos.first { $0.track.lowercased() == name.lowercased() } ?? combos.first { sameTrack($0.track, name) })?.trackId ?? 0
}

/// Every circuit you drove: the most driven on top with its map, the others as tiles. Each opens its hub.
struct TracksView: View {
    @EnvironmentObject var account: Account
    @State private var sessions: [CloudSession]?
    @State private var combos: [Combo] = []
    @State private var heroId: Int64 = 0
    @State private var heroLayout: ([Double], [Double])?
    @State private var err: String?
    @State private var q = ""
    @State private var lastGame = ""

    private func reload() async {
        let gm = account.game
        if lastGame != gm { lastGame = gm; sessions = nil; combos = []; heroId = 0; heroLayout = nil }
        do {
            let g = try await account.sessions()
            if gm == account.game { sessions = g.data; err = nil }
        } catch {
            if !Task.isCancelled && sessions == nil { err = (error as? AppError)?.key ?? error.localizedDescription }
        }
        if let c = try? await account.combos(), gm == account.game { combos = c.data }
        if let top = myTracks(sessions ?? [], account.races).first {
            let id = trackIdOf(combos, top.name)
            if id > 0 && id != heroId {
                let lay = await account.trackLayout(trackId: id)
                if gm == account.game { heroId = id; heroLayout = lay }
            }
        }
    }

    var body: some View {
        let all = myTracks(sessions ?? [], account.races)
        let list = all.filter { q.isEmpty || $0.name.localizedCaseInsensitiveContains(q) }
        let hero: MyTrack? = list.first.flatMap { $0.name == all.first?.name ? $0 : nil }
        let rest = hero == nil ? list : Array(list.dropFirst())
        let rows: [[MyTrack]] = stride(from: 0, to: rest.count, by: 2).map { Array(rest[$0..<min($0 + 2, rest.count)]) }
        Screen(title: t("tab_tracks"), gameSeg: true) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundColor(Theme.muted)
                TextField(t("find_track"), text: $q).foregroundColor(Theme.fg).autocorrectionDisabled()
            }
            .padding(.horizontal, 12).padding(.vertical, 10).background(Theme.well)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
            ShortNote(key: "an_short")
            LoadState(loading: sessions == nil && err == nil, error: err) { Task { await reload() } }
            if sessions != nil && all.isEmpty { EmptyNote(text: t("no_tracks")) }
            else if !all.isEmpty && list.isEmpty { EmptyNote(text: t("nothing_found")) }
            if let x = hero {
                let id = trackIdOf(combos, x.name)
                NavigationLink(value: Route.track(TrackRef(id: id, name: x.name))) { TrackHero(x: x, layout: id > 0 && id == heroId ? heroLayout : nil) }.buttonStyle(.plain)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    ForEach(row, id: \.name) { x in
                        NavigationLink(value: Route.track(TrackRef(id: trackIdOf(combos, x.name), name: x.name))) { TrackTile(x: x) }.buttonStyle(.plain)
                    }
                    if row.count < 2 { Color.clear.frame(maxWidth: .infinity) }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task(id: "\(account.game)|\(account.demo)|\(account.refreshTick)") { await reload() }
        .refreshable { await reload() }
    }
}

/// The circuit you drove most: its map as the picture, then its name, your sessions, laps and best there.
struct TrackHero: View {
    let x: MyTrack
    let layout: ([Double], [Double])?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let lay = layout, lay.0.count >= 20 {
                Canvas { ctx, size in drawTrackRoad(ctx, size, lay.0, lay.1, [], edge: Theme.accent) }.frame(height: 170)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(t("most_driven")).font(.mono(11, .semibold)).foregroundColor(Theme.accent)
                Text(x.name.uppercased()).font(.display(22, .bold)).foregroundColor(Theme.fg).lineLimit(2)
                Text(t("trk_counts", x.count, x.laps) + (x.best.map { " · " + t("trk_best", lapTime($0)) } ?? "")).font(.ui(12)).foregroundColor(Theme.muted)
            }
            .padding(.horizontal, 6).padding(.bottom, 6).padding(.top, 4)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RadialGradient(colors: [Color(red: 0x24 / 255, green: 0x30 / 255, blue: 0x3F / 255), Theme.surface], center: UnitPoint(x: 0.5, y: 0.2), startRadius: 0, endRadius: 320))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .contentShape(RoundedRectangle(cornerRadius: 20))
    }
}

/// Another circuit you drove: its initials, its name, your sessions and laps there and your best.
struct TrackTile: View {
    let x: MyTrack
    var body: some View {
        let mono = x.name.split(whereSeparator: { $0 == " " || $0 == "-" }).prefix(2).map { String($0.prefix(1)) }.joined().uppercased()
        VStack(alignment: .leading, spacing: 2) {
            Text(mono).font(.display(17, .heavy)).foregroundColor(Theme.accent)
                .frame(width: 40, height: 40).background(Theme.well)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.bottom, 6)
            Text(x.name).font(.ui(14, .semibold)).foregroundColor(Theme.fg).lineLimit(2).multilineTextAlignment(.leading)
            Text(t("trk_counts", x.count, x.laps)).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(1)
            Spacer(minLength: 0)
            Text(lapTime(x.best)).font(.mono(13, .bold)).foregroundColor(Theme.fg).padding(.top, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .contentShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// A track's layout as a road with depth, its start/finish line, the direction arrow and the official turns: the same
/// drawing as the live map, without the cars.
func drawTrackRoad(_ ctx: GraphicsContext, _ size: CGSize, _ xs: [Double], _ ys: [Double], _ turns: [Double], edge: Color? = nil) {
    let n = xs.count, pad: CGFloat = 22
    guard n >= 20 else { return }
    let minX = xs.min() ?? 0, maxX = xs.max() ?? 1, minY = ys.min() ?? 0, maxY = ys.max() ?? 1
    let k = min((size.width - 2 * pad) / CGFloat(max(1e-6, maxX - minX)), (size.height - 2 * pad) / CGFloat(max(1e-6, maxY - minY)))
    let ox = (size.width - 2 * pad - CGFloat(maxX - minX) * k) / 2, oy = (size.height - 2 * pad - CGFloat(maxY - minY) * k) / 2
    func pt(_ i: Int) -> CGPoint { CGPoint(x: pad + CGFloat(xs[i] - minX) * k + ox, y: size.height - pad - CGFloat(ys[i] - minY) * k - oy) }
    var track = Path()
    for i in 0..<n { if i == 0 { track.move(to: pt(i)) } else { track.addLine(to: pt(i)) } }
    track.closeSubpath()
    let w: CGFloat = 11
    // the track as a road with depth: its shadow, the rim and the darker asphalt inside
    ctx.stroke(track.offsetBy(dx: 1.5, dy: 2.5), with: .color(.black.opacity(0.38)), style: StrokeStyle(lineWidth: w + 2, lineCap: .round, lineJoin: .round))
    ctx.stroke(track, with: .color(edge ?? Color(red: 0x3F / 255, green: 0x49 / 255, blue: 0x56 / 255)), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
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
        ctx.draw(Text("T\(ti + 1)").font(.ui(9, .bold)).foregroundColor(Theme.muted), at: CGPoint(x: q.x + qx * (w / 2 + 9), y: q.y + qy * (w / 2 + 9)))
    }
}

struct ComboView: View {
    @EnvironmentObject var account: Account
    let combo: Combo
    @StateObject private var board = Loader<[CommunityLap]>()

    var body: some View {
        let laps = board.data ?? []
        let shown = laps
        let top = laps.first?.time
        // the server marks the signed-in driver's own lap (anonymous ones too); older servers: by the public name
        let mine = laps.firstIndex { $0.mine } ?? laps.firstIndex { !account.display.isEmpty && $0.alias.caseInsensitiveCompare(account.display) == .orderedSame }
        // Le Mans Ultimate: this car's board, or each driver's best of any car of its class here
        let cls = account.boardClass(trackId: combo.trackId, carId: combo.carId)
        let whole = account.boardWhole && cls != nil
        Screen(title: combo.track, sub: whole ? lmuClass(cls, combo.car) : combo.car) {
            // its track page
            HStack {
                if cls != nil {
                    HStack(spacing: 6) {
                        wholeChip(t("board_this_car"), false)
                        wholeChip(t("board_whole_class"), true)
                    }
                }
                Spacer()
                NavigationLink(value: Route.track(TrackRef(id: combo.trackId, name: combo.track))) { Text(t("track_page")).font(.ui(12, .bold)).foregroundColor(Theme.accent) }
                    .buttonStyle(.plain)
            }
            LoadState(loading: board.loading, error: board.error, stale: board.stale) { Task { await load() } }
            if board.data != nil {
                Panel {
                    if mine == 0 && laps.count > 1 {
                        Text("🏆 " + t("you_fastest")).font(.ui(15, .black)).foregroundColor(Theme.purple)
                        Text(t("you_fastest_sub", laps.count, lapTime(laps[0].time))).font(.ui(12)).foregroundColor(Theme.muted)
                    } else if let mine { Text(t("your_position", mine + 1, laps.count, lapTime(laps[mine].time))).font(.ui(15, .bold)).foregroundColor(Theme.accent) }
                    else { Text(t("not_on_board")).font(.ui(12)).foregroundColor(Theme.muted) }
                    HStack(spacing: 6) {
                        GameBadge(game: account.game)
                        Text([catName(account.game, catOf(account.game, combo.cat, combo.cls, combo.car)), t("drivers", laps.count)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(11)).foregroundColor(Theme.muted)
                    }
                    if let mine {
                        // the picture of this lap for the phone's share sheet (ShareCard in Reports.swift)
                        Button {
                            let car = whole ? (laps[mine].car.flatMap { $0.isEmpty ? nil : $0 } ?? combo.car) : combo.car
                            ShareCard.share(track: combo.track, car: car, time: laps[mine].time, pos: mine + 1, of: laps.count, game: account.game)
                        } label: { Text(t("share_my_lap")).font(.ui(12, .bold)).foregroundColor(Theme.accent) }
                        .buttonStyle(.plain).padding(.top, 4)
                    }
                }
            }
            SectionLabel(text: t("fastest_drivers"))
            ForEach(shown) { lap in
                let i = laps.firstIndex(of: lap) ?? 0
                let me = i == mine
                NavigationLink(value: Route.profile(lap.id)) {
                Panel {
                    HStack {
                        Text("\(i + 1)").font(.mono(15, .bold)).foregroundColor(i == 0 ? Theme.purple : me ? Theme.accent : Theme.muted).frame(width: 32, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 6) {
                                Text(lap.alias == "Anonymous" ? t("anonymous") : lap.alias).font(.ui(15, .bold)).foregroundColor(me ? Theme.accent : Theme.fg).lineLimit(1).underline(lap.prof)
                                if lap.sup { SupBadge() }
                                if lap.mine { Text(t("you_badge")).font(.ui(10, .bold)).foregroundColor(Theme.accent) }
                            }
                            if whole, let car = lap.car { Text(car).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(1) }
                            if !lap.sectors.isEmpty { Text(lap.sectors.map { String(format: "%.3f", $0) }.joined(separator: "  ")).font(.mono(10)).foregroundColor(Theme.muted) }
                            if !lap.hasTrace { Text(t("trace_not_shared")).font(.ui(10)).foregroundColor(Theme.muted) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(lapTime(lap.time)).font(.mono(15, .bold)).foregroundColor(i == 0 ? Theme.purple : Theme.fg)
                            WetBadges(w: lap.wet)
                            if let top, i > 0 { Text(String(format: "+%.3f", lap.time - top)).font(.mono(11)).foregroundColor(Theme.muted) }
                        }
                    }
                }
                }
                .buttonStyle(.plain)
                .disabled(!lap.prof)
            }
        }
        .task { if board.data == nil { await load() } }
    }

    private func load() async { await board.load { try await account.board(trackId: combo.trackId, carId: combo.carId) } }

    private func wholeChip(_ label: String, _ on: Bool) -> some View {
        let sel = account.boardWhole == on
        return Button {
            guard account.boardWhole != on else { return }
            account.boardWhole = on
            Task { await load() }
        } label: {
            Text(label).font(.ui(11, .bold)).foregroundColor(sel ? Theme.bg : Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 5).background(sel ? Theme.accent : Theme.surface2).clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// The last 26 weeks in squares, brighter the more sessions that day (keys "y-m-d" like the web).
struct DayGrid: View {
    let days: [String: Int]
    /// Analysis: the day chosen, and what pressing a day with sessions does
    var selected = ""
    var onDay: ((String) -> Void)? = nil
    var body: some View {
        let cal = Calendar.current, today = cal.startOfDay(for: Date())
        let wd = (cal.component(.weekday, from: today) + 5) % 7 // Monday = 0
        let start = cal.date(byAdding: .day, value: -(wd + 25 * 7), to: today) ?? today
        let mx = max(1, days.values.max() ?? 1)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(0..<26, id: \.self) { w in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { d in
                            let day = cal.date(byAdding: .day, value: w * 7 + d, to: start) ?? start
                            let c = cal.dateComponents([.year, .month, .day], from: day)
                            let k = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
                            let n = day > today ? -1 : days[k] ?? 0
                            let lv = n > 0 ? min(4, max(1, Int((Double(n) / Double(mx) * 4).rounded(.up)))) : 0
                            let side: CGFloat = onDay == nil ? 10 : 14
                            RoundedRectangle(cornerRadius: 2).fill(n < 0 ? Color.clear : lv == 0 ? Theme.surface2 : Theme.accent.opacity(0.25 + Double(lv) * 0.18)).frame(width: side, height: side)
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(k == selected ? Theme.fg : Color.clear, lineWidth: 2))
                                .onTapGesture { if n > 0 { onDay?(k) } }
                        }
                    }
                }
            }
        }
    }
}

/// A driver's profile: nickname (never the iRacing name), license classes, recent races, laps on the leaderboards.
struct ProfileView: View {
    @EnvironmentObject var account: Account
    let lapId: String?
    @State private var p: DriverProfile?
    @State private var error: String?

    private func load() async {
        do { p = try await account.profile(lapId); error = nil } catch { self.error = (error as? AppError)?.key ?? error.localizedDescription }
    }

    var body: some View {
        Screen(title: p?.name ?? t("profile"), sub: p.map { t("since", day($0.since)) } ?? "") {
            if let p {
                Panel {
                    HStack(spacing: 8) {
                        Text(p.name).font(.ui(20, .black)).lineLimit(2)
                        if p.supporter && !(p.mine && p.supporterHidden) { SupBadge() }
                        Spacer()
                    }
                    if p.anonymous { Text("🔒 " + t(p.mine ? "anon_mine" : "anon_admins_only")).font(.ui(12)).foregroundColor(Theme.muted) }
                    if p.mine && p.supporter && p.supporterHidden { Text(t("badge_hidden")).font(.ui(12)).foregroundColor(Theme.muted) }
                    // their Discord, when they chose to show it
                    if !p.discordId.isEmpty, p.discordId.allSatisfy({ $0.isASCII && $0.isNumber }), let u = URL(string: "https://discord.com/users/" + p.discordId) {
                        HStack(spacing: 0) {
                            Text("Discord: ").font(.ui(12)).foregroundColor(Theme.muted)
                            Link(p.discordHandle.isEmpty ? t("discord_open") : "@" + p.discordHandle, destination: u).font(.ui(12, .bold)).foregroundColor(Theme.accent)
                        }
                        .padding(.top, 2)
                    }
                    let ls = DISCS.filter { p.lics[$0] != nil }
                    if !ls.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) { ForEach(ls, id: \.self) { k in HStack(spacing: 4) { LicBadge(k: p.lics[k]); Text(discName(k)).font(.ui(12)) } } }
                        }.padding(.top, 6)
                    }
                    if p.mine && p.supporter {
                        Button(t(p.supporterHidden ? "show_badge" : "hide_badge")) { Task { try? await account.setBadgeHidden(!p.supporterHidden); await load() } }
                            .font(.ui(12, .bold)).foregroundColor(Theme.accent).padding(.top, 6)
                    }
                }
                let recs = p.laps.filter { $0.pos == 1 }.count, pods = p.laps.filter { $0.pos > 0 && $0.pos <= 3 }.count
                if !p.laps.isEmpty {
                    HStack(spacing: 8) {
                        StatTile(value: "\(p.laps.count)", label: t("boards_n"))
                        StatTile(value: "\(recs)", label: t("records_held"), tint: recs > 0 ? Theme.purple : Theme.fg)
                        StatTile(value: "\(pods)", label: t("podiums_top3"))
                    }
                }
                SectionLabel(text: t("days_driven").uppercased() + " · " + t("days_in_6m", p.days.count))
                Panel { DayGrid(days: p.days) }
                SectionLabel(text: t("recent_races").uppercased())
                if p.races.isEmpty { EmptyNote(text: t("no_races_yet")) }
                ForEach(p.races) { r in
                    Panel {
                        HStack(spacing: 6) {
                            Text([day(r.when), r.official ? t("official") : "", discName(r.cat)].filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(11)).foregroundColor(Theme.muted)
                            LicBadge(k: r.lic)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.track).font(.ui(15, .bold)).lineLimit(1)
                                Text(r.car).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(r.dnf ? "DNF" : r.finish > 0 ? "P\(r.finish)/\(r.field)" : "—").font(.mono(17, .semibold).weight(.black))
                        }
                        let dif = r.start > 0 && r.finish > 0 ? r.start - r.finish : 0
                        Text([dif != 0 ? (dif > 0 ? "+" : "") + "\(dif) " + t("places") : "", "\(r.inc)x", r.irChange != 0 ? "iR " + (r.irChange > 0 ? "+" : "") + "\(r.irChange)" : "", r.best.map { t("best_short") + " " + lapTime($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.ui(11)).foregroundColor(Theme.muted)
                    }
                }
                SectionLabel(text: t("on_leaderboards").uppercased())
                if p.laps.isEmpty { EmptyNote(text: t("no_laps_yet")) }
                ForEach(p.laps) { l in
                    NavigationLink(value: Route.combo(Combo(trackId: l.trackId, track: l.track, carId: l.carId, car: l.car, laps: 0, best: l.time, cat: l.cat))) {
                    Panel {
                        HStack(spacing: 6) {
                            LicBadge(k: l.lic)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(l.track).font(.ui(15, .bold)).lineLimit(1)
                                Text([l.car, discName(l.cat)].filter { !$0.isEmpty }.joined(separator: " · ") + (l.anon ? " · 🔒 " + t(p.mine ? "anon_lap_mine" : "anon_lap_admins") : "")).font(.ui(11)).foregroundColor(Theme.muted).lineLimit(2)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(lapTime(l.time)).font(.mono(15, .bold)).foregroundColor(Theme.fg)
                                if l.pos > 0 { Text("P\(l.pos)" + (l.of > 0 ? "/\(l.of)" : "")).font(.mono(11)).foregroundColor(l.pos == 1 ? Theme.purple : Theme.muted) }
                            }
                        }
                    }
                    }
                    .buttonStyle(.plain)
                    .disabled(l.trackId == 0 || l.carId == 0)
                }
            } else if let error {
                EmptyNote(text: error.localizedCaseInsensitiveContains("anonymous") ? t("anonymous_private") : t(error))
            } else {
                EmptyNote(text: t("loading"))
            }
        }
        .task { if p == nil { await load() } }
    }
}

// ---------- Live ----------

struct LiveView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var live: Live
    @State private var codeIn = ""
    @State private var codeErr = false

    private var status: (String, Color) {
        switch live.link {
        case .off: return (t("offline_s"), Theme.muted)
        case .connecting: return (t("connecting"), Theme.muted)
        case .open:
            if !live.pcOnline { return (t("pc_offline"), Theme.muted) }
            if !live.simConnected { return (t("pc_no_sim"), Theme.accent) }
            return (t("live_s"), Theme.good)
        }
    }

    private func start() { live.start(token: account.token, key: account.dataKey, demo: account.demo) }

    var body: some View {
        Screen(title: t("live_title")) {
            ShortNote(key: "live_short")
            // your PC, from anywhere: Connect when it is online, Disconnect to stop the live data on this phone
            Panel {
                Text(t("your_pc_anywhere")).font(.ui(17, .black))
                switch live.mode {
                case .own where live.pcOnline && live.ask == "wait":
                    // your PC asks you there: Accept / Decline
                    TimelineView(.periodic(from: .now, by: 5)) { tl in
                        let late = tl.date.timeIntervalSince(live.askAt) >= 60
                        VStack(alignment: .leading, spacing: 6) {
                            Text(late ? t("pc_no_answer") : t("accept_on_pc")).font(.ui(15)).foregroundColor(Theme.muted).padding(.vertical, 4)
                            HStack(spacing: 14) {
                                if late { Button(t("try_again")) { live.askAgain() }.buttonStyle(.borderedProminent).tint(Theme.accent) }
                                Button(t("cancel")) { live.watch(.idle) }.foregroundColor(Theme.bad).font(.ui(15, .bold))
                            }
                        }
                    }
                case .own:
                    Text(live.pcOnline ? t("watching_pc") : t("waiting_pc")).font(.ui(15)).foregroundColor(live.pcOnline ? Theme.good : Theme.muted).padding(.vertical, 4)
                    Button(t("disconnect")) { live.watch(.idle) }.foregroundColor(Theme.bad).font(.ui(15, .bold))
                    if live.pcOnline && live.ask == "ok" {
                        Divider().padding(.vertical, 6)
                        Text(t("your_code")).font(.ui(15, .bold))
                        if !live.myCode.isEmpty {
                            Text(live.myCode).font(.mono(22, .black)).foregroundColor(Theme.accent).padding(.vertical, 2)
                            Text(t("your_code_sub")).font(.ui(12)).foregroundColor(Theme.muted)
                            HStack(spacing: 14) {
                                Button(t("new_code")) { live.share(on: true, new: true) }.foregroundColor(Theme.accent)
                                Button(t("stop_sharing")) { live.share(on: false) }.foregroundColor(Theme.bad)
                            }.font(.ui(12, .bold)).padding(.top, 4)
                        } else {
                            Text(t("get_code_sub")).font(.ui(12)).foregroundColor(Theme.muted)
                            Button(t("get_code")) { live.share(on: true) }.foregroundColor(Theme.accent).font(.ui(12, .bold)).padding(.top, 4)
                        }
                    }
                case .code:
                    Text(t("watching_other_back")).font(.ui(15)).foregroundColor(Theme.muted).padding(.vertical, 4)
                    Button(t("connect")) { live.watch(.own) }.buttonStyle(.borderedProminent).tint(Theme.accent)
                case .idle:
                    Text(live.pcOnline ? t("pc_is_online") : t("open_pc")).font(.ui(15)).foregroundColor(live.pcOnline ? Theme.good : Theme.muted).padding(.vertical, 4)
                    Button(t("connect")) { live.watch(.own) }.buttonStyle(.borderedProminent).tint(Theme.accent).disabled(!live.pcOnline)
                    if Date().timeIntervalSince(live.declinedAt) < 60 { Text(t("declined_on_pc")).font(.ui(12)).foregroundColor(Theme.bad).padding(.top, 4) }
                }
            }
            // the PC app, right under it: it is what sends the telemetry
            Link(destination: URL(string: "https://pitlanehq.app/dl/PitlaneHQ-Setup.exe")!) { ActionRow(title: t("download_pc").uppercased(), sub: t("download_pc_sub"), icon: "desktopcomputer") }
            // someone else's telemetry with the code they give you
            Panel {
                Text(t("watch_other")).font(.ui(17, .black))
                if live.mode == .code {
                    Text((live.pcOnline ? t("watching") : t("waiting_their_pc")) + " · " + stride(from: 0, to: live.code.count, by: 4).map { i in String(Array(live.code)[i..<min(i + 4, live.code.count)]) }.joined(separator: "-"))
                        .font(.ui(15)).foregroundColor(live.pcOnline ? Theme.good : Theme.muted).padding(.vertical, 4)
                    Button(t("disconnect")) { live.watch(.idle) }.foregroundColor(Theme.bad).font(.ui(15, .bold))
                } else {
                    TextField("ABCD-EFGH-JK", text: $codeIn).textInputAutocapitalization(.characters).autocorrectionDisabled().padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    if codeErr { Text(t("code_bad")).font(.ui(12)).foregroundColor(Theme.bad) }
                    Button(t("watch")) {
                        let c = PLCrypto.codeNorm(codeIn)
                        if PLCrypto.codeOk(c) { codeErr = false; live.watch(.code, code: c) } else { codeErr = true }
                    }.buttonStyle(.borderedProminent).tint(Theme.accent).padding(.top, 4)
                }
            }
            if live.mode == .code || (live.mode == .own && live.ask == "ok") {
            StatusPill(text: status.0, color: status.1)
            if let m = live.message { Text(t(m)).font(.ui(12)).foregroundColor(Theme.bad) }
            // the same three tabs as the PC's Telemetry: what matters while driving, the standings, the tyres
            LiveTabsView(live: live)
            }
        }
        .onAppear { live.screens += 1; start() }
        // leaving Telemetry: back to presence only (the server's sync nudge keeps reaching the phone)
        .onDisappear { live.screens = max(0, live.screens - 1); live.startPresence(token: account.token, key: account.dataKey) }
    }

    private func bar(_ label: String, _ v: Double?, _ c: Color) -> some View {
        HStack {
            Text(label).font(.mono(11)).foregroundColor(Theme.muted).frame(width: 90, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.surface2)
                    Capsule().fill(c).frame(width: g.size.width * min(max(v ?? 0, 0), 1))
                }
            }
            .frame(height: 10)
        }
        .padding(.top, 6)
    }
}

// ---------- DRINKS mode (admins) ----------

// the admin profile: every shared lap and race analysis with the name it shows and who really
// uploaded it (anonymous items and DRINKS drivers too), and the accounts
/// An account whose "in Pitlane HQ since" is being changed.
struct SinceEdit: Identifiable {
    let id: String
    var date: Date
    let custom: Bool
}

/// the admin panel's sections, the PC's: summary (the key numbers and what the drivers use), users, feedback, content
/// (the shared items), sessions, coach, server (the emails, the tools, the blocked sign-ins); each says in one line what it is
let adminSections = ["summary", "users", "feedback", "content", "sessions", "coach", "server"]

struct AdminView: View {
    @EnvironmentObject var account: Account
    @Environment(\.dismiss) private var dismiss
    @State private var kind = "summary"
    @State private var days = 14
    @State private var since: SinceEdit?
    @State private var renaming: (String, String)?
    @State private var newName = ""
    @State private var linking: String?   // the account a DRINKS driver is being joined to
    @State private var linkName = ""
    @State private var rows: [[String: Any]]?
    /// the summary's and the server's status, the coach's answer
    @State private var extra: [String: Any]?
    @State private var error: String?
    @State private var confirmDelete: (String, String)?

    var body: some View {
        Screen(title: t("admin_profile")) {
            Panel {
                // admin mode switched off here: back to the app as everyone sees it
                Toggle(t("admin_mode"), isOn: Binding(get: { account.adminMode }, set: { on in account.adminMode = on; if !on { dismiss() } })).font(.ui(15, .bold))
                Text(t("admin_mode_sub")).font(.ui(12)).foregroundColor(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) { HStack(spacing: 8) {
                ForEach(adminSections, id: \.self) { k in
                    Button { kind = k; Task { await load() } } label: {
                        Text(t("admin_sec_" + k)).font(.ui(15)).padding(.horizontal, 12).padding(.vertical, 6)
                            .background(kind == k ? Theme.accent : Theme.surface2).foregroundColor(kind == k ? Theme.ink : Theme.fg).clipShape(Capsule())
                    }
                }
            } }
            Text(t("admin_sec_" + kind + "_sub")).font(.ui(12)).foregroundColor(Theme.muted)
            if let e = error {
                EmptyNote(text: t(e))
            } else if let rows = rows {
                section(rows)
            } else {
                EmptyNote(text: t("loading"))
            }
        }
        .task { await load() }
        .onAppear { Usage.count("view:admin") }
        .sheet(item: $since) { e in
            NavigationStack {
                Form {
                    DatePicker(t("admin_set_since"), selection: Binding(get: { since?.date ?? e.date }, set: { since?.date = $0 }), in: ...Date(), displayedComponents: .date).datePickerStyle(.graphical)
                    if e.custom { Button(t("admin_account_date")) { let id = e.id; since = nil; Task { try? await account.adminSince(id, nil); await load() } } }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { since = nil } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("save")) {
                            let id = e.id, d = since?.date ?? e.date
                            let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
                            var u = DateComponents(); u.year = c.year; u.month = c.month; u.day = c.day; u.hour = 12
                            var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
                            let ms = (cal.date(from: u) ?? d).timeIntervalSince1970 * 1000
                            since = nil
                            Task { try? await account.adminSince(id, ms); await load() }
                        }
                    }
                }
            }
        }
        // a DRINKS driver joined to an account: what was shared under the driver's name goes to the account, later laps too
        .alert(t("admin_link_guest"), isPresented: Binding(get: { linking != nil }, set: { if !$0 { linking = nil } })) {
            TextField(t("admin_link_guest"), text: $linkName)
            Button(t("save")) {
                let id = linking ?? "", n = linkName.trimmingCharacters(in: .whitespaces)
                linking = nil
                if !n.isEmpty { Task { try? await account.adminAccount(id, "link-guest", name: n); await load() } }
            }
            Button(t("cancel"), role: .cancel) { linking = nil }
        } message: { Text(t("admin_link_guest_hint")) }
        .alert(t("admin_rename"), isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField(t("admin_rename"), text: $newName)
            Button(t("save")) {
                let id = renaming?.0 ?? "", n = newName.trimmingCharacters(in: .whitespaces)
                renaming = nil
                if !n.isEmpty { Task { try? await account.adminAccount(id, "rename", name: n); await load() } }
            }
            Button(t("cancel"), role: .cancel) { renaming = nil }
        }
        .alert(t("admin_delete_ask", confirmDelete?.1 ?? ""), isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } })) {
            Button(t("delete"), role: .destructive) {
                let id = confirmDelete?.0 ?? ""
                Task { try? await account.adminDeleteUser(id); await load() }
            }
            Button(t("cancel"), role: .cancel) {}
        }
    }

    private func iv(_ v: Any?) -> Int { (v as? NSNumber)?.intValue ?? 0 }

    @ViewBuilder private func section(_ rows: [[String: Any]]) -> some View {
        switch kind {
        case "summary": summaryView(rows.first)
        case "server":
            Panel { serverView(extra ?? [:]) }
            SectionLabel(text: t("admin_blocked"))
            if rows.isEmpty { EmptyNote(text: t("admin_nothing")) }
            ForEach(rows.indices, id: \.self) { i in Panel { blockedRow(rows[i]) } }
        case "coach":
            Panel { coachHead(extra ?? [:]) }
            if rows.isEmpty { EmptyNote(text: t("admin_nothing")) }
            ForEach(rows.indices, id: \.self) { i in Panel { coachRow(rows[i]) } }
        default:
            if rows.isEmpty { EmptyNote(text: t("admin_nothing")) }
            ForEach(rows.indices, id: \.self) { i in row(rows[i]) }
        }
    }

    // one function per kind of row: one big builder was too much for the type checker
    @ViewBuilder private func row(_ x: [String: Any]) -> some View {
        Panel {
            switch kind {
            case "sessions": sessionRow(x)
            case "users": userRow(x)
            case "feedback": feedbackRow(x)
            default: itemRow(x)
            }
        }
    }

    /// Summary: the key numbers, then what the drivers use over the days chosen
    @ViewBuilder private func summaryView(_ an: [String: Any]?) -> some View {
        let x = extra ?? [:]
        let c = x["counts"] as? [String: Any] ?? [:], g = x["config"] as? [String: Any] ?? [:]
        let n = { (k: String) in "\((c[k] as? NSNumber)?.intValue ?? 0)" }
        Panel {
            Text(t("admin_counts", n("accounts"), n("verified"), n("sessions"), n("shared"))).font(.ui(12, .bold)).foregroundColor(Theme.fg)
            Text(t("admin_activity", n("new7"), n("drivers7"), n("sessions1"), n("sessions7"))).font(.ui(12)).foregroundColor(Theme.muted)
            Text(t("admin_community", n("boards"), n("leagues"), (g["leaguesOpen"] as? Bool ?? false) ? t("admin_open") : t("admin_only"))).font(.ui(12)).foregroundColor(Theme.muted)
            Text(t("admin_sup", n("supporters"), n("supportersPatreon"), n("patrons"))).font(.ui(12)).foregroundColor(Theme.muted)
            Text(t("admin_model", n("learnt"), n("models")) + " · " + t("admin_dirty", n("modelsDirty"))).font(.ui(12)).foregroundColor(Theme.muted)
        }
        HStack(spacing: 6) {
            ForEach([7, 14, 30], id: \.self) { d in LiveChip(label: t("admin_days", "\(d)"), on: days == d) { days = d; Task { await load() } } }
        }
        if let an {
            analyticsView(an)
        } else {
            Panel { Text(t("admin_no_analytics")).font(.ui(12)).foregroundColor(Theme.muted) }
        }
    }

    @ViewBuilder private func analyticsView(_ an: [String: Any]) -> some View {
        let list = { (k: String) in an[k] as? [[String: Any]] ?? [] }
        Panel {
            Text(t("admin_active")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            if list("active").isEmpty { Text(t("admin_nothing")).font(.ui(12)).foregroundColor(Theme.muted) } else { AdminActiveChart(days: list("active")) }
        }
        Panel {
            Text(t("admin_devices")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            ForEach(Array(list("byDevice").enumerated()), id: \.offset) { _, d in useRow(d["device"] as? String ?? "", t("admin_use_n", "\(iv(d["n"]))", "\(iv(d["users"]))")) }
        }
        Panel {
            Text(t("admin_top")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            ForEach(Array(list("top").prefix(20).enumerated()), id: \.offset) { _, d in useRow(d["key"] as? String ?? "", t("admin_use_n", "\(iv(d["n"]))", "\(iv(d["users"]))")) }
        }
        Panel {
            Text(t("admin_games")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            ForEach(Array(list("games").enumerated()), id: \.offset) { _, d in
                let gm = d["game"] as? String ?? ""
                useRow(gm == "lmu" ? "Le Mans Ultimate" : gm == "iracing" ? "iRacing" : gm, t("admin_use_n", "\(iv(d["n"]))", "\(iv(d["users"]))"))
            }
        }
        Panel {
            Text(t("admin_versions")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
            ForEach(Array(list("versions").enumerated()), id: \.offset) { _, d in useRow(d["v"] as? String ?? "", t("admin_devices_n", "\(iv(d["devices"]))")) }
        }
    }

    private func useRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.mono(12)).foregroundColor(Theme.fg).lineLimit(1)
            Spacer()
            Text(value).font(.ui(12)).foregroundColor(Theme.muted)
        }
    }

    /// Server: the emails and the tools, each with the line that says what it does
    @ViewBuilder private func serverView(_ x: [String: Any]) -> some View {
        let m = x["mail"] as? [String: Any] ?? [:], c = x["counts"] as? [String: Any] ?? [:]
        let ready = m["ready"] as? Bool ?? false
        let g = x["config"] as? [String: Any] ?? [:]
        let pat = g["patreon"] as? Bool ?? false
        Text(t("admin_mail") + " · " + (ready ? t("admin_mail_ok") + " (" + (m["via"] as? String ?? "") + ")" : t("admin_mail_off"))).font(.ui(15, .bold)).foregroundColor(ready ? Theme.good : Theme.bad)
        Text(t("admin_mail_sub")).font(.ui(12)).foregroundColor(Theme.muted)
        Text(m["from"] as? String ?? "").font(.ui(12)).foregroundColor(Theme.muted)
        Text(t("admin_mail_last", dayTime((m["lastOk"] as? NSNumber)?.doubleValue ?? 0))).font(.ui(12)).foregroundColor(Theme.muted)
        if let e = m["lastError"] as? [String: Any] {
            Text(t("admin_mail_err") + " · " + ["message", "reply", "status", "body"].compactMap { e[$0].map { "\($0)" } }.filter { !$0.isEmpty }.joined(separator: " · ")).font(.ui(12)).foregroundColor(Theme.bad)
        }
        Text(pat ? t("admin_patreon_ok") : t("admin_patreon_off")).font(.ui(12)).foregroundColor(pat ? Theme.good : Theme.bad)
        // the tools: the coach models learn again, the blocked sign-ins open again
        Group {
            Divider().padding(.vertical, 4)
            Text(t("admin_tools_t")).font(.ui(15, .bold))
            Button(t("admin_rebuild")) { Task { try? await account.adminTool("models"); await load() } }.foregroundColor(Theme.accent).font(.ui(12, .bold))
            Text(t("admin_rebuild_sub")).font(.ui(12)).foregroundColor(Theme.muted)
            Button(t("admin_unlock", "\(iv(c["authFails"]))")) { Task { try? await account.adminTool("unlock"); await load() } }.foregroundColor(Theme.accent).font(.ui(12, .bold)).padding(.top, 4)
            Text(t("admin_unlock_sub")).font(.ui(12)).foregroundColor(Theme.muted)
        }
    }

    /// Coach: the totals and the confidence switch
    @ViewBuilder private func coachHead(_ x: [String: Any]) -> some View {
        let tot = x["totals"] as? [String: Any] ?? [:]
        let conf = x["confidence"] as? Bool ?? false
        Text(t("admin_coach_totals", "\(iv(tot["tips"]))", "\(iv(tot["scored"]))", "\(iv(tot["rated"]))", "\(iv(tot["drivers"]))", "\(iv(tot["week"]))")).font(.ui(12, .bold)).foregroundColor(Theme.fg)
        Toggle(t("admin_coach_conf"), isOn: Binding(get: { conf }, set: { on in Task { try? await account.adminCoachConfidence(on); await load() } })).font(.ui(15))
        Text(t("admin_coach_conf_sub")).font(.ui(12)).foregroundColor(Theme.muted)
        Text(t("admin_coach_off_sub")).font(.ui(12)).foregroundColor(Theme.muted).padding(.top, 4)
    }

    /// one bucket: a kind of tip on corners of one speed, its cases, gains and losses, the thumbs, and its off switch
    @ViewBuilder private func coachRow(_ b: [String: Any]) -> some View {
        let kind = b["kind"] as? String ?? "", cls = b["cls"] as? String ?? ""
        let off = Set(extra?["off"] as? [String] ?? [])
        let isOff = off.contains(kind + "|" + cls)
        let th = (extra?["ratings"] as? [String: Any])?[kind] as? [String: Any]
        let w = (b["w"] as? NSNumber)?.doubleValue ?? 1
        let title: String = kind + (cls.isEmpty ? "" : " · " + t("admin_coach_cls_" + cls)) + (isOff ? " · " + t("admin_coach_is_off") : "")
        let thumbs: String = th.map { " · 👍 \(iv($0["up"])) 👎 \(iv($0["down"]))" } ?? ""
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ui(15, .bold)).foregroundColor(isOff ? Theme.bad : Theme.fg)
                Text(t("admin_coach_line", "\(iv(b["n"]))", "\(iv(b["win"]))", "\(iv(b["loss"]))") + thumbs + String(format: " · w %.2f", w)).font(.ui(12)).foregroundColor(Theme.muted)
            }
            Spacer()
            if !cls.isEmpty {
                Button(t(isOff ? "admin_coach_on" : "admin_coach_off")) { Task { try? await account.adminCoachOff(kind, cls, !isOff); await load() } }
                    .foregroundColor(isOff ? Theme.accent : Theme.bad).font(.ui(12, .bold))
            }
        }
    }

    /// one piece of feedback: the stars, what was written, who, from which device, version and screen, and when
    @ViewBuilder private func feedbackRow(_ x: [String: Any]) -> some View {
        let r = iv(x["rating"])
        let who: String = ["nick", "display", "email"].compactMap { x[$0] as? String }.first { !$0.isEmpty } ?? "—"
        let at = (x["at"] as? NSNumber)?.doubleValue ?? (x["created"] as? NSNumber)?.doubleValue ?? 0
        let meta: String = ([who] + ["device", "v", "view"].compactMap { x[$0] as? String }.filter { !$0.isEmpty }).joined(separator: " · ") + " · " + dayTime(at)
        if (1...5).contains(r) { Text(String(repeating: "★", count: r) + String(repeating: "☆", count: 5 - r)).font(.ui(15)).foregroundColor(Theme.accent) }
        Text(x["text"] as? String ?? "").font(.ui(15)).foregroundColor(Theme.fg).textSelection(.enabled)
        Text(meta).font(.ui(11)).foregroundColor(Theme.muted)
        // the driver's thread with Support, to answer them there
        if let acc = x["accountId"] as? String, !acc.isEmpty {
            Button(t("sup_open_chat")) { account.openSupport(acc, nick: who) }.font(.ui(12, .bold)).foregroundColor(Theme.accent)
        }
    }

    @ViewBuilder private func sessionRow(_ x: [String: Any]) -> some View {
        let str = { (k: String) in x[k] as? String ?? "" }
        let int = { (k: String) in (x[k] as? NSNumber)?.intValue ?? 0 }
        Text(str("track") + (str("trackConfig").isEmpty ? "" : " · " + str("trackConfig"))).font(.ui(15, .bold)).foregroundColor(Theme.fg)
        Text(str("car") + " · " + kindText(str("kind")) + " · " + t("laps_n", int("laps"))).font(.ui(12)).foregroundColor(Theme.muted)
        Text(day((x["started"] as? NSNumber)?.doubleValue ?? 0) + " · " + str("who")).font(.ui(12)).foregroundColor(Theme.muted)
    }

    @ViewBuilder private func blockedRow(_ x: [String: Any]) -> some View {
        let str = { (k: String) in x[k] as? String ?? "" }
        let int = { (k: String) in (x[k] as? NSNumber)?.intValue ?? 0 }
        let a = x["account"] as? [String: Any], bl = x["blocked"] as? Bool ?? false
        let who: String = (a?["display"] as? String) ?? (x["net"] as? String) ?? "—"
        let title: String = str("kind") + " · " + who + (bl ? " · " + t("admin_is_blocked") : "")
        Text(title).font(.ui(15, .bold)).foregroundColor(bl ? Theme.bad : Theme.fg)
        Text(t("admin_tries", "\(int("n"))")).font(.ui(12)).foregroundColor(Theme.muted)
        Button(t("admin_unblock")) { Task { try? await account.adminUnlock("k", str("k")); await load() } }.foregroundColor(Theme.accent).font(.ui(12, .bold))
    }

    @ViewBuilder private func userRow(_ x: [String: Any]) -> some View {
        let str = { (k: String) in x[k] as? String ?? "" }
        // the DRINKS drivers joined to this account ("gid|name,…")
        let guestLinks: [String] = str("guestLinked").split(separator: ",").map { String($0.split(separator: "|").last ?? "") }.filter { !$0.isEmpty }
        let int = { (k: String) in (x[k] as? NSNumber)?.intValue ?? 0 }
        // the games whose driver is linked to this account ("iracing,lmu"; a server without it: iRacing's when linked)
        let driverGames: [String] = x["driverGames"] is String ? str("driverGames").split(separator: ",").map(String.init).filter { !$0.isEmpty } : (int("driverLinked") == 1 ? ["iracing"] : [])
        let ms0 = (x["memberSince"] as? NSNumber)?.doubleValue ?? 0, ms = ms0 > 0 ? ms0 : ((x["created"] as? NSNumber)?.doubleValue ?? 0)
        let name: String = str("display") + ((x["admin"] as? Bool ?? false) ? " · Admin" : "")
        Text(name).font(.ui(15, .bold)).foregroundColor(Theme.fg)
        Text(str("id")).font(.mono(11)).foregroundColor(Theme.muted).textSelection(.enabled)
        Text(t("admin_since", day(ms)) + (ms0 > 0 ? " ✎" : "")).font(.ui(12)).foregroundColor(Theme.muted)
        Text(t("admin_user_line", "\(int("sessions"))", "\(int("laps"))", "\(int("guests"))")).font(.ui(12)).foregroundColor(Theme.muted)
        // what it uses (the analytics): when it was last seen, its devices, its top features
        if let use = x["_use"] as? [String: Any] {
            let devs: String = (use["devices"] as? [String] ?? []).joined(separator: ", ")
            let seen: String = t("admin_last_seen", dayTime((use["lastSeen"] as? NSNumber)?.doubleValue ?? 0)) + (devs.isEmpty ? "" : " · " + devs) + " · " + t("admin_uses", "\(iv(use["n"]))")
            let top: String = (use["top"] as? [[String: Any]] ?? []).prefix(5).map { ($0["key"] as? String ?? "") + " \(iv($0["n"]))" }.joined(separator: " · ")
            Text(seen).font(.ui(12)).foregroundColor(Theme.accent)
            if !top.isEmpty { Text(top).font(.mono(11)).foregroundColor(Theme.muted) }
        }
        // help with an account: confirm its email, turn off its two-step sign-in, sign it out, rename it, unblock it
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 14) {
                if int("verified") != 1 { Button(t("admin_verify")) { Task { try? await account.adminAccount(str("id"), "verify"); await load() } } }
                if int("twoFactor") == 1 { Button(t("admin_2fa_off")) { Task { try? await account.adminAccount(str("id"), "2fa-off"); await load() } } }
                Button(t("admin_signout")) { Task { try? await account.adminAccount(str("id"), "signout"); await load() } }
                ForEach(driverGames, id: \.self) { g in Button(t(g == "lmu" ? "admin_unlink_driver_lmu" : "admin_unlink_driver")) { Task { try? await account.adminAccount(str("id"), "unlink-driver", name: g); await load() } } }
                Button(t("admin_rename")) { newName = str("display"); renaming = (str("id"), str("display")) }
                Button(t("admin_unblock")) { Task { try? await account.adminUnlock("account", str("id")); await load() } }
                Button(t("admin_link_guest")) { linkName = ""; linking = str("id") }
                ForEach(guestLinks, id: \.self) { g in Button(t("admin_unlink_guest", g)) { Task { try? await account.adminAccount(str("id"), "unlink-guest", name: g); await load() } } }
            }
            .foregroundColor(Theme.accent).font(.ui(12, .bold))
        }
        if !guestLinks.isEmpty { Text(t("admin_guest_linked", guestLinks.joined(separator: ", "))).font(.ui(12)).foregroundColor(Theme.accent) }
        HStack(spacing: 14) {
            NavigationLink(value: Route.profile("acct:" + str("id"))) { Text(t("profile")) }.foregroundColor(Theme.accent).font(.ui(12, .bold))
            Button(t("admin_set_since")) { since = SinceEdit(id: str("id"), date: Date(timeIntervalSince1970: ms / 1000), custom: ms0 > 0) }.foregroundColor(Theme.accent).font(.ui(12, .bold))
        }
        let sup = int("supporter") == 1
        let supLabel: String = (sup ? "♥ " + t("supporter_remove") : t("supporter_give")) + (sup && int("supporterHidden") == 1 ? " · " + t("supporter_hidden_by") : "")
        Button(supLabel) {
            Task { try? await account.adminSupporter(str("id"), !sup); await load() }
        }.foregroundColor(sup ? Color(red: 1, green: 0.56, blue: 0.75) : Theme.accent).font(.ui(12, .bold))
        if !(x["admin"] as? Bool ?? false) {
            Button(t("admin_delete_account")) { confirmDelete = (str("id"), str("display")) }.foregroundColor(Theme.bad).font(.ui(12, .bold))
        }
    }

    @ViewBuilder private func itemRow(_ x: [String: Any]) -> some View {
        let str = { (k: String) in x[k] as? String ?? "" }
        let int = { (k: String) in (x[k] as? NSNumber)?.intValue ?? 0 }
        Text(str("track") + " · " + str("car")).font(.ui(15, .bold)).foregroundColor(Theme.fg)
        Text((str("kind") == "laps" ? t("lap") : t("race")) + " · " + lapTime(x["time"] as? Double)).font(.ui(12)).foregroundColor(Theme.muted)
        Text(t("admin_shown_as", str("shownAs")) + (int("anon") == 1 ? " 🔒" : "")).font(.ui(12)).foregroundColor(Theme.fg)
        Text(t("admin_real", str("realUploader"))).font(.ui(12, .bold)).foregroundColor(Theme.fg)
        Button(t("delete")) {
            Task { try? await account.adminDelete(str("kind"), str("id")); await load() }
        }.foregroundColor(Theme.bad).font(.ui(12, .bold))
    }

    private func load() async {
        rows = nil
        extra = nil
        error = nil
        do {
            switch kind {
            case "summary":
                // the analytics may not be there yet (an older server): the key numbers still show
                extra = try await account.adminStatus()
                let an = try? await account.adminAnalytics(days)
                rows = an.map { [$0] } ?? []
            case "users":
                let use = ((try? await account.adminAnalytics(30))?["users"] as? [[String: Any]]) ?? []
                var byId: [String: [String: Any]] = [:]
                for u in use { if let id = u["id"] as? String { byId[id] = u } }
                rows = try await account.adminList("users").map { u -> [String: Any] in
                    var u = u
                    if let id = u["id"] as? String, let x = byId[id] { u["_use"] = x }
                    return u
                }
            case "feedback": rows = try await account.adminFeedback()
            case "content": rows = try await account.adminList("uploads")
            case "coach":
                let c = try await account.adminCoach()
                extra = c
                rows = (c["buckets"] as? [[String: Any]] ?? []).sorted { iv($0["n"]) > iv($1["n"]) }
            case "server":
                extra = try await account.adminStatus()
                rows = try await account.adminList("blocked")
            default: rows = try await account.adminList(kind)
            }
        } catch { self.error = (error as? AppError)?.key ?? "server_down" }
    }
}

/// Active users per day as bars: the finger picks a day and says its users under the chart.
struct AdminActiveChart: View {
    let days: [[String: Any]]
    @State private var sel: Int?
    var body: some View {
        let users: [Int] = days.map { ($0["users"] as? NSNumber)?.intValue ?? 0 }
        let n = users.count
        let hi = max(users.max() ?? 1, 1)
        let i = min(max(sel ?? n - 1, 0), max(n - 1, 0))
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(0..<n, id: \.self) { k in
                        RoundedRectangle(cornerRadius: 2).fill(k == i ? Theme.accent : Theme.accent.opacity(0.45))
                            .frame(maxWidth: .infinity)
                            .frame(height: max(1, g.size.height * CGFloat(users[k]) / CGFloat(hi)))
                    }
                }
                .frame(width: g.size.width, height: g.size.height, alignment: .bottom)
                .contentShape(Rectangle())
                .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { v in
                    sel = min(max(Int(v.location.x / max(g.size.width, 1) * CGFloat(n)), 0), max(n - 1, 0))
                })
            }
            .frame(height: 110)
            if n > 0 { Text((days[i]["day"] as? String ?? "") + " · \(users[i])").font(.ui(12, .bold)).foregroundColor(Theme.fg) }
        }
    }
}

struct DrinksView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var live: Live
    @State private var name = ""
    @State private var taken: String?
    @State private var editing: String?
    @State private var newName = ""
    @State private var forgetting: String?

    var body: some View {
        Screen(title: t("drinks")) {
            StatusPill(text: live.pcOnline ? t("pc_online") : live.link == .connecting ? t("connecting") : t("pc_offline"), color: live.pcOnline ? Theme.good : Theme.muted)
            if let m = live.message { Text(t(m)).font(.ui(12)).foregroundColor(Theme.bad) }
            Panel { Text(t("drinks_note")).font(.ui(12)).foregroundColor(Theme.muted) }
            if account.demo {
                EmptyNote(text: t("drinks_demo"))
            } else if let d = live.drinks {
                if !d.admin {
                    EmptyNote(text: t("drinks_pc_admin"))
                } else {
                    controls(d)
                }
            } else {
                EmptyNote(text: t("drinks_wait"))
            }
        }
        .onAppear { live.screens += 1; live.start(token: account.token, key: account.dataKey, demo: false) }
        .onDisappear { live.screens = max(0, live.screens - 1); live.startPresence(token: account.token, key: account.dataKey) }
        // change a name (the laps already shared change too) or take it off the list (they stay)
        .alert(t("drinks_rename"), isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
            TextField(t("drinks_name"), text: $newName)
            Button(t("save")) { rename() }
            Button(t("cancel"), role: .cancel) { editing = nil }
        } message: { Text(t("drinks_rename_note", editing ?? "")) }
        .alert(t("drinks_forget"), isPresented: Binding(get: { forgetting != nil }, set: { if !$0 { forgetting = nil } })) {
            Button(t("drinks_forget"), role: .destructive) { if let g = forgetting { live.forgetDrinksGuest(g) }; forgetting = nil }
            Button(t("cancel"), role: .cancel) { forgetting = nil }
        } message: { Text(t("drinks_forget_q", forgetting ?? "")) }
    }

    private func rename() {
        guard let from = editing else { return }
        editing = nil
        let n = String(newName.trimmingCharacters(in: .whitespaces).prefix(32))
        guard !n.isEmpty, n != from else { return }
        taken = nil
        let known = live.drinks?.guests ?? []
        if n.caseInsensitiveCompare(from) != .orderedSame && known.contains(where: { $0.caseInsensitiveCompare(n) == .orderedSame }) { taken = n; return }
        Task { if await account.nameFree(n) { live.renameDrinksGuest(from: from, to: n) } else { taken = n } }
    }

    @ViewBuilder private func controls(_ d: Drinks) -> some View {
        Panel {
            Toggle(t("drinks_on"), isOn: Binding(get: { d.on }, set: { live.setDrinks(on: $0, guest: d.guest, guestAuto: d.guestAuto) })).font(.ui(15, .bold))
            Text(t("drinks_now", d.driver.isEmpty ? t("you") : d.driver)).font(.ui(15, .bold)).foregroundColor(d.on ? Theme.accent : Theme.muted)
        }
        if d.on {
            Panel {
                Toggle(t("drinks_auto"), isOn: Binding(get: { d.guestAuto }, set: { live.setDrinks(on: true, guest: d.guest, guestAuto: $0) })).font(.ui(15))
                if !d.guestAuto {
                    if let n = taken { Text(t("name_taken_drinks", n)).font(.ui(12)).foregroundColor(Theme.bad) }
                    TextField(t("drinks_name"), text: $name).padding(10).background(Theme.surface2).clipShape(RoundedRectangle(cornerRadius: 6))
                    HStack(spacing: 8) {
                        Button(t("drinks_set")) {
                            let g = String(name.trimmingCharacters(in: .whitespaces).prefix(32))
                            name = ""
                            taken = nil
                            // a new name is checked first: names used by other people on Pitlane HQ are refused
                            if d.guests.contains(where: { $0.caseInsensitiveCompare(g) == .orderedSame }) {
                                live.setDrinks(on: true, guest: g, guestAuto: false)
                            } else {
                                Task { if await account.nameFree(g) { live.setDrinks(on: true, guest: g, guestAuto: false) } else { taken = g } }
                            }
                        }
                        .buttonStyle(.borderedProminent).foregroundColor(Theme.ink)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button(t("drinks_me")) { live.setDrinks(on: true, guest: "", guestAuto: false) }.buttonStyle(.bordered)
                    }
                }
            }
            if !d.guestAuto && !d.guests.isEmpty {
                SectionLabel(text: t("drinks_recent"))
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(d.guests, id: \.self) { g in
                            let sel = g.caseInsensitiveCompare(d.guest) == .orderedSame
                            Button { live.setDrinks(on: true, guest: g, guestAuto: false) } label: {
                                Text(g).font(.ui(15)).padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(sel ? Theme.accent : Theme.surface2).foregroundColor(sel ? Theme.ink : Theme.fg).clipShape(Capsule())
                            }
                        }
                    }
                }
                Panel {
                    ForEach(d.guests, id: \.self) { g in
                        HStack {
                            Text(g).font(.ui(15, .bold))
                            Spacer()
                            Button { editing = g; newName = g } label: { Image(systemName: "pencil") }.accessibilityLabel(t("drinks_rename")).foregroundColor(Theme.muted)
                            Button { forgetting = g } label: { Image(systemName: "xmark") }.accessibilityLabel(t("drinks_forget")).foregroundColor(Theme.muted).padding(.leading, 12)
                        }
                    }
                }
            }
        }
    }
}

// ---------- Settings ----------

struct SettingsView: View {
    @EnvironmentObject var account: Account
    @EnvironmentObject var i18n: I18n
    @State private var showMail = false
    @StateObject private var devices = Loader<[Device]>()

    private var version: String { (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "") + " beta" }

    var body: some View {
        Screen(title: t("account_tab")) {
            SectionLabel(text: t("account"))
            Panel {
                HStack(spacing: 6) { Text(account.display.isEmpty ? t("driver") : account.display).font(.ui(20, .black)).lineLimit(1); MyBadges() }
                HStack {
                    Text(showMail ? account.email : String(repeating: "•", count: min(14, max(8, account.email.count)))).font(.ui(12)).foregroundColor(Theme.muted)
                    Button(t(showMail ? "hide" : "show")) { showMail.toggle() }.font(.ui(12, .bold)).foregroundColor(Theme.accent)
                }
                Text(account.verified ? t("verified") : t("not_verified")).font(.ui(11)).foregroundColor(account.verified ? Theme.good : Theme.accent)
            }
            TwoFactorPanel()
            NavigationLink(value: Route.profile(nil)) { ActionRow(title: t("my_profile").uppercased(), sub: t("my_profile_sub"), icon: "person.crop.circle") }
                .buttonStyle(.plain)
            NavigationLink(value: Route.notes) { ActionRow(title: t("track_notes").uppercased(), sub: t("track_notes_sub"), icon: "note.text") }
                .buttonStyle(.plain)
            Link(destination: webApp) { ActionRow(title: t("web").uppercased(), sub: t("web_sub"), icon: "safari") }
            if let u = URL(string: patreonURL), !patreonURL.isEmpty {
                Link(destination: u) { ActionRow(title: t("support").uppercased(), sub: t("support_sub"), icon: "heart") }
            }
            SectionLabel(text: t("devices"))
            LoadState(loading: devices.loading, error: devices.error) { Task { await devices.load { try await account.devices() } } }
            ForEach(devices.data ?? []) { d in
                Panel {
                    HStack {
                        Image(systemName: d.device.localizedCaseInsensitiveContains("iphone") || d.device.localizedCaseInsensitiveContains("android") ? "iphone" : "desktopcomputer").foregroundColor(Theme.muted)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.current ? t("this_device") : (d.device.isEmpty ? "—" : d.device)).font(.ui(15, .bold))
                            Text(dayTime(d.lastSeen)).font(.ui(11)).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        if !d.current {
                            Button(t("sign_out_device")) { revoke(d.id) }.font(.ui(12)).foregroundColor(Theme.bad)
                        }
                    }
                }
            }
            if (devices.data?.count ?? 0) > 1 {
                Button(t("sign_out_others")) { revoke("others") }.foregroundColor(Theme.bad)
            }
            SectionLabel(text: t("notify_title"))
            NotifyPanel()
            SectionLabel(text: "DISCORD")
            DiscordPanel()
            SectionLabel(text: "STEAM")
            SteamPanel()
            SectionLabel(text: t("language"))
            Panel {
                ForEach(["system", "en", "es", "pt"], id: \.self) { k in
                    Button { i18n.choice = k } label: {
                        HStack {
                            Image(systemName: i18n.choice == k ? "largecircle.fill.circle" : "circle").foregroundColor(Theme.accent)
                            Text(k == "system" ? t("lang_system") : k == "en" ? "English" : k == "es" ? "Español" : "Português").foregroundColor(Theme.fg)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            // admins: the app as everyone sees it, to test it (everything for admins and in development hides)
            if account.realAdmin {
                Panel {
                    // admin mode, off by default (the app as everyone sees it); on, what is for admins and in development shows
                    Toggle(t("admin_mode"), isOn: $account.adminMode).font(.ui(15, .bold))
                    Text(t("admin_mode_sub")).font(.ui(12)).foregroundColor(Theme.muted)
                }
            }
            if account.admin {
                SectionLabel(text: t("admin_tools"))
                NavigationLink { AdminView() } label: { ActionRow(title: t("admin_profile").uppercased(), sub: t("admin_profile_sub"), icon: "person.badge.key") }
                    .buttonStyle(.plain)
                NavigationLink { DrinksView() } label: { ActionRow(title: t("drinks").uppercased(), sub: t("drinks_sub"), icon: "wineglass") }
                    .buttonStyle(.plain)
                Panel {
                    Toggle(t("demo_mode"), isOn: $account.demo).font(.ui(15, .bold))
                    Text(t("demo_note")).font(.ui(12)).foregroundColor(Theme.muted)
                }
            }
            Button {
                Task { await account.logout() }
            } label: {
                Text(t("sign_out").uppercased()).font(.ui(17, .bold)).frame(maxWidth: .infinity).padding(12)
                    .background(Theme.surface2).foregroundColor(Theme.bad).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if account.signedIn && !account.demo { DeleteAccountPanel() }
            Text(t("version", version)).font(.ui(11)).foregroundColor(Theme.muted)
        }
        .task { if devices.data == nil { await devices.load { try await account.devices() } } }
    }

    private func revoke(_ id: String) {
        Task {
            do { try await account.revoke(id) } catch { devices.error = (error as? AppError)?.key ?? error.localizedDescription }
            await devices.load { try await account.devices() }
        }
    }
}

/// One number with its label, for a row of three (the profile's leaderboards, records and podiums).
struct StatTile: View {
    let value: String
    let label: String
    var tint: Color = Theme.fg
    var body: some View {
        Panel {
            VStack(spacing: 2) {
                Text(value).font(.mono(20, .black)).foregroundColor(tint)
                Text(label).font(.ui(11)).foregroundColor(Theme.muted).multilineTextAlignment(.center).lineLimit(2)
            }.frame(maxWidth: .infinity)
        }
    }
}

/// Your notes on a track (the same the PC and the web keep): the general note, which you can write here, and the
/// corner notes made on the PC or the web.
struct TrackNotesPanel: View {
    @EnvironmentObject var account: Account
    let trackId: Int64
    let track: String
    @State private var editing = false
    @State private var text = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        let n = account.trackNotes[trackId]
        SectionLabel(text: t("my_notes"))
        Panel {
            if let n, !n.general.isEmpty { Text(n.general).font(.ui(15)).fixedSize(horizontal: false, vertical: true) }
            else if n == nil || n!.corners.isEmpty { Text(t("no_track_notes")).font(.ui(12)).foregroundColor(Theme.muted) }
            ForEach(n?.corners ?? [], id: \.self) { c in
                HStack(alignment: .top, spacing: 8) {
                    Text(c.name.isEmpty ? t("corner_n", c.n) : c.name).font(.ui(12, .bold)).foregroundColor(Theme.accent).frame(minWidth: 64, alignment: .leading)
                    Text(c.note).font(.ui(12)).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.top, 4)
            }
            Button(t(n?.general.isEmpty ?? true ? "write_note" : "edit_note")) { text = n?.general ?? ""; error = nil; editing = true }
                .font(.ui(12, .bold)).foregroundColor(Theme.accent).padding(.top, 6)
        }
        .onAppear { account.loadTrackNotes() }
        .sheet(isPresented: $editing) {
            NavigationStack {
                VStack(alignment: .leading, spacing: 10) {
                    Text(track).font(.ui(17, .semibold))
                    TextEditor(text: $text).scrollContentBackground(.hidden).frame(minHeight: 180).padding(6).background(Theme.surface).cornerRadius(10)
                    if let error { Text(error).font(.ui(12)).foregroundColor(Theme.bad) }
                    Spacer()
                }
                .padding()
                .background(Theme.bg.ignoresSafeArea())
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { editing = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(t("save")) {
                            saving = true
                            Task {
                                do { try await account.setTrackNote(trackId: trackId, track: track, general: text); editing = false }
                                catch { self.error = (error as? AppError)?.key ?? error.localizedDescription }
                                saving = false
                            }
                        }.disabled(saving)
                    }
                }
            }
        }
    }
}

/// Every track you wrote notes on, the newest first; each opens its track page (with the notes).
struct TrackNotesList: View {
    @EnvironmentObject var account: Account
    var body: some View {
        let all = account.trackNotes.values.sorted { $0.updated > $1.updated }
        Screen(title: t("track_notes")) {
            if all.isEmpty { EmptyNote(text: t("no_notes_any")) }
            ForEach(all) { n in
                NavigationLink(value: Route.track(TrackRef(id: n.trackId, name: n.track))) {
                    Panel {
                        Text(n.track.isEmpty ? "#\(n.trackId)" : n.track).font(.ui(15, .bold)).foregroundColor(Theme.fg).lineLimit(1)
                        Text(n.general.isEmpty ? t("corner_notes_n", n.corners.count) : n.general).font(.ui(12)).foregroundColor(Theme.muted).lineLimit(2)
                    }
                }.buttonStyle(.plain)
            }
        }
        .onAppear { account.loadTrackNotes() }
    }
}
