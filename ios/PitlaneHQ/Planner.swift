import SwiftUI

// The Planner (in development: admins with admin mode on, like the PC and the web). Home's Planner card opens it with two
// sub-tabs: Weeks (pick a week of the season, the starred series' tracks that week) and My season (each series' weeks,
// green where the account raced the track, and the tracks it has not raced). Both filter by discipline and licence and
// open the same week sheet and series page. Owned marks come from what the account raced (GET /api/sessions-owned).
// The same screens as Android's ui/Planner.kt.

private let goodFill = Color(red: 0x1D / 255, green: 0x4A / 255, blue: 0x33 / 255)
private let goodEdge = Color(red: 0x2B / 255, green: 0x6B / 255, blue: 0x48 / 255)
private let amberBg = Color(red: 0x2A / 255, green: 0x1F / 255, blue: 0x0A / 255)
private let amberEdge = Color(red: 0x5A / 255, green: 0x42 / 255, blue: 0x14 / 255)
private let btnEdge = Color(red: 0x33 / 255, green: 0x41 / 255, blue: 0x55 / 255)
private let LIC5 = ["R", "D", "C", "B", "A"]

func plNow() -> Double { Date().timeIntervalSince1970 * 1000 }
private func locale() -> Locale { Locale(identifier: I18n.shared.lang == "es" ? "es" : I18n.shared.lang == "pt" ? "pt_BR" : "en") }
private func fmt(_ t: Double, _ f: String) -> String { let d = DateFormatter(); d.locale = locale(); d.setLocalizedDateFormatFromTemplate(f); return d.string(from: Date(timeIntervalSince1970: t / 1000)) }
func plHm(_ t: Double) -> String { let d = DateFormatter(); d.locale = locale(); d.timeStyle = .short; d.dateStyle = .none; return d.string(from: Date(timeIntervalSince1970: t / 1000)) }
private func plDay(_ t: Double) -> String { fmt(t, "dMMM") }
private func plWeekday(_ t: Double) -> String { fmt(t, "EEE") }
private func plLongDay(_ t: Double) -> String { fmt(t, "EEEEdMMM") }
func plUntil(_ at: Double, _ now: Double = plNow()) -> String {
    let m = Int(((at - now) / 60_000).rounded())
    if m < 1 { return t("pl_now") }
    if m < 60 { return t("pl_in_min", m) }
    let h = m / 60
    if h < 24 { return m % 60 == 0 ? t("pl_in_h", h) : t("pl_in_hm", h, m % 60) }
    return t("pl_in_d", h / 24)
}
private func lenText(_ w: SWeek) -> String {
    if w.mins >= 120 && w.mins % 60 == 0 { return t("pl_hours", w.mins / 60) }
    if w.mins > 0 { return t("pl_minutes", w.mins) }
    if w.laps > 0 { return t("laps_n", w.laps) }
    return "–"
}
private func everyText(_ w: SWeek) -> String {
    if w.rep && w.every > 0 { return w.every % 60 == 0 ? t("pl_every_h", w.every / 60) : t("pl_every_min", w.every) }
    return w.times.isEmpty ? "" : t("pl_set_times", w.times.count)
}
/// "Okayama International Circuit" → "Okayama": the short name the cards show big.
private let SHORT = ["Circuit des 24 Heures du Mans": "Le Mans", "Autodromo Internazionale Enzo e Dino Ferrari": "Imola", "Circuit of the Americas": "COTA",
    "Autodromo Nazionale Monza": "Monza", "Circuit de Spa-Francorchamps": "Spa", "WeatherTech Raceway at Laguna Seca": "Laguna Seca", "Suzuka International Racing Course": "Suzuka",
    "Watkins Glen International": "Watkins Glen"]
func shortTrack(_ n: String) -> String {
    if let s = SHORT[n] { return s }
    var x = n.replacingOccurrences(of: "^\\[Legacy\\] ", with: "", options: .regularExpression)
    x = x.replacingOccurrences(of: "^(WeatherTech Raceway at|Circuito de|Circuit de|Mobility Resort|Motorsport Arena)\\s+", with: "", options: .regularExpression)
    return x.replacingOccurrences(of: "\\s+(International( Racing Course| Raceway| Circuit| Speedway)?|Circuit|Raceway|Motor Speedway|Speedway|Park|Racing Circuit)$", with: "", options: .regularExpression)
}
private func licLetter(_ g: Int) -> String { g >= 1 && g <= 5 ? LIC5[g - 1] : "R" }

/// The weeks of the season (most series share the same 12): those of the series that start the day most of them start.
private func seasonWeeks(_ d: SeasonData) -> [SWeek] {
    let g = Dictionary(grouping: d.series) { $0.weeks[0].start }.max { $0.value.count < $1.value.count }?.value ?? []
    return g.max { $0.weeks.count < $1.weeks.count }?.weeks ?? []
}
private func weekOf(_ s: SSeries, _ ref: SWeek) -> SWeek? { s.weeks.first { abs($0.start - ref.start) < 3 * Season.DAY } }

/// The season, loaded once for the Planner and its series pages.
@MainActor
final class PlannerStore: ObservableObject {
    static let shared = PlannerStore()
    let loader = Loader<SeasonData>()
    func load(_ a: Account) async { if loader.data == nil && !loader.loading { await loader.load { try await a.season() } } }
}

private struct WeekPick: Identifiable { let s: SSeries; let w: SWeek; var id: String { "\(s.id)-\(w.k)" } }

/// Home's door to the Planner: the next race in the plan, with "In development".
struct PlannerCard: View {
    @EnvironmentObject var account: Account
    var body: some View {
        let now = plNow()
        let p = account.plannerPlan.filter { $0.t > now }.min { $0.t < $1.t }
        NavigationLink(value: Route.planner) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(t("planner").uppercased()).font(.system(size: 12, weight: .black)).tracking(1.5).foregroundColor(Theme.accent)
                    Spacer()
                    Text(t("in_development")).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.accent)
                    Text("›").font(.title3).foregroundColor(Theme.muted)
                }
                if let p {
                    Text(p.name).font(.subheadline.bold()).foregroundColor(Theme.fg).lineLimit(1)
                    HStack(spacing: 0) {
                        Text("\(p.track) · \(plWeekday(p.t)) \(plHm(p.t)) · ").foregroundColor(Theme.muted).lineLimit(1)
                        Text(plUntil(p.t, now)).foregroundColor(Theme.accent).fontWeight(.semibold).lineLimit(1)
                    }.font(.caption)
                } else { Text(t("pl_no_plan")).font(.caption).foregroundColor(Theme.muted) }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [amberBg, Theme.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(amberEdge, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
        }.buttonStyle(.plain)
    }
}

private struct Own: View {
    let ok: Bool, label: String
    var body: some View { if ok { Text("✓ " + label).font(.system(size: 11, weight: .semibold)).foregroundColor(Theme.good).lineLimit(1) } }
}
private struct Pill: View {
    let s: String
    var body: some View {
        Text(s).font(.system(size: 11)).foregroundColor(Theme.muted).lineLimit(1).padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.line, lineWidth: 1))
    }
}
private struct PChip: View {
    let label: String, on: Bool, tap: () -> Void
    var body: some View {
        Button(action: tap) {
            Text(label).font(.system(size: 11, weight: .bold)).lineLimit(1).padding(.horizontal, 10).padding(.vertical, 5)
                .background(on ? Theme.accent : Theme.surface2).foregroundColor(on ? Theme.ink : Theme.muted).clipShape(Capsule())
        }.buttonStyle(.plain)
    }
}
private struct StarButton: View {
    @EnvironmentObject var account: Account
    let s: SSeries
    var body: some View {
        let on = account.plannerFav.contains(s.sid)
        Button { account.toggleStar(s.sid) } label: {
            Image(systemName: on ? "star.fill" : "star").font(.system(size: 17)).foregroundColor(on ? Theme.accent : Theme.muted).frame(width: 34, height: 34)
        }.buttonStyle(.plain)
    }
}
/// + / ✓: puts a race in the plan or takes it out.
private struct AddRound: View {
    @EnvironmentObject var account: Account
    let s: SSeries, at: Double
    var body: some View {
        let on = account.inPlan(s.sid, at)
        Button { account.togglePlan(s, at) } label: {
            Text(on ? "✓" : "+").font(.system(size: 16, weight: .black)).foregroundColor(on ? Theme.ink : Theme.fg).frame(width: 32, height: 32)
                .background(on ? Theme.accent : Theme.surface2).overlay(Circle().stroke(on ? Theme.accent : btnEdge, lineWidth: 1)).clipShape(Circle())
        }.buttonStyle(.plain)
    }
}
private struct AddButton: View {
    @EnvironmentObject var account: Account
    let s: SSeries, at: Double
    var body: some View {
        let on = account.inPlan(s.sid, at)
        Button { account.togglePlan(s, at) } label: {
            Text(on ? "✓ " + t("pl_in_plan") : "+ " + t("pl_plan")).font(.system(size: 12, weight: .bold)).lineLimit(1).foregroundColor(on ? Theme.ink : Theme.fg)
                .padding(.horizontal, 10).padding(.vertical, 6).background(on ? Theme.accent : Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(on ? Theme.accent : btnEdge, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
        }.buttonStyle(.plain)
    }
}
private struct TimeChip: View {
    @EnvironmentObject var account: Account
    let s: SSeries, at: Double, label: String
    var body: some View {
        let on = account.inPlan(s.sid, at)
        Button { account.togglePlan(s, at) } label: {
            Text(label).font(.system(size: 12, weight: .bold, design: .monospaced)).lineLimit(1).foregroundColor(on ? Theme.ink : Theme.fg)
                .padding(.horizontal, 9).padding(.vertical, 6).background(on ? Theme.accent : Theme.surface2)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(on ? Theme.accent : Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }
}

/// The account's sessions at a track, newest first, with their Race, Qualifying or Practice badge.
private struct YouHere: View {
    @EnvironmentObject var account: Account
    let track: String
    @State private var sessions: [CloudSession]? = nil
    var body: some View {
        Group {
            let here = (sessions ?? []).filter { $0.game == "iracing" && sameTrack($0.track, track) }.prefix(5)
            if here.isEmpty { Text(t("pl_no_sessions_here")).font(.subheadline).foregroundColor(Theme.muted) }
            else {
                Panel {
                    ForEach(Array(here.enumerated()), id: \.offset) { i, x in
                        if i > 0 { Divider().overlay(Theme.line).padding(.vertical, 4) }
                        HStack(spacing: 8) {
                            KindTag(kind: x.kind)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.car).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.fg).lineLimit(1)
                                Text(plDay(x.started) + " · " + (x.pos != nil ? x.place : t("laps_n", x.laps))).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                            }
                            Spacer()
                            Text(lapTime(x.best)).font(.system(size: 13, design: .monospaced)).foregroundColor(Theme.fg)
                        }
                    }
                }
            }
        }
        .task { if sessions == nil, account.game == "iracing" { sessions = (try? await account.sessions())?.data ?? [] } }
    }
}

/// The filters both sub-tabs share: All series (else the starred ones), the disciplines and the licences.
private struct Filters: View {
    @Binding var allS: Bool
    @Binding var cat: String
    @Binding var lic: Int
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    PChip(label: t("pl_all_series"), on: allS) { allS.toggle() }
                    ForEach(DISCS, id: \.self) { k in PChip(label: discName(k), on: cat == k) { cat = cat == k ? "" : k } }
                }
            }
            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { g in
                    Button { lic = lic == g ? 0 : g } label: {
                        LicBadge(k: licLetter(g)).padding(.horizontal, 9).padding(.vertical, 5).background(lic == g ? amberBg : Theme.surface2)
                            .overlay(Capsule().stroke(lic == g ? Theme.accent : Theme.line, lineWidth: 1)).clipShape(Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

struct PlannerView: View {
    @EnvironmentObject var account: Account
    @ObservedObject private var store = PlannerStore.shared.loader
    @State private var tab = 0
    @State private var allS: Bool? = nil
    @State private var cat = ""
    @State private var lic = 0
    @State private var wk = -1
    @State private var pick: WeekPick? = nil
    @State private var openS: SSeries? = nil

    var body: some View {
        let now = plNow()
        Screen(title: t("planner")) {
            Text(t("in_development")).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.accent)
            Tabs(labels: [t("pl_weeks"), t("pl_my_season")], selected: $tab)
            if let d = store.data {
                let all = allS ?? account.plannerFav.isEmpty
                let allB = Binding(get: { all }, set: { allS = $0 })
                let pool = (all ? d.series : d.series.filter { account.plannerFav.contains($0.sid) })
                    .filter { (cat.isEmpty || Season.cat($0, now) == cat) && (lic == 0 || $0.lic == lic) }
                let empty = t(!all && account.plannerFav.isEmpty ? "pl_star_some" : "pl_no_match")
                if tab == 0 { weeksTab(d, pool, allB, empty, now) } else { seasonTab(d, pool, allB, empty, now) }
            } else if store.loading { ProgressView().tint(Theme.accent).frame(maxWidth: .infinity).padding(.top, 30) }
            else if let e = store.error {
                Text(t(e)).font(.caption).foregroundColor(Theme.bad)
                Button(t("retry")) { Task { await PlannerStore.shared.load(account) } }.foregroundColor(Theme.accent)
            }
        }
        .task { Usage.count("view:planner"); await PlannerStore.shared.load(account) }
        .sheet(item: $pick) { p in
            WeekSheet(d: store.data, s: p.s, w: p.w) { pick = nil; DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { openS = p.s } }.environmentObject(account)
        }
        .navigationDestination(isPresented: Binding(get: { openS != nil }, set: { if !$0 { openS = nil } })) { if let s = openS { PlannerSeriesView(s: s) } }
    }

    @ViewBuilder private func weeksTab(_ d: SeasonData, _ pool: [SSeries], _ allB: Binding<Bool>, _ empty: String, _ now: Double) -> some View {
        let weeks = seasonWeeks(d)
        let cw = max(0, weeks.firstIndex { now >= $0.start && now < $0.end } ?? 0)
        let k = weeks.indices.contains(wk) ? wk : cw
        ScrollViewReader { sp in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(weeks.enumerated()), id: \.offset) { i, w in
                        let on = i == k
                        Button { wk = i } label: {
                            VStack(spacing: 1) {
                                Text(t("pl_week").uppercased()).font(.system(size: 9, design: .monospaced)).foregroundColor(on ? Theme.ink : Theme.muted)
                                Text("\(i + 1)").font(.system(size: 18, weight: .black)).foregroundColor(on ? Theme.ink : Theme.fg)
                                Text(plDay(w.start)).font(.system(size: 9, design: .monospaced)).foregroundColor(on ? Theme.ink : Theme.muted).lineLimit(1)
                            }
                            .frame(width: 58).padding(.vertical, 7).background(on ? Theme.accent : Theme.surface)
                            .overlay(RoundedRectangle(cornerRadius: 12).stroke(on || i == cw ? Theme.accent : Theme.line, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 12))
                            .opacity(w.end < now && !on ? 0.5 : 1)
                        }.buttonStyle(.plain).id(i)
                    }
                }
            }
            .onAppear { sp.scrollTo(max(0, cw - 1), anchor: .leading) }
        }
        let ref = weeks.indices.contains(k) ? weeks[k] : nil
        let rows: [(SSeries, SWeek)] = ref.map { r in pool.compactMap { s in weekOf(s, r).map { (s, $0) } } } ?? []
        HStack(spacing: 8) {
            Metric(label: t("pl_series"), value: "\(rows.count)")
            Metric(label: t("pl_on_raced"), value: "\(rows.filter { Season.ownTrack(d, $0.1) }.count)", color: Theme.good)
        }
        Filters(allS: allB, cat: $cat, lic: $lic)
        if let ref { Text(plDay(ref.start) + " – " + plDay(ref.end - 1)).font(.caption).foregroundColor(Theme.muted) }
        if rows.isEmpty { EmptyNote(text: empty) }
        ForEach(rows, id: \.0.id) { s, w in
            NavigationLink(value: Route.plannerSeries(s)) {
                Panel {
                    HStack(spacing: 6) {
                        LicBadge(k: licLetter(s.lic))
                        Text(s.name).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                        Spacer()
                        StarButton(s: s)
                    }
                    Text(shortTrack(w.track).uppercased()).font(.system(size: 19, weight: .black)).foregroundColor(Theme.fg).lineLimit(1)
                    Text(w.cfg.isEmpty ? w.track : w.cfg).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                    HStack(spacing: 5) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                Own(ok: Season.ownTrack(d, w), label: t("pl_track"))
                                Pill(s: lenText(w))
                                if !everyText(w).isEmpty { Pill(s: everyText(w)) }
                                Pill(s: t("pl_rain", w.rain))
                            }
                        }
                        Button { pick = WeekPick(s: s, w: w) } label: {
                            Text(t(w.end < now ? "pl_done" : "pl_times")).font(.system(size: 12, weight: .bold)).foregroundColor(Theme.fg).lineLimit(1)
                                .padding(.horizontal, 10).padding(.vertical, 6).background(Theme.surface2)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(btnEdge, lineWidth: 1)).clipShape(RoundedRectangle(cornerRadius: 10))
                        }.buttonStyle(.plain)
                    }.padding(.top, 6)
                }
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder private func seasonTab(_ d: SeasonData, _ pool: [SSeries], _ allB: Binding<Bool>, _ empty: String, _ now: Double) -> some View {
        Filters(allS: allB, cat: $cat, lic: $lic)
        if pool.isEmpty { EmptyNote(text: empty) }
        ForEach(pool, id: \.id) { s in
            let rem = s.weeks.filter { $0.end > now }
            let can = rem.filter { Season.ownTrack(d, $0) }.count
            let cw = Season.curWeek(s, now)
            Panel {
                NavigationLink(value: Route.plannerSeries(s)) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(s.name).font(.subheadline.bold()).foregroundColor(Theme.fg).lineLimit(1)
                            Text(t("pl_can_race", can, rem.count)).font(.caption).foregroundColor(Theme.muted)
                        }
                        Spacer()
                        Text("\(can)").font(.system(size: 26, weight: .black)).foregroundColor(can > 0 ? Theme.good : Theme.muted)
                        Text("/\(rem.count)").font(.system(size: 16, weight: .black)).foregroundColor(Theme.muted)
                    }
                }.buttonStyle(.plain)
                HStack(spacing: 3) {
                    ForEach(Array(s.weeks.enumerated()), id: \.offset) { _, w in
                        let own = Season.ownTrack(d, w), cur = w === cw
                        RoundedRectangle(cornerRadius: 4).fill(own ? goodFill : Theme.bg).frame(height: 22)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(cur ? Theme.accent : own ? goodEdge : Theme.line, lineWidth: cur ? 2 : 1))
                            .opacity(w.end < now ? 0.35 : 1).frame(maxWidth: .infinity)
                            .onTapGesture { pick = WeekPick(s: s, w: w) }
                    }
                }.padding(.vertical, 6)
                HStack(spacing: 8) {
                    Text(t("pl_this_week", cw.map { shortTrack($0.track) } ?? "–")).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                    Spacer()
                    if let n = Season.nextRace(s, now) {
                        Text(plHm(n.0)).font(.system(size: 13, weight: .bold, design: .monospaced)).foregroundColor(Theme.accent)
                        AddRound(s: s, at: n.0)
                    }
                }
            }
        }
        // the tracks the account has not raced, by how many of the remaining weeks they bring
        let top = missing(d, pool, now)
        if !top.isEmpty {
            HStack { SectionLabel(text: t("pl_not_raced").uppercased()); Spacer(); Text(t("pl_weeks_they_bring")).font(.system(size: 11)).foregroundColor(Theme.muted) }
            Panel {
                ForEach(Array(top.enumerated()), id: \.offset) { i, e in
                    if i > 0 { Divider().overlay(Theme.line).padding(.vertical, 4) }
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(e.0).font(.system(size: 13, weight: .semibold)).foregroundColor(Theme.fg).lineLimit(1)
                            Text(e.2.joined(separator: ", ")).font(.caption).foregroundColor(Theme.muted).lineLimit(1)
                        }
                        Spacer()
                        Text("\(e.1)").font(.system(.body, design: .monospaced).bold()).foregroundColor(Theme.fg)
                    }
                }
            }
        }
    }

    private func missing(_ d: SeasonData, _ pool: [SSeries], _ now: Double) -> [(String, Int, [String])] {
        var m: [String: (Int, [String])] = [:]
        for s in pool { for w in s.weeks where w.end > now && !Season.ownTrack(d, w) {
            var e = m[w.track] ?? (0, []); e.0 += 1; if !e.1.contains(s.name) { e.1.append(s.name) }; m[w.track] = e } }
        return m.map { ($0.key, $0.value.0, $0.value.1) }.sorted { $0.1 > $1.1 }.prefix(6).map { $0 }
    }
}

/// One week of one series: its track, the ticks, the length, the race times to tap into the plan and "You here".
private struct WeekSheet: View {
    @EnvironmentObject var account: Account
    @Environment(\.dismiss) private var dismiss
    let d: SeasonData?, s: SSeries, w: SWeek
    var onOpen: (() -> Void)? = nil
    var body: some View {
        let now = plNow()
        ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text((s.name + " · " + t("pl_week") + " \(w.k + 1)").uppercased()).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted).lineLimit(1)
                    Text(w.track.uppercased()).font(.system(size: 22, weight: .black)).foregroundColor(Theme.fg)
                    Text((w.cfg.isEmpty ? "" : w.cfg + " · ") + plDay(w.start) + " – " + plDay(w.end - 1)).font(.caption).foregroundColor(Theme.muted)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            if let d { Own(ok: Season.ownTrack(d, w), label: t("pl_track")); Own(ok: Season.ownCar(d, s, w), label: t("pl_car")) }
                            Pill(s: lenText(w))
                            if !everyText(w).isEmpty { Pill(s: everyText(w)) }
                            Pill(s: t("pl_rain", w.rain))
                        }
                    }
                    if w.end < now { Text(t("pl_week_over")).font(.subheadline).foregroundColor(Theme.muted) }
                    else {
                        let ts = Array(Season.starts(w, max(now, w.start), w.end).prefix(24))
                        SectionLabel(text: t("pl_races").uppercased())
                        if ts.isEmpty { Text(t("pl_no_more")).font(.subheadline).foregroundColor(Theme.muted) }
                        else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(ts, id: \.self) { tm in TimeChip(s: s, at: tm, label: (w.start > now + Season.DAY ? plWeekday(tm) + " " : "") + plHm(tm)) }
                                }
                            }
                        }
                    }
                    SectionLabel(text: t("pl_you_here").uppercased())
                    YouHere(track: w.track)
                    if let onOpen {
                        Button(action: onOpen) {
                            Text(t("pl_open_series", s.name)).font(.subheadline).foregroundColor(Theme.fg).lineLimit(1).frame(maxWidth: .infinity).padding(.vertical, 10)
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(16)
        }
        .background(Theme.surface.ignoresSafeArea())
        .presentationDetents([.large])
    }
}

/// A series: this week, the next three days of race times, the cars, the account at this week's track and the season.
struct PlannerSeriesView: View {
    @EnvironmentObject var account: Account
    @ObservedObject private var store = PlannerStore.shared.loader
    let s: SSeries
    @State private var pick: WeekPick? = nil
    var body: some View {
        let d = store.data
        let now = plNow()
        let w = Season.curWeek(s, now) ?? s.weeks.first { $0.start > now } ?? s.weeks[0]
        let wi = s.weeks.firstIndex { $0 === w } ?? 0
        let next = Array(s.weeks.flatMap { Season.starts($0, now, now + 3 * Season.DAY) }.sorted().prefix(24))
        let rem = s.weeks.filter { $0.end > now }
        Screen(title: s.name) {
            HStack(spacing: 6) {
                StarButton(s: s); LicBadge(k: licLetter(s.lic))
                Pill(s: discName(Season.cat(s, now)))
                Pill(s: t(s.fixed ? "pl_fixed" : "pl_open"))
                if s.multi { Pill(s: t("pl_multiclass")) }
            }
            if !s.desc.isEmpty { Text(s.desc).font(.caption).foregroundColor(Theme.muted) }
            Panel {
                Text(t("pl_this_week_n", wi + 1, s.weeks.count).uppercased()).font(.system(size: 10, design: .monospaced)).foregroundColor(Theme.muted)
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(w.track.uppercased()).font(.system(size: 20, weight: .black)).foregroundColor(Theme.fg)
                        if !w.cfg.isEmpty { Text(w.cfg).font(.caption).foregroundColor(Theme.muted) }
                    }
                    Spacer()
                    if let d { VStack(alignment: .trailing) { Own(ok: Season.ownTrack(d, w), label: t("pl_track")); Own(ok: Season.ownCar(d, s, w), label: t("pl_car")) } }
                }.padding(.bottom, 6)
                InfoRow(label: t("pl_length"), value: lenText(w))
                InfoRow(label: t("pl_sessions"), value: everyText(w).isEmpty ? "–" : everyText(w))
                InfoRow(label: t("pl_rain_l"), value: "\(w.rain)%")
                InfoRow(label: t("pl_inc_limit"), value: s.inc > 0 ? "\(s.inc)" : "–")
                InfoRow(label: t("pl_drops"), value: "\(s.drops)")
            }
            HStack { SectionLabel(text: t("pl_next_3").uppercased()); Spacer(); Text(t("pl_your_time")).font(.system(size: 11)).foregroundColor(Theme.muted) }
            Panel {
                if next.isEmpty { Text(t("pl_none_3")).font(.subheadline).foregroundColor(Theme.muted) }
                ForEach(Array(next.enumerated()), id: \.offset) { i, tm in
                    if i == 0 || plLongDay(next[i - 1]) != plLongDay(tm) {
                        Text(plLongDay(tm).uppercased()).font(.system(size: 10, weight: .bold, design: .monospaced)).foregroundColor(Theme.muted).padding(.top, i > 0 ? 8 : 0)
                    }
                    HStack {
                        Text(plHm(tm)).font(.system(.body, design: .monospaced).bold()).foregroundColor(Theme.fg).frame(width: 64, alignment: .leading)
                        Text(plUntil(tm, now)).font(.caption).foregroundColor(Theme.muted)
                        Spacer()
                        AddButton(s: s, at: tm)
                    }.padding(.vertical, 2)
                }
            }
            if let d {
                let cars = Season.carsOf(s, w)
                if !cars.isEmpty {
                    SectionLabel(text: t("pl_cars").uppercased())
                    Panel {
                        ForEach(Array(cars.prefix(10)), id: \.self) { c in
                            HStack {
                                Text(d.cars[c] ?? "–").font(.system(size: 13)).foregroundColor(Theme.fg).lineLimit(1)
                                Spacer()
                                Own(ok: d.racedCars.contains(c), label: t("pl_raced"))
                            }.padding(.vertical, 2)
                        }
                        if cars.count > 10 { Text(t("pl_more", cars.count - 10)).font(.caption).foregroundColor(Theme.muted) }
                    }
                }
            }
            SectionLabel(text: t("pl_you_at", shortTrack(w.track)).uppercased())
            YouHere(track: w.track)
            HStack {
                SectionLabel(text: t("pl_schedule").uppercased()); Spacer()
                if let d { Text(t("pl_can_race", rem.filter { Season.ownTrack(d, $0) }.count, rem.count)).font(.system(size: 11)).foregroundColor(Theme.muted) }
            }
            Panel {
                ForEach(Array(s.weeks.enumerated()), id: \.offset) { i, x in
                    Button { pick = WeekPick(s: s, w: x) } label: {
                        HStack {
                            Text("\(i + 1)").font(.system(.body, design: .monospaced)).foregroundColor(Theme.muted).frame(width: 24, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(x.track).font(.system(size: 13, weight: x === w ? .bold : .regular)).foregroundColor(Theme.fg).lineLimit(1)
                                Text(plDay(x.start) + " · " + lenText(x)).font(.caption).foregroundColor(Theme.muted)
                            }
                            Spacer()
                            if let d { Own(ok: Season.ownTrack(d, x), label: "") }
                        }
                        .padding(.vertical, 6).padding(.horizontal, 4).frame(maxWidth: .infinity, alignment: .leading)
                        .background(x === w ? amberBg : Color.clear).clipShape(RoundedRectangle(cornerRadius: 8)).opacity(x.end < now ? 0.45 : 1)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
        }
        .task { await PlannerStore.shared.load(account) }
        .sheet(item: $pick) { p in WeekSheet(d: store.data, s: p.s, w: p.w).environmentObject(account) }
    }
}
