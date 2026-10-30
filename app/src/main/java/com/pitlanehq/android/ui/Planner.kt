package com.pitlanehq.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.outlined.StarOutline
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.pitlanehq.android.data.*
import com.pitlanehq.android.model.CloudSession
import com.pitlanehq.android.viewmodel.PitlaneViewModel
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.Locale

/* The Planner (in development: admins with admin mode on, like the PC and the web). Home's Planner card opens it with two
 * sub-tabs: Weeks (pick a week of the season, the starred series' tracks that week) and My season (each series' 12 weeks,
 * green where the account raced the track, and the tracks it has not raced). Both filter by discipline and licence and
 * open the same week sheet and series page. Owned marks come from what the account raced (GET /api/sessions-owned). */

private val GoodBg = Color(0xFF12291F)
private val GoodEdge = Color(0xFF245A3C)
private val LIC5 = listOf("R", "D", "C", "B", "A")
private const val HOUR = 3_600_000L

private fun locale(): Locale = Locale.forLanguageTag(when (I18n.lang) { "es" -> "es"; "pt" -> "pt-BR"; else -> "en" })
private fun zdt(t: Long) = Instant.ofEpochMilli(t).atZone(ZoneId.systemDefault())
internal fun plHm(t: Long): String = DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT).withLocale(locale()).format(zdt(t))
private fun plDay(t: Long): String = DateTimeFormatter.ofPattern("d MMM", locale()).format(zdt(t))
private fun plWeekday(t: Long): String = DateTimeFormatter.ofPattern("EEE", locale()).format(zdt(t))
private fun plLongDay(t: Long): String = DateTimeFormatter.ofPattern("EEEE d MMM", locale()).format(zdt(t))
internal fun plUntil(t: Long, now: Long = System.currentTimeMillis()): String {
    val m = Math.round((t - now) / 60_000.0)
    if (m < 1) return t("pl_now")
    if (m < 60) return t("pl_in_min", m)
    val h = m / 60
    if (h < 24) return if (m % 60 == 0L) t("pl_in_h", h) else t("pl_in_hm", h, m % 60)
    return t("pl_in_d", h / 24)
}
private fun lenText(w: SWeek): String = when {
    w.mins >= 120 && w.mins % 60 == 0 -> t("pl_hours", w.mins / 60)
    w.mins > 0 -> t("pl_minutes", w.mins)
    w.laps > 0 -> t("laps_n", w.laps)
    else -> "–"
}
private fun everyText(w: SWeek): String = when {
    w.rep && w.every > 0 -> if (w.every % 60 == 0) t("pl_every_h", w.every / 60) else t("pl_every_min", w.every)
    w.times.isNotEmpty() -> t("pl_set_times", w.times.size)
    else -> ""
}
/** "Okayama International Circuit" → "Okayama": the short name the cards show big. */
private val SHORT = mapOf("Circuit des 24 Heures du Mans" to "Le Mans", "Autodromo Internazionale Enzo e Dino Ferrari" to "Imola", "Circuit of the Americas" to "COTA",
    "Autodromo Nazionale Monza" to "Monza", "Circuit de Spa-Francorchamps" to "Spa", "WeatherTech Raceway at Laguna Seca" to "Laguna Seca", "Suzuka International Racing Course" to "Suzuka",
    "Watkins Glen International" to "Watkins Glen")
internal fun shortTrack(n: String): String = SHORT[n] ?: n.replace(Regex("^\\[Legacy\\] "), "")
    .replace(Regex("^(WeatherTech Raceway at|Circuito de|Circuit de|Mobility Resort|Motorsport Arena)\\s+"), "")
    .replace(Regex("\\s+(International( Racing Course| Raceway| Circuit| Speedway)?|Circuit|Raceway|Motor Speedway|Speedway|Park|Racing Circuit)$"), "")
private fun licLetter(g: Int) = LIC5.getOrElse(g - 1) { "R" }

/** The weeks of the season (most series share the same 12): those of the series that start the day most of them start. */
private fun seasonWeeks(d: SeasonData): List<SWeek> = d.series.groupBy { it.weeks[0].start }.maxByOrNull { it.value.size }?.value?.maxByOrNull { it.weeks.size }?.weeks ?: emptyList()
private fun weekOf(s: SSeries, ref: SWeek): SWeek? = s.weeks.firstOrNull { Math.abs(it.start - ref.start) < 3 * Season.DAY }

/** Home's door to the Planner: the next race in the plan, with "In development". */
@Composable
fun PlannerCard(vm: PitlaneViewModel, nav: NavHostController) {
    val plan by vm.plannerPlan.collectAsState()
    val now = System.currentTimeMillis()
    val p = plan.filter { it.t > now }.minByOrNull { it.t }
    Card(
        Modifier.fillMaxWidth().clickable { nav.navigate("planner") }, colors = CardDefaults.cardColors(containerColor = Color.Transparent),
        border = BorderStroke(1.dp, Color(0xFF5A4214)), shape = RoundedCornerShape(12.dp)
    ) {
        Column(Modifier.background(Brush.linearGradient(listOf(Color(0xFF2A1F0A), Surface))).padding(12.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(t("planner").uppercase(), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Black, letterSpacing = 1.5.sp, modifier = Modifier.weight(1f))
                Text(t("in_development"), color = Accent, fontFamily = FontFamily.Monospace, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                Text("  ›", color = Muted, fontSize = 18.sp)
            }
            if (p != null) {
                Text(p.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row {
                    Text("${p.track} · ${plWeekday(p.t)} ${plHm(p.t)} · ", color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, false))
                    Text(plUntil(p.t, now), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                }
            } else Text(t("pl_no_plan"), color = Muted, fontSize = 12.sp)
        }
    }
}

@Composable
private fun Own(ok: Boolean, label: String) {
    if (ok) Text("✓ $label", color = Good, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
}
@Composable
private fun Pill(s: String) {
    Text(s, color = Muted, fontSize = 11.sp, maxLines = 1, modifier = Modifier.border(1.dp, Line, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 1.dp))
}
@Composable
private fun StarButton(vm: PitlaneViewModel, s: SSeries) {
    val fav by vm.plannerFav.collectAsState()
    val on = s.sid in fav
    IconButton({ vm.toggleStar(s.sid) }, Modifier.size(34.dp)) {
        Icon(if (on) Icons.Filled.Star else Icons.Outlined.StarOutline, t("pl_star"), tint = if (on) Accent else Muted, modifier = Modifier.size(20.dp))
    }
}
/** + / ✓: puts a race in the plan or takes it out. */
@Composable
private fun AddRound(vm: PitlaneViewModel, s: SSeries, t: Long) {
    val plan by vm.plannerPlan.collectAsState()
    val on = plan.any { it.sid == s.sid && it.t == t }
    Box(
        Modifier.size(32.dp).clip(CircleShape).background(if (on) Accent else Surface2).border(1.dp, if (on) Accent else Color(0xFF334155), CircleShape).clickable { vm.togglePlan(s, t) },
        contentAlignment = Alignment.Center
    ) { Text(if (on) "✓" else "+", color = if (on) Ink else Fg, fontWeight = FontWeight.Black, fontSize = 16.sp) }
}
@Composable
private fun AddButton(vm: PitlaneViewModel, s: SSeries, t: Long) {
    val plan by vm.plannerPlan.collectAsState()
    val on = plan.any { it.sid == s.sid && it.t == t }
    Text(
        if (on) "✓ " + t("pl_in_plan") else "+ " + t("pl_plan"), fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (on) Ink else Fg, maxLines = 1,
        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(if (on) Accent else Surface2).border(1.dp, if (on) Accent else Color(0xFF334155), RoundedCornerShape(10.dp))
            .clickable { vm.togglePlan(s, t) }.padding(horizontal = 10.dp, vertical = 6.dp)
    )
}
@Composable
private fun TimeChip(vm: PitlaneViewModel, s: SSeries, t: Long, label: String) {
    val plan by vm.plannerPlan.collectAsState()
    val on = plan.any { it.sid == s.sid && it.t == t }
    Text(
        label, fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, color = if (on) Ink else Fg, maxLines = 1,
        modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (on) Accent else Surface2).border(1.dp, if (on) Accent else Line, RoundedCornerShape(8.dp))
            .clickable { vm.togglePlan(s, t) }.padding(horizontal = 9.dp, vertical = 6.dp)
    )
}

/** The account's sessions at a track, newest first, with their Race, Qualifying or Practice badge. */
@Composable
private fun YouHere(vm: PitlaneViewModel, track: String) {
    val sl by vm.sessions.collectAsState()
    LaunchedEffect(Unit) { if (sl.data == null && !sl.loading) vm.loadSessions() }
    val here = (sl.data ?: emptyList()).filter { it.game == "iracing" && sameTrack(it.track, track) }.take(5)
    if (here.isEmpty()) { Text(t("pl_no_sessions_here"), color = Muted, fontSize = 13.sp); return }
    Panel {
        here.forEachIndexed { i, x: CloudSession ->
            if (i > 0) HorizontalDivider(color = Line, modifier = Modifier.padding(vertical = 8.dp))
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                KindTag(x.kind)
                Column(Modifier.weight(1f)) {
                    Text(x.car, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(plDay(x.started) + if (x.pos != null) " · " + x.place else " · " + t("laps_n", x.laps), color = Muted, fontSize = 12.sp, maxLines = 1)
                }
                Text(com.pitlanehq.android.model.lapTime(x.best), fontFamily = FontFamily.Monospace, fontSize = 13.sp)
            }
        }
    }
}

/** The filters both sub-tabs share: All series (else the starred ones), the disciplines and the licences. */
@Composable
private fun Filters(allS: Boolean, cat: String, lic: Int, onAll: () -> Unit, onCat: (String) -> Unit, onLic: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(t("pl_all_series"), allS, onAll)
            DISCS.forEach { k -> Chip(discName(k), cat == k) { onCat(if (cat == k) "" else k) } }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (1..5).forEach { g ->
                Box(
                    Modifier.clip(RoundedCornerShape(999.dp)).background(if (lic == g) Color(0xFF2A1F0A) else Surface2)
                        .border(1.dp, if (lic == g) Accent else Line, RoundedCornerShape(999.dp)).clickable { onLic(if (lic == g) 0 else g) }.padding(horizontal = 9.dp, vertical = 5.dp)
                ) { LicBadge(licLetter(g)) }
            }
        }
    }
}

@Composable
fun PlannerScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val st by vm.season.collectAsState()
    val fav by vm.plannerFav.collectAsState()
    LaunchedEffect(Unit) { vm.loadSeason(); vm.track("view:planner") }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var allS by rememberSaveable { mutableStateOf(fav.isEmpty()) }
    var cat by rememberSaveable { mutableStateOf("") }
    var lic by rememberSaveable { mutableIntStateOf(0) }
    var wk by rememberSaveable { mutableIntStateOf(-1) }
    var sheet by remember { mutableStateOf<Pair<SSeries, SWeek>?>(null) }
    val d = st.data
    val now = System.currentTimeMillis()
    Screen(t("planner"), back = { nav.popBackStack() }, head = {
        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("in_development"), color = Accent, fontFamily = FontFamily.Monospace, fontSize = 10.sp, fontWeight = FontWeight.Bold)
            Tabs(listOf(t("pl_weeks"), t("pl_my_season")), tab) { tab = it }
        }
    }) {
        state(st) { vm.loadSeason() }
        if (d == null) return@Screen
        val pool = (if (allS) d.series else d.series.filter { it.sid in fav })
            .filter { (cat.isEmpty() || Season.cat(it, now) == cat) && (lic == 0 || it.lic == lic) }
        val weeks = seasonWeeks(d)
        if (tab == 0) {
            val cw = weeks.indexOfFirst { now >= it.start && now < it.end }.coerceAtLeast(0)
            val k = if (wk in weeks.indices) wk else cw
            item {
                val sc = rememberScrollState()
                LaunchedEffect(Unit) { sc.scrollTo((cw - 1).coerceAtLeast(0) * 64 * 3) }
                Row(Modifier.horizontalScroll(sc), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    weeks.forEachIndexed { i, w ->
                        val on = i == k
                        Column(
                            Modifier.width(58.dp).clip(RoundedCornerShape(12.dp)).background(if (on) Accent else Surface)
                                .border(1.dp, if (on || i == cw) Accent else Line, RoundedCornerShape(12.dp)).alpha(if (w.end < now && !on) .5f else 1f)
                                .clickable { wk = i }.padding(vertical = 7.dp),
                            horizontalAlignment = Alignment.CenterHorizontally
                        ) {
                            Text(t("pl_week").uppercase(), fontSize = 9.sp, fontFamily = FontFamily.Monospace, color = if (on) Ink else Muted)
                            Text("${i + 1}", fontSize = 18.sp, fontWeight = FontWeight.Black, color = if (on) Ink else Fg)
                            Text(plDay(w.start), fontSize = 9.sp, fontFamily = FontFamily.Monospace, color = if (on) Ink else Muted, maxLines = 1)
                        }
                    }
                }
            }
            val ref = weeks.getOrNull(k)
            val rows = if (ref == null) emptyList() else pool.mapNotNull { s -> weekOf(s, ref)?.let { s to it } }
            item {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Metric(t("pl_series"), "${rows.size}", Modifier.weight(1f))
                    Metric(t("pl_on_raced"), "${rows.count { Season.ownTrack(d, it.second) }}", Modifier.weight(1f), color = Good)
                }
            }
            item { Filters(allS, cat, lic, { allS = !allS }, { cat = it }, { lic = it }) }
            ref?.let { item { Text(plDay(it.start) + " – " + plDay(it.end - 1), color = Muted, fontSize = 12.sp) } }
            if (rows.isEmpty()) item { Empty(t(if (!allS && fav.isEmpty()) "pl_star_some" else "pl_no_match")) }
            rows.forEach { (s, w) ->
                item(key = "w${s.id}") {
                    Panel(Modifier.clickable { vm.plannerSeries = s; nav.navigate("pseries") }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            LicBadge(licLetter(s.lic))
                            Text(s.name, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            StarButton(vm, s)
                        }
                        Text(shortTrack(w.track).uppercase(), fontSize = 19.sp, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(w.cfg.ifBlank { w.track }, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Spacer(Modifier.height(6.dp))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                            Row(Modifier.weight(1f).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.CenterVertically) {
                                Own(Season.ownTrack(d, w), t("pl_track"))
                                Pill(lenText(w)); everyText(w).takeIf { it.isNotBlank() }?.let { Pill(it) }; Pill(t("pl_rain", w.rain))
                            }
                            Text(
                                t(if (w.end < now) "pl_done" else "pl_times"), fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                                modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Surface2).border(1.dp, Color(0xFF334155), RoundedCornerShape(10.dp))
                                    .clickable { sheet = s to w }.padding(horizontal = 10.dp, vertical = 6.dp)
                            )
                        }
                    }
                }
            }
        } else {
            item { Filters(allS, cat, lic, { allS = !allS }, { cat = it }, { lic = it }) }
            if (pool.isEmpty()) item { Empty(t(if (!allS && fav.isEmpty()) "pl_star_some" else "pl_no_match")) }
            pool.forEach { s ->
                item(key = "s${s.id}") {
                    val rem = s.weeks.filter { it.end > now }
                    val can = rem.count { Season.ownTrack(d, it) }
                    val cw = Season.curWeek(s, now)
                    val n = Season.nextRace(s, now)
                    Panel {
                        Row(Modifier.fillMaxWidth().clickable { vm.plannerSeries = s; nav.navigate("pseries") }, verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(s.name, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(t("pl_can_race", can, rem.size), color = Muted, fontSize = 12.sp)
                            }
                            Text("$can", fontSize = 26.sp, fontWeight = FontWeight.Black, color = if (can > 0) Good else Muted)
                            Text("/${rem.size}", fontSize = 16.sp, fontWeight = FontWeight.Black, color = Muted)
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                            s.weeks.forEach { w ->
                                val own = Season.ownTrack(d, w)
                                Box(
                                    Modifier.weight(1f).height(22.dp).alpha(if (w.end < now) .35f else 1f).clip(RoundedCornerShape(4.dp))
                                        .background(if (own) Color(0xFF1D4A33) else Bg)
                                        .border(if (w === cw) 2.dp else 1.dp, if (w === cw) Accent else if (own) Color(0xFF2B6B48) else Line, RoundedCornerShape(4.dp))
                                        .clickable { sheet = s to w }
                                )
                            }
                        }
                        Spacer(Modifier.height(8.dp))
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(t("pl_this_week", cw?.let { shortTrack(it.track) } ?: "–"), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                            n?.let { (tm, _) ->
                                Text(plHm(tm), color = Accent, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 13.sp)
                                AddRound(vm, s, tm)
                            }
                        }
                    }
                }
            }
            // the tracks the account has not raced, by how many of the remaining weeks they bring
            val miss = HashMap<String, Pair<Int, MutableSet<String>>>()
            pool.forEach { s -> s.weeks.filter { it.end > now && !Season.ownTrack(d, it) }.forEach { w ->
                val e = miss.getOrPut(w.track) { 0 to mutableSetOf() }; e.second += s.name; miss[w.track] = (e.first + 1) to e.second } }
            val top = miss.entries.sortedByDescending { it.value.first }.take(6)
            if (top.isNotEmpty()) {
                item { Row { Section(t("pl_not_raced").uppercase()); Spacer(Modifier.weight(1f)); Text(t("pl_weeks_they_bring"), color = Muted, fontSize = 11.sp) } }
                item {
                    Panel {
                        top.forEachIndexed { i, e ->
                            if (i > 0) HorizontalDivider(color = Line, modifier = Modifier.padding(vertical = 8.dp))
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(e.key, fontWeight = FontWeight.SemiBold, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                    Text(e.value.second.joinToString(", "), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                }
                                Text("${e.value.first}", fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }
    sheet?.let { (s, w) -> WeekSheet(vm, d, s, w, { sheet = null }) { sheet = null; vm.plannerSeries = s; nav.navigate("pseries") } }
}

/** One week of one series: its track, the ticks, the length, the race times to tap into the plan and "You here". */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun WeekSheet(vm: PitlaneViewModel, d: SeasonData?, s: SSeries, w: SWeek, close: () -> Unit, open: (() -> Unit)?) {
    val now = System.currentTimeMillis()
    ModalBottomSheet(onDismissRequest = close, containerColor = Surface, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 28.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text((s.name + " · " + t("pl_week") + " " + (w.k + 1)).uppercase(), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text(w.track.uppercase(), fontSize = 22.sp, fontWeight = FontWeight.Black)
            Text((if (w.cfg.isNotBlank()) w.cfg + " · " else "") + plDay(w.start) + " – " + plDay(w.end - 1), color = Muted, fontSize = 12.sp)
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                if (d != null) { Own(Season.ownTrack(d, w), t("pl_track")); Own(Season.ownCar(d, s, w), t("pl_car")) }
                Pill(lenText(w)); everyText(w).takeIf { it.isNotBlank() }?.let { Pill(it) }; Pill(t("pl_rain", w.rain))
            }
            if (w.end < now) Text(t("pl_week_over"), color = Muted, fontSize = 13.sp)
            else {
                val ts = Season.starts(w, maxOf(now, w.start), w.end).take(24)
                Section(t("pl_races").uppercase())
                if (ts.isEmpty()) Text(t("pl_no_more"), color = Muted, fontSize = 13.sp)
                else Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    ts.forEach { tm -> TimeChip(vm, s, tm, (if (w.start > now + Season.DAY) plWeekday(tm) + " " else "") + plHm(tm)) }
                }
            }
            Section(t("pl_you_here").uppercase())
            YouHere(vm, w.track)
            if (open != null) OutlinedButton(open, Modifier.fillMaxWidth(), border = BorderStroke(1.dp, Line)) { Text(t("pl_open_series", s.name), color = Fg, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        }
    }
}

/** A series: this week, the next three days of race times, the cars, the account at this week's track and the season. */
@Composable
fun PlannerSeriesScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val s = vm.plannerSeries ?: run { LaunchedEffect(Unit) { nav.popBackStack() }; return }
    val d = vm.season.collectAsState().value.data
    val now = System.currentTimeMillis()
    val w = Season.curWeek(s, now) ?: s.weeks.firstOrNull { it.start > now } ?: s.weeks[0]
    val wi = s.weeks.indexOf(w)
    var sheet by remember { mutableStateOf<SWeek?>(null) }
    Screen(s.name, back = { nav.popBackStack() }, head = {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            StarButton(vm, s); LicBadge(licLetter(s.lic)); Pill(discName(Season.cat(s, now)).ifBlank { Season.cat(s, now) })
            Pill(t(if (s.fixed) "pl_fixed" else "pl_open")); if (s.multi) Pill(t("pl_multiclass"))
        }
    }) {
        if (s.desc.isNotBlank()) item { Text(s.desc, color = Muted, fontSize = 12.sp) }
        item {
            Panel {
                Text(t("pl_this_week_n", wi + 1, s.weeks.size).uppercase(), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                Row(verticalAlignment = Alignment.Top) {
                    Column(Modifier.weight(1f)) {
                        Text(w.track.uppercase(), fontSize = 20.sp, fontWeight = FontWeight.Black)
                        if (w.cfg.isNotBlank()) Text(w.cfg, color = Muted, fontSize = 12.sp)
                    }
                    if (d != null) Column(horizontalAlignment = Alignment.End) { Own(Season.ownTrack(d, w), t("pl_track")); Own(Season.ownCar(d, s, w), t("pl_car")) }
                }
                Spacer(Modifier.height(6.dp))
                InfoRow(t("pl_length"), lenText(w)); InfoRow(t("pl_sessions"), everyText(w).ifBlank { "–" }); InfoRow(t("pl_rain_l"), "${w.rain}%")
                InfoRow(t("pl_inc_limit"), if (s.inc > 0) "${s.inc}" else "–"); InfoRow(t("pl_drops"), "${s.drops}")
            }
        }
        val next = s.weeks.flatMap { Season.starts(it, now, now + 3 * Season.DAY) }.sorted().take(24)
        item { Row { Section(t("pl_next_3").uppercase()); Spacer(Modifier.weight(1f)); Text(t("pl_your_time"), color = Muted, fontSize = 11.sp) } }
        item {
            Panel {
                if (next.isEmpty()) Text(t("pl_none_3"), color = Muted, fontSize = 13.sp)
                var day = ""
                next.forEachIndexed { i, tm ->
                    val dd = plLongDay(tm)
                    if (dd != day) { day = dd; Text(dd.uppercase(), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = if (i > 0) 8.dp else 0.dp, bottom = 4.dp)) }
                    Row(Modifier.padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(plHm(tm), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.width(64.dp))
                        Text(plUntil(tm, now), color = Muted, fontSize = 12.sp, modifier = Modifier.weight(1f))
                        AddButton(vm, s, tm)
                    }
                }
            }
        }
        if (d != null) {
            val cars = Season.carsOf(d, s, w)
            if (cars.isNotEmpty()) {
                item { Section(t("pl_cars").uppercase()) }
                item {
                    Panel {
                        cars.take(10).forEach { c ->
                            Row(Modifier.padding(vertical = 3.dp)) {
                                Text(d.cars[c] ?: "–", fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                                Own(c in d.racedCars, t("pl_raced"))
                            }
                        }
                        if (cars.size > 10) Text(t("pl_more", cars.size - 10), color = Muted, fontSize = 12.sp)
                    }
                }
            }
        }
        item { Section(t("pl_you_at", shortTrack(w.track)).uppercase()) }
        item { YouHere(vm, w.track) }
        val rem = s.weeks.filter { it.end > now }
        item { Row { Section(t("pl_schedule").uppercase()); Spacer(Modifier.weight(1f)); if (d != null) Text(t("pl_can_race", rem.count { Season.ownTrack(d, it) }, rem.size), color = Muted, fontSize = 11.sp) } }
        item {
            Panel {
                s.weeks.forEachIndexed { i, x ->
                    Row(
                        Modifier.fillMaxWidth().alpha(if (x.end < now) .45f else 1f).clip(RoundedCornerShape(8.dp)).background(if (x === w) Color(0xFF2A1F0A) else Color.Transparent)
                            .clickable { sheet = x }.padding(vertical = 6.dp, horizontal = 4.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("${i + 1}", color = Muted, fontFamily = FontFamily.Monospace, modifier = Modifier.width(24.dp))
                        Column(Modifier.weight(1f)) {
                            Text(x.track, fontSize = 13.sp, fontWeight = if (x === w) FontWeight.Bold else FontWeight.Normal, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(plDay(x.start) + " · " + lenText(x), color = Muted, fontSize = 12.sp)
                        }
                        if (d != null) Own(Season.ownTrack(d, x), "")
                    }
                }
            }
        }
    }
    sheet?.let { x -> WeekSheet(vm, d, s, x, { sheet = null }, null) }
}
