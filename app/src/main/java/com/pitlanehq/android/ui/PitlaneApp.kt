package com.pitlanehq.android.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.runtime.collectAsState
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material3.*
import com.pitlanehq.android.data.AppUpdate
import com.pitlanehq.android.data.AccountState
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.draw.alpha
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.draw.clip
import androidx.compose.ui.unit.IntOffset
import androidx.compose.foundation.layout.offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.unit.IntSize
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.viewmodel.compose.viewModel
import androidx.navigation.NavHostController
import kotlinx.coroutines.flow.first
import androidx.navigation.compose.*
import com.pitlanehq.android.BuildConfig
import com.pitlanehq.android.data.SERVER
import com.pitlanehq.android.model.*
import com.pitlanehq.android.viewmodel.LapAnalysis
import com.pitlanehq.android.viewmodel.PitlaneViewModel
import com.pitlanehq.android.viewmodel.RefKind
import java.text.DateFormat
import java.util.Date
import kotlin.math.abs
import kotlin.math.roundToInt

// the pit wall look: one dark theme with the amber accent, never switched
private val Ink = Color(0xFF0D1116)
private val Surface = Color(0xFF161C24)
private val Bg = Color(0xFF0D1116)
private val Surface2 = Color(0xFF1E2631)
private val Line = Color(0xFF263140)
private val Fg = Color(0xFFE7EBF1)
private val Muted = Color(0xFF9AA6B8)
private val Accent = Color(0xFFFFB02E)
private val Good = Color(0xFF4FE09A)
private val Bad = Color(0xFFFF7A7A)
private val Purple = Color(0xFFC9A4FF)
private val Blue = Color(0xFF8CC4FF)
/** the floating tab bar's chosen tab */
private val NavOn = Color(0xFF2E3846)

private const val WEB_APP = "$SERVER/"

/** Support Pitlane HQ (Settings); empty: not shown. */
private const val PATREON_URL = "https://www.patreon.com/c/PitlaneHQ/membership"
/** The changelog of the phone apps (the "What's new" of the update notice): one entry per version. */
private const val CHANGELOG_URL = "https://pitlanehq.app/changelog/phones"
/** Where "Send feedback" goes. */
private const val SUPPORT_EMAIL = "support@pitlanehq.app"
private const val FEEDBACK_URL = "mailto:$SUPPORT_EMAIL?subject=Pitlane%20HQ%20feedback"

private data class Dest(val route: String, val label: String, val icon: ImageVector)

private fun day(ms: Long) = if (ms <= 0) "" else DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(ms))
private fun dayTime(ms: Long) = if (ms <= 0) "" else DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(ms))

@Composable
fun PitlaneApp(vm: PitlaneViewModel = viewModel()) {
    val account by vm.account.collectAsState()
    // every time the app comes to the screen, the account syncs by itself
    LifecycleEventEffect(Lifecycle.Event.ON_START) { vm.onForeground() }
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { vm.onBackground() }
    val scheme = darkColorScheme(
        primary = Accent, onPrimary = Ink, background = Ink, onBackground = Fg, surface = Surface, onSurface = Fg,
        surfaceVariant = Surface2, onSurfaceVariant = Muted, outline = Line, error = Bad
    )
    MaterialTheme(colorScheme = scheme) {
        key(I18n.lang) {
            if (!account.signedIn) LoginScreen(vm, account.error, account.busy) else MainApp(vm)
        }
    }
}

@Composable
private fun LoginScreen(vm: PitlaneViewModel, error: String?, busy: Boolean) {
    var email by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    val needCode by vm.account.collectAsState()
    val uri = LocalUriHandler.current
    if (needCode.needCode) {
        // the password was right: the authenticator code (or a recovery code) finishes the sign-in
        AlertDialog(
            onDismissRequest = { vm.cancelCode() },
            title = { Text(t("two_factor"), fontWeight = FontWeight.Black) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(t("two_factor_code"), color = Muted, fontSize = 12.sp)
                    OutlinedTextField(code, { code = it }, label = { Text(t("code")) }, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number), modifier = Modifier.fillMaxWidth())
                    error?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
                }
            },
            confirmButton = { TextButton({ vm.loginCode(code) }, enabled = !busy && code.isNotBlank()) { Text(t("sign_in"), color = Accent) } },
            dismissButton = { TextButton({ vm.cancelCode() }) { Text(t("cancel"), color = Muted) } }
        )
    }
    LazyColumn(
        Modifier.fillMaxSize().background(Ink).systemBarsPadding().imePadding(),
        contentPadding = PaddingValues(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item { Spacer(Modifier.height(32.dp)) }
        item { Text("PITLANE HQ", color = Fg, fontSize = 34.sp, fontWeight = FontWeight.Black) }
        item { Text(t("companion"), color = Accent, fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
        item {
            Panel {
                Text(t("sign_in").uppercase(), fontSize = 22.sp, fontWeight = FontWeight.Black)
                Text(t("same_account"), color = Muted, fontSize = 12.sp)
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    email, { email = it }, label = { Text(t("email")) }, singleLine = true,
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Email), modifier = Modifier.fillMaxWidth()
                )
                OutlinedTextField(
                    password, { password = it }, label = { Text(t("password")) }, singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password), modifier = Modifier.fillMaxWidth()
                )
                error?.let { Text(t(it), color = Bad, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
                Spacer(Modifier.height(10.dp))
                Button(
                    onClick = { vm.login(email, password) }, enabled = !busy && email.isNotBlank() && password.isNotBlank(),
                    modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)
                ) { Text((if (busy) t("signing_in") else t("sign_in")).uppercase(), fontWeight = FontWeight.Black) }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton({ uri.openUri(WEB_APP) }) { Text(t("create_account"), color = Accent, fontSize = 12.sp) }
                    TextButton({ uri.openUri("$SERVER/account/forgot") }) { Text(t("forgot"), color = Muted, fontSize = 12.sp) }
                }
            }
        }
    }
}

@Composable
private fun MainApp(vm: PitlaneViewModel) {
    val nav = rememberNavController()
    val demo by vm.demo.collectAsState()
    val online by vm.online.collectAsState()
    val upd by vm.update.collectAsState()
    val uri = LocalUriHandler.current
    val info = rememberInfo(vm, nav)
    CompositionLocalProvider(LocalInfo provides info) {
    Scaffold(containerColor = Ink, bottomBar = { BottomBar(nav) }) { pad ->
        Column(Modifier.padding(pad).fillMaxSize()) {
            Column(Modifier.statusBarsPadding()) {
                if (!online) Banner(t("showing_saved"), Bad)
                if (demo && ShotMode.route == null) Banner(t("demo_banner"), Accent)
                upd?.let { u -> Banner(t("update_available", u.version), Good) { uri.openUri(u.url) } }
            }
            UpdateNotice(upd)
            // the screenshot job (debug builds): open the screen it asked for
            LaunchedEffect(Unit) {
                val r = ShotMode.route ?: return@LaunchedEffect
                vm.analysisTab = ShotMode.tab
                if (r == "race") {
                    vm.race = vm.races.first { !it.data.isNullOrEmpty() }.data!!.first()
                }
                if (r != "home") nav.navigate(r)
            }
            NavHost(nav, "home", Modifier.weight(1f)) {
                composable("home") { Home(vm, nav) }
                composable("race") { RaceDetail(vm, nav) }
                composable("analysis") { Analysis(vm, nav) }
                composable("session") { SessionDetail(vm, nav) }
                composable("lap") { LapDetail(vm, nav) }
                composable("community") { Community(vm, nav) }
                composable("combo") { ComboDetail(vm, nav) }
                composable("track") { TrackPageScreen(vm, nav) }
                composable("profile") { ProfileScreen(vm, nav) }
                composable("notes") { TrackNotesScreen(vm, nav) }
                composable("live") { Live(vm) }
                composable("settings") { Settings(vm, nav) }
                composable("drinks") { DrinksScreen(vm, nav) }
                composable("admin") { AdminScreen(vm, nav) }
            }
        }
    }
    }
}

/** One entry of Info: an alert (dismissable) or one of the permanent items (support, feedback). */
private class InfoItem(val id: String, val icon: androidx.compose.ui.graphics.vector.ImageVector, val title: String, val text: String, val keep: Boolean = false, val acts: List<Pair<String, () -> Unit>>)

/** Info, shared by every screen's header: the alerts, how many are new, and the sheet. */
private class InfoState(val alerts: List<InfoItem>, val always: List<InfoItem>, val fresh: Int, val open: () -> Unit)
private val LocalInfo = compositionLocalOf<InfoState?> { null }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun rememberInfo(vm: PitlaneViewModel, nav: NavHostController): InfoState {
    val a by vm.account.collectAsState()
    val upd by vm.update.collectAsState()
    val news by vm.news.collectAsState()
    val seen by vm.inboxSeen.collectAsState()
    var open by remember { mutableStateOf(false) }
    val uri = LocalUriHandler.current
    val alerts = buildList {
        upd?.let { u -> add(InfoItem("upd:" + u.version, Icons.Default.Download, t("update_title", u.version), t("update_body", BuildConfig.VERSION_NAME.replace("-", " ")), acts = listOf(t("download") to { uri.openUri(u.url) }, t("whats_new") to { uri.openUri(CHANGELOG_URL + "#" + u.version.replace(".", "") + "-beta") }))) }
        if (!a.twoFactor) add(InfoItem("2fa", Icons.Default.Lock, t("two_factor_rec_short"), t("two_factor_rec_sub"), acts = listOf(t("turn_on") to { nav.navigate("settings") })))
        news.forEach { n -> add(InfoItem("news:" + n.id, Icons.Default.Newspaper, n.title, n.text + if (n.date.isNotBlank()) " · " + n.date else "", acts = listOfNotNull(n.url?.let { u -> t("open") to { uri.openUri(u) } }, n.view?.let { v -> t("see_it") to { nav.navigate(if (v == "me") "settings" else v) } }))) }
    }.filter { it.keep || it.id !in seen }
    val always = buildList {
        if (PATREON_URL.isNotEmpty()) add(InfoItem("support", Icons.Default.Favorite, t("support"), t("support_sub"), keep = true, acts = listOf("Patreon" to { uri.openUri(PATREON_URL) })))
        add(InfoItem("feedback", Icons.Default.Forum, t("feedback"), t("feedback_sub"), keep = true, acts = listOf(t("send_feedback") to { uri.openUri(FEEDBACK_URL) })))
    }
    val fresh = alerts.count { "seen:" + it.id !in seen }
    if (open) ModalBottomSheet(onDismissRequest = { open = false; vm.inboxMark(alerts.map { "seen:" + it.id }) }, containerColor = Surface) {
        Column(Modifier.padding(horizontal = 16.dp).padding(bottom = 24.dp).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(t("alerts").uppercase(), color = Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, modifier = Modifier.weight(1f))
                if (alerts.any { !it.keep }) TextButton({ vm.inboxMark(alerts.filter { !it.keep }.map { it.id }) }) { Text(t("clear"), color = Muted, fontSize = 12.sp) }
            }
            if (alerts.isEmpty()) Text(t("nothing_new"), color = Muted, fontSize = 13.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 12.dp))
            alerts.forEach { InfoRow(it, { open = false }) { vm.inboxMark(listOf(it.id)) } }
            Text("PITLANE HQ", color = Muted, fontSize = 12.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(top = 8.dp))
            always.forEach { InfoRow(it, { open = false }, null) }
        }
    }
    return InfoState(alerts, always, fresh) { open = true }
}

@Composable
private fun InfoRow(it: InfoItem, close: () -> Unit, dismiss: (() -> Unit)?) {
    Row(Modifier.fillMaxWidth().background(Surface2, androidx.compose.foundation.shape.RoundedCornerShape(10.dp)).padding(10.dp), verticalAlignment = Alignment.Top) {
        Icon(it.icon, null, tint = Accent, modifier = Modifier.padding(end = 10.dp, top = 2.dp))
        Column(Modifier.weight(1f)) {
            Text(it.title, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            Text(it.text, color = Muted, fontSize = 12.sp)
            Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                it.acts.forEachIndexed { i, (label, run) ->
                    if (i == 0) Button({ close(); run() }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink), contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) { Text(label.uppercase(), fontSize = 11.sp, fontWeight = FontWeight.Black) }
                    else OutlinedButton({ close(); run() }, contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp)) { Text(label.uppercase(), fontSize = 11.sp, color = Fg) }
                }
            }
        }
        if (dismiss != null && !it.keep) IconButton(dismiss, modifier = Modifier.size(28.dp)) { Icon(Icons.Default.Close, t("dismiss"), tint = Muted) }
    }
}

/** The Info button in the header of every screen, with the number of new alerts. */
@Composable
private fun InfoButton() {
    val info = LocalInfo.current ?: return
    BadgedBox(badge = { if (info.fresh > 0) Badge(containerColor = Accent, contentColor = Ink) { Text("${info.fresh}") } }) {
        IconButton(info.open) { Icon(Icons.Outlined.Info, "Info", tint = Muted) }
    }
}

/** When the app starts with a newer version published: what's new, download, or later (the banner stays). */
@Composable
private fun UpdateNotice(u: AppUpdate?) {
    var shown by rememberSaveable { mutableStateOf("") }
    val uri = LocalUriHandler.current
    if (u == null || shown == u.version) return
    AlertDialog(
        onDismissRequest = { shown = u.version },
        title = { Text(t("update_title", u.version), fontWeight = FontWeight.Black) },
        text = { Text(t("update_body", BuildConfig.VERSION_NAME.replace("-", " ")), color = Muted, fontSize = 13.sp) },
        confirmButton = {
            Row {
                TextButton({ uri.openUri(CHANGELOG_URL + "#" + u.version.replace(".", "") + "-beta") }) { Text(t("whats_new"), color = Accent) }
                TextButton({ shown = u.version; uri.openUri(u.url) }) { Text(t("download"), color = Accent, fontWeight = FontWeight.Bold) }
            }
        },
        dismissButton = { TextButton({ shown = u.version }) { Text(t("later"), color = Muted) } }
    )
}

@Composable
private fun Banner(s: String, c: Color, onClick: (() -> Unit)? = null) {
    Text(
        s, color = Ink, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace,
        modifier = Modifier.fillMaxWidth().background(c).let { if (onClick != null) it.clickable(onClick = onClick) else it }.padding(horizontal = 16.dp, vertical = 6.dp)
    )
}

@Composable
private fun BottomBar(nav: NavHostController) {
    val dests = listOf(
        Dest("home", t("home"), Icons.Default.Home),
        Dest("analysis", t("analysis"), Icons.Default.QueryStats),
        Dest("live", t("live"), Icons.Default.Sensors),
        Dest("community", t("community"), Icons.Default.Groups),
        Dest("settings", t("account_tab"), Icons.Default.Person)
    )
    val current = nav.currentBackStackEntryAsState().value?.destination?.route
    val tab = when (current) { "race" -> if (nav.previousBackStackEntry?.destination?.route == "analysis") "analysis" else "home"; "session", "lap" -> "analysis"; "combo" -> "community"; "drinks", "admin" -> "settings"; else -> current }
    // a floating bar over the screen: the chosen tab is a lighter pill with the amber icon
    Row(
        Modifier.fillMaxWidth().background(Ink).navigationBarsPadding().padding(start = 16.dp, end = 16.dp, top = 6.dp, bottom = 12.dp)
            .clip(RoundedCornerShape(22.dp)).background(Surface2).border(1.dp, Color(0xFF2E3A4A), RoundedCornerShape(22.dp)).padding(6.dp)
    ) {
        dests.forEach { d ->
            val on = tab == d.route
            Column(
                Modifier.weight(1f).heightIn(min = 52.dp).clip(RoundedCornerShape(16.dp)).background(if (on) NavOn else Color.Transparent)
                    .clickable { nav.navigate(d.route) { popUpTo("home") { saveState = true }; launchSingleTop = true; restoreState = true } },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center
            ) {
                Icon(d.icon, d.label, tint = if (on) Accent else Muted, modifier = Modifier.size(22.dp))
                Text(d.label, fontSize = 10.sp, maxLines = 1, color = if (on) Accent else Muted, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Normal)
            }
        }
    }
}

@Composable
private fun Screen(title: String, sub: String = "", back: (() -> Unit)? = null, content: LazyListScope.() -> Unit) {
    LazyColumn(
        Modifier.fillMaxSize().background(Ink),
        contentPadding = PaddingValues(start = 14.dp, end = 14.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                if (back != null) IconButton(back) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Fg) }
                Column(Modifier.weight(1f)) {
                    Text(title.uppercase(), color = Fg, fontSize = 26.sp, fontWeight = FontWeight.Black, letterSpacing = 1.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (sub.isNotBlank()) Text(sub, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                InfoButton()
            }
        }
        content()
    }
}

/** Loading bar, error with a retry button, and the "saved copy" note. */
private fun <T> LazyListScope.state(l: Loadable<T>, retry: () -> Unit) {
    if (l.loading) item { LinearProgressIndicator(Modifier.fillMaxWidth(), color = Accent, trackColor = Surface2) }
    l.error?.let { e ->
        item {
            Panel {
                Text(t(e), color = Bad, fontSize = 13.sp)
                TextButton(retry) { Text(t("retry").uppercase(), color = Accent, fontWeight = FontWeight.Bold) }
            }
        }
    }
    if (l.stale && l.error == null) item { Text(t("showing_saved"), color = Accent, fontSize = 11.sp) }
}

// ---------- Home ----------
@Composable
private fun Home(vm: PitlaneViewModel, nav: NavHostController) {
    val a by vm.account.collectAsState()
    val r by vm.races.collectAsState()
    val races = r.data ?: emptyList()
    Screen(a.display.ifBlank { t("driver") }) {
        if (a.admin || (a.supporter && !a.supporterHidden)) item { Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { MyBadges(a) } }
        state(r) { vm.loadRaces() }
        // the pit wall: your last race on top, then the days you drove, the licence summary and your races
        races.firstOrNull()?.let { x -> item { LastRace(x) { vm.race = x; nav.navigate("race") } } }
        item { DaysDriven(vm, nav, races) }
        item { Licences(vm) }
        item { Section(t("race_summary")) }
        item {
            // no iRating here: each category has its own (the licence summary above), never one number for all
            val recent = races.take(10)
            Grid(
                listOf(
                    MetricData(t("races"), "${races.size}"),
                    MetricData(t("wins"), "${races.count { it.finish == 1 }}"),
                    MetricData(t("top5"), "${races.count { it.finish in 1..5 }}"),
                    MetricData(t("avg_inc"), if (recent.isEmpty()) "—" else "%.1f".format(recent.map { it.inc }.average()))
                ), columns = 2
            )
        }
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Section(t("your_recent_races"))
                Spacer(Modifier.weight(1f))
                if (races.size > 5) TextButton({ vm.analysisTab = 3; nav.navigate("analysis") { popUpTo("home") { saveState = true }; launchSingleTop = true; restoreState = true } }) { Text(t("see_all"), color = Accent, fontSize = 12.sp) }
            }
        }
        if (r.data != null && races.isEmpty()) item { Empty(t("no_races")) }
        items(races.take(5)) { x -> RaceRow(x) { vm.race = x; nav.navigate("race") } }
        item { Text(t("ir_estimate"), color = Muted, fontSize = 11.sp) }
        // no sync card (the sync is automatic): only what went wrong, when something did
        a.error?.let { e -> item { Text(t(e), color = Bad, fontSize = 12.sp) } }
    }
}

/**
 * The days you drove, like the web and the PC: the last 26 weeks in squares, brighter the more races and sessions that day.
 * A day opens what you drove: the race summaries and the sessions.
 */
@Composable
private fun DaysDriven(vm: PitlaneViewModel, nav: NavHostController, races: List<Race>) {
    val sl by vm.sessions.collectAsState()
    LaunchedEffect(Unit) { if (sl.data == null && !sl.loading) vm.loadSessions() }
    val sessions = sl.data ?: emptyList()
    val zone = java.time.ZoneId.systemDefault()
    fun day(ms: Long) = java.time.Instant.ofEpochMilli(ms).atZone(zone).toLocalDate()
    val byRace = races.groupBy { day(it.whenMs) }
    val bySes = sessions.groupBy { day(it.started) }
    val today = java.time.LocalDate.now(zone)
    val weeks = 26
    val start = today.minusDays(((today.dayOfWeek.value - 1) + (weeks - 1) * 7).toLong())
    val count = { d: java.time.LocalDate -> (byRace[d]?.size ?: 0) + (bySes[d]?.size ?: 0) }
    val max = ((0 until weeks * 7).maxOfOrNull { count(start.plusDays(it.toLong())) } ?: 1).coerceAtLeast(1)
    val driven = (0 until weeks * 7).count { val d = start.plusDays(it.toLong()); !d.isAfter(today) && count(d) > 0 }
    var open by remember { mutableStateOf<java.time.LocalDate?>(null) }
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Section(t("days_driven")); Spacer(Modifier.weight(1f)); Text(t("days_in_6m", driven), color = Muted, fontSize = 11.sp)
    }
    Panel {
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
            for (w in 0 until weeks) Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                for (d in 0 until 7) {
                    val date = start.plusDays((w * 7 + d).toLong())
                    val n = count(date)
                    val a = if (n == 0) 0f else listOf(.35f, .6f, .8f, 1f)[(kotlin.math.ceil(n.toDouble() / max * 4).toInt() - 1).coerceIn(0, 3)]
                    Box(
                        Modifier.size(11.dp).clip(RoundedCornerShape(3.dp))
                            .background(if (date.isAfter(today)) Color.Transparent else if (n == 0) Surface2 else Accent.copy(alpha = a))
                            .then(if (n > 0) Modifier.clickable { open = date } else Modifier)
                    )
                }
            }
        }
    }
    open?.let { d ->
        AlertDialog(
            onDismissRequest = { open = null },
            confirmButton = { TextButton({ open = null }) { Text(t("close"), color = Accent) } },
            title = { Text(d.format(java.time.format.DateTimeFormatter.ofPattern("EEEE d MMMM")), fontWeight = FontWeight.Black) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    byRace[d]?.forEach { x ->
                        Text("${x.track} · P${x.finish}/${x.field} · ${x.inc}x", fontWeight = FontWeight.Bold,
                            modifier = Modifier.fillMaxWidth().clickable { open = null; vm.race = x; nav.navigate("race") }.padding(vertical = 6.dp))
                    }
                    bySes[d]?.forEach { x ->
                        Text("${kindText(x.kind)} · ${x.track} · ${x.car} · ${lapTime(x.best)}", color = Fg,
                            modifier = Modifier.fillMaxWidth().clickable { open = null; vm.session = x; vm.loadLaps(x.id); nav.navigate("session") }.padding(vertical = 6.dp))
                    }
                }
            }
        )
    }
}

/** Your last race on Home: where, the place, what it gave and the way to its summary. */
@Composable
private fun LastRace(x: Race, onClick: () -> Unit) {
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onClick), colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Accent.copy(alpha = 0.45f)), shape = RoundedCornerShape(14.dp)
    ) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(t("last_race"), color = Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.3.sp, modifier = Modifier.weight(1f))
                Text(day(x.whenMs), color = Muted, fontSize = 11.sp)
            }
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(x.track, fontWeight = FontWeight.Black, fontSize = 20.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(listOf(x.car, discName(raceDisc(x.cat, x.car))).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) { DrinksBadge(x); AiBadge(x) }
                }
                Text(if (x.dnf) t("dnf") else "P${x.finish}", fontSize = 34.sp, fontWeight = FontWeight.Black, color = if (!x.dnf && x.finish in 1..3) Accent else Fg)
                if (!x.dnf) Text("/${x.field}", color = Muted, fontSize = 14.sp, modifier = Modifier.padding(top = 12.dp))
            }
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // a race against the AI has no iRating
                LastStat(t("lr_ir"), if (x.ai) "—" else signed(x.irChange), if (x.ai) Muted else if (x.irChange > 0) Good else if (x.irChange < 0) Bad else Fg, Modifier.weight(1f).fillMaxHeight())
                LastStat(t("lr_best"), lapTime(x.best), Purple, Modifier.weight(1f).fillMaxHeight())
                LastStat(t("lr_inc"), "${x.inc}x", if (x.inc >= 8) Bad else Fg, Modifier.weight(1f).fillMaxHeight())
            }
            Text(t("see_summary"), color = Accent, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
        }
    }
}

@Composable
private fun LastStat(l: String, v: String, c: Color, m: Modifier) {
    Column(m.clip(RoundedCornerShape(10.dp)).background(Ink).padding(horizontal = 10.dp, vertical = 8.dp)) {
        Text(l, color = Muted, fontSize = 10.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp, maxLines = 1)
        Text(v, color = c, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 16.sp, maxLines = 1)
    }
}

/** Your rated races of one discipline, oldest first (an offline race's placeholder iRating 1 is none). */
private fun irRaces(races: List<Race>, k: String, n: Int) =
    races.filter { !it.ai && it.ir != 1 && raceDisc(it.cat, it.car) == k }.take(n).reversed()

/** The iRating each of those races left you at: the race's own when it has one, else counted back from the newest
 *  known (a race's, or the discipline's rating) with the changes in between. */
private fun irVals(rs: List<Race>, now: Int?): List<Int> {
    val cum = rs.runningFold(0) { a, r -> a + r.irChange }.drop(1)
    val m = rs.indexOfLast { it.ir > 1 }
    val off = if (m >= 0) rs[m].ir + rs[m].irChange - cum[m] else if (now != null && now > 1) now - cum.last() else 0
    return rs.mapIndexed { i, r -> if (r.ir > 1) r.ir + r.irChange else cum[i] + off }
}

/** The iRating after each race as a line that follows the finger: the point under it is picked (onSel). */
@Composable
private fun IrLine(vals: List<Int>, col: Color, height: Dp, sel: Int?, area: Boolean = false, onSel: (Int) -> Unit) {
    val n = vals.size
    if (n < 2) return
    var width by remember { mutableIntStateOf(1) }
    fun pickAt(x: Float) = onSel(((x / width.coerceAtLeast(1)) * (n - 1)).roundToInt().coerceIn(0, n - 1))
    val lo = vals.min() - 10.0; val hi = vals.max() + 10.0
    Canvas(
        Modifier.fillMaxWidth().height(height).onSizeChanged { width = it.width }
            .pointerInput(n) { detectTapGestures(onPress = { pickAt(it.x) }) }
            .pointerInput(n) { detectHorizontalDragGestures(onDragStart = { pickAt(it.x) }, onHorizontalDrag = { ch, _ -> pickAt(ch.position.x); ch.consume() }) }
    ) {
        val pad = 4.dp.toPx()
        fun x(i: Int) = size.width * i / (n - 1)
        fun y(v: Int) = (pad + (size.height - 2 * pad) * (1 - (v - lo) / (hi - lo))).toFloat()
        val p = Path().apply { vals.forEachIndexed { i, v -> if (i == 0) moveTo(x(i), y(v)) else lineTo(x(i), y(v)) } }
        if (area) drawPath(Path().apply { addPath(p); lineTo(size.width, size.height); lineTo(0f, size.height); close() }, col.copy(alpha = 0.10f))
        drawPath(p, col, style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
        sel?.coerceIn(0, n - 1)?.let { i ->
            drawLine(Fg.copy(alpha = 0.5f), Offset(x(i), 0f), Offset(x(i), size.height), 1.dp.toPx())
            drawCircle(Ink, 5.dp.toPx(), Offset(x(i), y(vals[i])))
            drawCircle(col, 5.dp.toPx(), Offset(x(i), y(vals[i])), style = Stroke(width = 2.dp.toPx()))
        }
    }
}

/** My races: your iRating of one discipline over its last races, a line you read with your finger. */
@Composable
private fun IrTrend(races: List<Race>, now: Map<String, Triple<Int, String, Long>>, onOpen: (Race) -> Unit) {
    val discs = DISCS.filter { k -> irRaces(races, k, 2).size >= 2 }
    if (discs.isEmpty()) return
    var k by rememberSaveable { mutableStateOf("") }
    val disc = k.takeIf { it in discs } ?: races.firstOrNull { !it.ai && it.ir != 1 }?.let { raceDisc(it.cat, it.car) }?.takeIf { it in discs } ?: discs[0]
    val rs = irRaces(races, disc, 12)
    val vals = irVals(rs, now[disc]?.first)
    var sel by remember(disc) { mutableStateOf<Int?>(null) }
    val i = sel ?: (rs.size - 1)
    val x = rs[i]
    Panel {
        if (discs.size > 1) Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            discs.forEach { d -> Chip(discName(d), d == disc) { k = d } }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Section(t("ir_trend", discName(disc).uppercase()))
            Spacer(Modifier.weight(1f))
            Text(vals[i].toString(), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 18.sp)
            Text(" " + signed(x.irChange), color = if (x.irChange >= 0) Good else Bad, fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.Bold)
        }
        if (sel == null) Text(t("spark_last", rs.size) + " · " + signed(rs.sumOf { it.irChange }), color = Muted, fontSize = 12.sp)
        else Text(x.track + " · " + (if (x.dnf) t("dnf") else "P${x.finish}") + " · " + day(x.whenMs) + "  ›", color = Accent, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
            modifier = Modifier.clickable { onOpen(x) })
        Spacer(Modifier.height(6.dp))
        IrLine(vals, Accent, 110.dp, sel, area = true) { sel = it }
    }
}

@Composable
private fun RaceRow(x: Race, onClick: () -> Unit) {
    Panel(Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Text(x.track, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) { DrinksBadge(x); AiBadge(x) }
                Text(x.car, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    listOf(day(x.whenMs), if (x.official) t("official") else t("unofficial"), if (x.sof > 0) "SOF ${x.sof}" else "").filter { it.isNotBlank() }.joinToString(" · "),
                    color = Muted, fontSize = 11.sp
                )
            }
            Column(horizontalAlignment = Alignment.End) {
                Text(if (x.dnf) t("dnf") else "P${x.finish}/${x.field}", fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, color = if (x.finish == 1) Purple else Fg)
                // a race against the AI has no iRating
                if (!x.ai) Text("iR " + signed(x.irChange), color = if (x.irChange > 0) Good else if (x.irChange < 0) Bad else Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp, fontWeight = FontWeight.Bold)
                Text("${x.inc}x", color = if (x.inc >= 8) Bad else Muted, fontFamily = FontFamily.Monospace, fontSize = 11.sp)
            }
        }
    }
}

/** DRINKS mode: a race a friend drove (any lap): "DRINKS · Ana", or "DRINKS · Multiple drivers" when several drove
 *  it; tapped, who drove it, their laps and their best lap. */
@Composable
private fun DrinksBadge(x: Race, names: Boolean = false) {
    if (x.drinks.isEmpty()) return
    var open by remember { mutableStateOf(false) }
    val many = x.drinks.size > 1
    Column(Modifier.padding(vertical = 2.dp)) {
        Text("DRINKS · " + (if (many) t("drinks_multiple") + " ▾" else x.drinks[0]), color = Color(0xFFFFE2A8), fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp, maxLines = 1,
            modifier = Modifier.background(Accent.copy(alpha = 0.22f), RoundedCornerShape(50)).border(1.dp, Accent.copy(alpha = 0.6f), RoundedCornerShape(50)).then(if (many) Modifier.clickable { open = true } else Modifier).padding(horizontal = 8.dp, vertical = 2.dp))
        if (names && many) Text(t("drinks_by", x.drinks.joinToString(", ")), color = Muted, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
    }
    if (open) AlertDialog(onDismissRequest = { open = false }, confirmButton = { TextButton({ open = false }) { Text("OK") } },
        title = { Text("DRINKS · " + t("drinks_who"), fontWeight = FontWeight.Black) },
        text = {
            Column {
                Text(x.track + " · " + x.car, color = Muted, fontSize = 12.sp, modifier = Modifier.padding(bottom = 8.dp))
                (x.drivers().ifEmpty { x.drinks.map { Triple(it, 0, null as Double?) } }).forEach { (n, laps, best) ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        Text(n, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                        if (laps > 0) Text(t("drinks_laps", laps, lapTime(best)), color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        })
}

/** A race against iRacing's AI drivers */
@Composable
private fun AiBadge(x: Race) {
    if (!x.ai) return
    Text(t("vs_ai"), color = Blue, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp, maxLines = 1,
        modifier = Modifier.padding(vertical = 2.dp).border(1.dp, Blue.copy(alpha = 0.55f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
}

@Composable
private fun RaceDetail(vm: PitlaneViewModel, nav: NavHostController) {
    val x = vm.race ?: return
    val notes by vm.driverNotes.collectAsState()
    var editing by remember { mutableStateOf<RaceResult?>(null) }
    LaunchedEffect(Unit) { vm.loadDriverNotes() }
    val anyMe = x.results.any { it.me }
    Screen(x.track, x.car + " · " + dayTime(x.whenMs), back = { nav.popBackStack() }) {
        if (x.drinks.isNotEmpty() || x.ai) item { Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) { DrinksBadge(x, names = true); AiBadge(x) } }
        item {
            Grid(
                listOf(
                    MetricData(t("start"), "P${x.start}"),
                    MetricData(t("finish"), if (x.dnf) t("dnf") else "P${x.finish}", if (x.finish == 1) Purple else Fg),
                    if (x.ai) MetricData("iRating", "—", Muted, t("vs_ai")) // a race against the AI has none
                    else MetricData("iRating", signed(x.irChange), if (x.irChange > 0) Good else if (x.irChange < 0) Bad else Fg, if (x.ir > 0) "${x.ir} → ${x.ir + x.irChange}" else null),
                    MetricData(t("incidents"), "${x.inc}x", if (x.inc >= 8) Bad else Fg),
                    MetricData(t("pos_gain"), signed(x.start - x.finish), if (x.start > x.finish) Good else if (x.start < x.finish) Bad else Fg),
                    MetricData(t("sof"), if (x.sof > 0) "${x.sof}" else "—")
                ), columns = 3
            )
        }
        item {
            Panel {
                InfoRow(t("best_lap"), lapTime(x.best), Purple)
                InfoRow(t("field_best"), lapTime(x.fieldBest))
                InfoRow(t("average"), lapTime(x.avg))
                InfoRow(t("consistency"), x.consistency?.let { "±%.3f s".format(it) } ?: "—")
                InfoRow(t("pits"), "${x.pits}")
                InfoRow(t("fuel_used"), x.fuelUsed?.let { "%.1f L".format(it) } ?: "—")
                InfoRow(t("laps"), "${x.laps.size} · " + t("drivers", x.field))
            }
        }
        if (x.laps.isNotEmpty()) {
            item { Section(t("laps").uppercase()) }
            item {
                Panel {
                    val best = x.laps.filter { it.time > 0 && !it.cut }.minOfOrNull { it.time }
                    val drk = x.drivers().isNotEmpty()
                    x.laps.forEach { l ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                            Text("L${l.n}", color = Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp, modifier = Modifier.width(44.dp))
                            // DRINKS mode: who drove each lap
                            if (drk) Text(x.driverOf(l), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.width(78.dp))
                            val strike = if (l.cut) TextDecoration.LineThrough else TextDecoration.None
                            Text(lapTime(l.time), fontFamily = FontFamily.Monospace, fontSize = 12.sp, color = if (l.cut) Muted else if (l.time == best) Purple else Fg, textDecoration = strike, modifier = Modifier.weight(1f).alpha(if (l.cut) .6f else 1f))
                            Text("P${l.pos}", color = Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp, textDecoration = strike, modifier = Modifier.width(44.dp).alpha(if (l.cut) .6f else 1f))
                            Text(listOfNotNull(if (l.cut) t("invalid").lowercase() else null, if (l.pit) t("pit") else null, if (l.inc > 0) "${l.inc}x" else null).joinToString(" · "), color = if (l.pit && !l.cut) Blue else Bad, fontFamily = FontFamily.Monospace, fontSize = 11.sp, modifier = Modifier.widthIn(min = 40.dp))
                        }
                    }
                }
            }
        }
        if (x.results.isNotEmpty()) {
            item { Section(t("results")) }
            item {
                Panel {
                    Text(t("tap_driver_note"), color = Muted, fontSize = 11.sp, modifier = Modifier.padding(bottom = 4.dp))
                    x.results.forEach { p ->
                        val me = if (anyMe) p.me else p.pos == x.finish
                        val note = if (me) null else noteFor(notes, p.k, p.name)
                        // your note on a driver: their tag before the name; tap a driver to mark them
                        Row(Modifier.fillMaxWidth().then(if (me || p.ai) Modifier else Modifier.clickable { editing = p }).padding(vertical = 3.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text("${p.pos}", color = if (me) Accent else Muted, fontFamily = FontFamily.Monospace, fontSize = 12.sp, modifier = Modifier.width(30.dp))
                            if (note != null && note.tag.isNotEmpty()) { TagIcon(note.tag, 14.dp); Spacer(Modifier.width(5.dp)) }
                            // your car in a DRINKS race: who drove it
                            val nm = if (me && x.drivers().isNotEmpty()) x.drivers().joinToString(", ") { it.first } else p.name
                            Text(nm + if (note != null && note.note.isNotEmpty()) " ✎" else "", fontSize = 12.sp, fontWeight = if (me) FontWeight.Black else FontWeight.Normal, color = if (me) Accent else Fg, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                            if (p.ai) Text(" " + t("ai_driver"), color = Blue, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                            // laps more (red) or less (blue) than you, like the relative
                            val myLaps = x.results.firstOrNull { if (anyMe) it.me else it.pos == x.finish }?.laps ?: 0
                            val dl = if (!me && p.laps > 0 && myLaps > 0) p.laps - myLaps else 0
                            if (dl != 0) Text((if (dl > 0) " +" else " −") + kotlin.math.abs(dl) + "L", color = if (dl > 0) Bad else Blue, fontSize = 10.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                            Spacer(Modifier.weight(1f))
                            Text(if (p.ir > 0 && !x.ai) "${p.ir}" else "", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(44.dp))
                            Text(lapTime(p.best), fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(66.dp))
                            Text("${p.inc}x", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(30.dp))
                        }
                    }
                }
            }
        }
    }
    editing?.let { d -> DriverNoteDialog(vm, d, noteFor(notes, d.k, d.name)) { editing = null } }
}

// ---------- driver notes ----------
private val TagColors = mapOf("danger" to Color(0xFFFF5B5B), "careful" to Color(0xFFFFB02E), "clean" to Color(0xFF38C97C), "friend" to Color(0xFF4C9BFF))

private fun noteFor(notes: Map<String, DriverNote>, key: String, name: String): DriverNote? =
    notes[key].takeIf { key.isNotEmpty() } ?: notes["n:" + name.trim().lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ")]

/** The icon of a tag, the same as the PC's and the web's: a red triangle, an amber circle, a green tick, a blue star. */
@Composable
private fun TagIcon(tag: String, size: androidx.compose.ui.unit.Dp) {
    val col = TagColors[tag] ?: return
    Canvas(Modifier.size(size)) {
        val u = this.size.width / 16f
        val ink = if (tag == "careful") Color(0xFF14171C) else Color.White
        if (tag == "danger") {
            drawPath(Path().apply { moveTo(8 * u, 0.6f * u); lineTo(15.8f * u, 14.6f * u); lineTo(0.2f * u, 14.6f * u); close() }, col)
            drawLine(ink, Offset(8 * u, 5 * u), Offset(8 * u, 9.6f * u), 1.9f * u, StrokeCap.Round)
            drawCircle(ink, 1.1f * u, Offset(8 * u, 12.1f * u))
            return@Canvas
        }
        drawCircle(col, 8 * u, Offset(8 * u, 8 * u))
        when (tag) {
            "careful" -> { drawLine(ink, Offset(8 * u, 3.8f * u), Offset(8 * u, 9 * u), 1.9f * u, StrokeCap.Round); drawCircle(ink, 1.1f * u, Offset(8 * u, 11.7f * u)) }
            "clean" -> drawPath(Path().apply { moveTo(4.4f * u, 8.2f * u); lineTo(7 * u, 10.9f * u); lineTo(11.8f * u, 5.4f * u) }, ink, style = Stroke(1.9f * u, cap = StrokeCap.Round, join = StrokeJoin.Round))
            "friend" -> drawPath(Path().apply {
                for (i in 0 until 10) {
                    val r = if (i % 2 == 0) 5f else 2.1f
                    val a = -Math.PI / 2 + i * Math.PI / 5
                    val px = (8 + r * Math.cos(a)).toFloat() * u; val py = (8 + r * Math.sin(a)).toFloat() * u
                    if (i == 0) moveTo(px, py) else lineTo(px, py)
                }
                close()
            }, ink)
        }
    }
}

/** Mark a driver: one tag (or none) and a note only you see. */
@Composable
private fun DriverNoteDialog(vm: PitlaneViewModel, d: RaceResult, cur: DriverNote?, close: () -> Unit) {
    var tag by remember { mutableStateOf(cur?.tag ?: "") }
    var note by remember { mutableStateOf(cur?.note ?: "") }
    var busy by remember { mutableStateOf(false) }
    var err by remember { mutableStateOf<String?>(null) }
    fun save(t: String, n: String) { busy = true; err = null; vm.setDriverNote(d.k, d.name, t, n) { e -> busy = false; if (e == null) close() else err = e } }
    AlertDialog(
        onDismissRequest = close,
        title = { Column { Text(t("driver_note"), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Black); Text(d.name, fontWeight = FontWeight.Black) } },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                listOf("danger", "careful", "clean", "friend").forEach { tg ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).border(1.dp, if (tag == tg) Accent else Line, RoundedCornerShape(10.dp))
                        .background(if (tag == tg) Accent.copy(alpha = .12f) else Color.Transparent).clickable { tag = if (tag == tg) "" else tg }.padding(10.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        TagIcon(tg, 18.dp)
                        Spacer(Modifier.width(10.dp))
                        Column { Text(t("tag_$tg"), fontWeight = FontWeight.Bold, fontSize = 13.sp); Text(t("tag_${tg}_hint"), color = Muted, fontSize = 11.sp) }
                    }
                }
                OutlinedTextField(note, { if (it.length <= 500) note = it }, placeholder = { Text(t("driver_note_hint"), fontSize = 12.sp) }, minLines = 2, modifier = Modifier.fillMaxWidth())
                err?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
            }
        },
        confirmButton = { TextButton({ save(tag, note.trim()) }, enabled = !busy) { Text(t("save"), color = Accent) } },
        dismissButton = {
            Row {
                if (cur != null) TextButton({ save("", "") }, enabled = !busy) { Text(t("remove"), color = Bad) }
                TextButton(close) { Text(t("cancel"), color = Muted) }
            }
        }
    )
}

// ---------- Analysis ----------
/**
 * Analysis, as on the PC and the web: Laps (the laps of the session you chose), Coach (its best lap against the model's
 * next level), My sessions (every session in the account, filtered like the web's "Choose a session") and My races.
 */
@Composable
private fun Analysis(vm: PitlaneViewModel, nav: NavHostController) {
    val s by vm.sessions.collectAsState()
    val b by vm.bests.collectAsState()
    val l by vm.laps.collectAsState()
    val co by vm.coach.collectAsState()
    val r by vm.races.collectAsState()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    // the tab a session chosen in My sessions opens: Laps, or the Coach when you came from it
    var pickFor by rememberSaveable { mutableIntStateOf(0) }
    var onlyBest by rememberSaveable { mutableStateOf(false) }
    var fCat by rememberSaveable { mutableStateOf("") }
    var fCar by rememberSaveable { mutableStateOf("") }
    var fTrack by rememberSaveable { mutableStateOf("") }
    var fKind by rememberSaveable { mutableStateOf("") }
    var fDay by rememberSaveable { mutableStateOf("") }
    var showDays by rememberSaveable { mutableStateOf(false) }
    var pick by remember(co.data) { mutableStateOf<Int?>(null) }
    val cur = vm.session
    // Home's "See all" opens My races
    LaunchedEffect(Unit) { vm.analysisTab?.let { tab = it; vm.analysisTab = null } }
    LaunchedEffect(Unit) { if (s.data == null && !s.loading) vm.loadSessions() }
    LaunchedEffect(tab, onlyBest) {
        if (tab == 2 && onlyBest && b.data == null && !b.loading) vm.loadBests()
        if (tab == 3 && r.data == null && !r.loading) vm.loadRaces()
    }
    // Laps and the Coach open on your newest session until you choose another
    LaunchedEffect(s.data) { if (vm.session == null) s.data?.firstOrNull()?.let { vm.session = it; vm.loadLaps(it.id) } }
    LaunchedEffect(tab, cur?.id, l.data) { val x = vm.session; val ls = l.data; if (tab == 1 && x != null && ls != null && !l.loading) vm.coachFor(x, ls) }
    val open = { x: CloudSession -> vm.session = x; vm.loadLaps(x.id); tab = pickFor }
    Screen(t("analysis")) {
        item { Tabs(listOf(t("tab_laps"), t("tab_coach"), t("tab_my_sessions"), t("tab_my_races")), tab) { tab = it; if (it < 2) pickFor = it } }
        when (tab) {
            0, 1 -> {
                if (cur == null) {
                    state(s) { vm.loadSessions() }
                    if (s.data != null) item { Empty(t("no_sessions")) }
                } else {
                    val from = tab
                    item { SessionHead(cur) { pickFor = from; tab = 2 } }
                    state(l) { vm.loadLaps(cur.id) }
                    val ls = l.data
                    if (tab == 0) { if (ls != null) lapItems(vm, nav, cur, ls) }
                    else if (ls != null) {
                        if (ls.none { it.valid && it.time > 0 }) item { Empty(t("coach_no_lap")) }
                        else {
                            state(co) { vm.coachKey = ""; vm.coachFor(cur, ls) }
                            val an = co.data
                            if (an != null && vm.coachKey.startsWith(cur.id + "|")) coachItems(an, pick, vm) { pick = it }
                        }
                    }
                }
            }
            2 -> {
                item { Row(verticalAlignment = Alignment.CenterVertically) { Chip(t("only_fastest"), onlyBest) { onlyBest = !onlyBest } } }
                if (onlyBest) {
                    state(b) { vm.loadBests() }
                    val list = b.data
                    if (list != null && list.isEmpty()) item { Empty(t("no_sessions")) }
                    items(list ?: emptyList()) { x ->
                        Panel(Modifier.clickable(enabled = x.bestSessionId != null) {
                            open(CloudSession(x.bestSessionId!!, x.last, x.track, x.trackConfig, x.car, "", x.laps, x.best))
                        }) {
                            Text(x.track + if (x.trackConfig.isNotBlank()) " · " + x.trackConfig else "", fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Text(x.car, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                                Text(listOf(day(x.last), t("laps_n", x.laps)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp)
                                Text(lapTime(x.best), color = Purple, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                } else {
                    state(s) { vm.loadSessions() }
                    val all = s.data ?: emptyList()
                    // many cars, tracks and sessions make a long list: four small menus (discipline, kind of session, car, track)
                    // and the days you drove behind one button, like the web's "Choose a session". A car or a track is known by its
                    // name without accents or broken characters, so one track never shows twice
                    val trackName = { x: CloudSession -> fixText(x.track) + (if (x.trackConfig.isNotBlank()) " · " + fixText(x.trackConfig) else "") }
                    val trackOf = { x: CloudSession -> nameKey(trackName(x)) }
                    val carOf = { x: CloudSession -> nameKey(carFam(x.car)) }
                    val zone = java.time.ZoneId.systemDefault()
                    val dayOf = { x: CloudSession -> java.time.Instant.ofEpochMilli(x.started).atZone(zone).toLocalDate().let { "${it.year}-${it.monthValue}-${it.dayOfMonth}" } }
                    val match = { x: CloudSession, skip: String ->
                        (skip == "cat" || fCat.isEmpty() || x.cat == fCat) && (skip == "car" || fCar.isEmpty() || carOf(x) == fCar) && (skip == "track" || fTrack.isEmpty() || trackOf(x) == fTrack) &&
                            (skip == "kind" || fKind.isEmpty() || kindOf(x.kind) == fKind) && (skip == "day" || fDay.isEmpty() || dayOf(x) == fDay)
                    }
                    val forCat = all.filter { match(it, "cat") }
                    val forKind = all.filter { match(it, "kind") }
                    val forCar = all.filter { match(it, "car") }
                    val forTrack = all.filter { match(it, "track") }
                    val forDay = all.filter { match(it, "day") }
                    val group = { g: List<CloudSession>, key: (CloudSession) -> String, name: (CloudSession) -> String ->
                        g.groupBy(key).map { (k, v) -> Triple(k, name(v.first()), v.size) }.sortedBy { it.second.lowercase() }
                    }
                    if (all.size > 1) item {
                        Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                FilterMenu(t("lic_all_full"), forCat.size, DISCS.filter { k -> all.any { it.cat == k } }.map { k -> Triple(k, discName(k), forCat.count { it.cat == k }) }, fCat, Modifier.weight(1f)) { fCat = it }
                                FilterMenu(t("kind_all"), forKind.size, listOf("race", "qual", "prac", "test").map { k -> Triple(k, t("filt_$k"), forKind.count { kindOf(it.kind) == k }) }.filter { it.third > 0 || it.first == fKind }, fKind, Modifier.weight(1f)) { fKind = it }
                            }
                            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                                FilterMenu(t("every_car"), forCar.size, group(forCar, carOf) { carFam(it.car) }, fCar, Modifier.weight(1f)) { fCar = it }
                                FilterMenu(t("every_track"), forTrack.size, group(forTrack, trackOf, trackName), fTrack, Modifier.weight(1f)) { fTrack = it }
                            }
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                TextButton({ showDays = !showDays }) { Text((if (fDay.isEmpty()) t("days_drove") else t("days_drove") + " · " + fDay) + if (showDays) " ▴" else " ▾", color = Accent, fontSize = 13.sp) }
                                Spacer(Modifier.weight(1f))
                                if ((fCat + fCar + fTrack + fKind + fDay).isNotEmpty()) TextButton({ fCat = ""; fCar = ""; fTrack = ""; fKind = ""; fDay = "" }) {
                                    Text(t("clear_filters") + " · " + all.count { match(it, "") } + "/" + all.size, color = Accent, fontSize = 13.sp)
                                }
                            }
                            if (showDays) Panel { DayGrid(forDay.groupingBy(dayOf).eachCount(), fDay) { fDay = if (fDay == it) "" else it } }
                        }
                    }
                    val list = s.data?.let { all.filter { x -> match(x, "") } }
                    if (list != null && list.isEmpty()) item { Empty(t("no_sessions")) }
                    items(list ?: emptyList(), key = { it.id }) { x -> SessionRow(x, x.id == cur?.id) { open(x) } }
                }
            }
            else -> {
                state(r) { vm.loadRaces() }
                val races = r.data ?: emptyList()
                if (r.data != null && races.isEmpty()) item { Empty(t("no_races")) }
                if (races.isNotEmpty()) item { IrTrend(races, vm.ratings()) { x -> vm.race = x; nav.navigate("race") } }
                items(races) { x -> RaceRow(x) { vm.race = x; nav.navigate("race") } }
            }
        }
    }
}

/** A session in My sessions: its track, car, kind, day and laps, your best lap, and who drove it in DRINKS mode. */
@Composable
private fun SessionRow(x: CloudSession, on: Boolean, onClick: () -> Unit) {
    Panel(Modifier.clickable(onClick = onClick).then(if (on) Modifier.border(1.dp, Accent, MaterialTheme.shapes.small) else Modifier)) {
        Text(fixText(x.track) + if (x.trackConfig.isNotBlank()) " · " + fixText(x.trackConfig) else "", fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(fixText(x.car), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        SessionBadges(x)
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f, fill = false)) {
                Text(listOf(kindText(x.kind), day(x.started), t("laps_n", x.laps)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                LicBadge(x.lic)
            }
            Text(lapTime(x.best), color = Purple, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        }
    }
}

/** "DRINKS · Ana" (or "Multiple drivers") when friends drove laps of it, and "vs AI" for a session against iRacing's AI. */
@Composable
private fun SessionBadges(x: CloudSession) {
    if (x.drvs.isEmpty() && !x.ai) return
    Row(horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.padding(top = 2.dp)) {
        if (x.drvs.isNotEmpty()) Text("DRINKS · " + (if (x.drvs.size > 1) t("drinks_multiple") else x.drvs[0]), color = Color(0xFFFFE2A8), fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp, maxLines = 1,
            modifier = Modifier.background(Accent.copy(alpha = 0.22f), RoundedCornerShape(50)).border(1.dp, Accent.copy(alpha = 0.6f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
        if (x.ai) Text(t("vs_ai"), color = Blue, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 0.4.sp, maxLines = 1,
            modifier = Modifier.border(1.dp, Blue.copy(alpha = 0.55f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
    }
}

/** The session Laps and the Coach show, with the button that opens My sessions to choose another. */
@Composable
private fun SessionHead(x: CloudSession, onChoose: () -> Unit) {
    Panel {
        Text(fixText(x.track) + if (x.trackConfig.isNotBlank()) " · " + fixText(x.trackConfig) else "", fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(fixText(x.car), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        SessionBadges(x)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp), modifier = Modifier.weight(1f)) {
                Text(listOf(kindText(x.kind), day(x.started), discName(x.cat)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                LicBadge(x.lic)
            }
            TextButton(onChoose) { Text(t("choose_session") + " ▾", color = Accent, fontSize = 12.sp, maxLines = 1) }
        }
    }
}

/** A session's laps: its best and average, then every lap with its sectors and, in DRINKS mode, its driver (tap one to analyse it). */
private fun LazyListScope.lapItems(vm: PitlaneViewModel, nav: NavHostController, x: CloudSession, laps: List<CloudLap>) {
    // your laps only: a friend's lap (DRINKS mode) is never the account's best
    val valid = laps.filter { it.valid && it.time > 0 && it.drv.isEmpty() }.ifEmpty { laps.filter { it.valid && it.time > 0 } }
    val best = valid.minOfOrNull { it.time }
    val nSec = laps.maxOfOrNull { it.sectors.size } ?: 0
    // fastest time of each sector over the valid laps, shown in purple like in the sim
    val bestSec = (0 until nSec).map { i -> valid.mapNotNull { it.sectors.getOrNull(i) }.filter { it > 0 }.minOrNull() }
    // the average of the valid laps: a real figure, not a lap made of the best sectors
    val avg = if (valid.isNotEmpty()) valid.map { it.time }.average() else null
    item {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("best"), lapTime(best), Modifier.weight(1f).fillMaxHeight(), Purple)
            Metric(t("average"), lapTime(avg), Modifier.weight(1f).fillMaxHeight())
        }
    }
    if (laps.isEmpty()) { item { Empty(t("no_laps")) }; return }
    item { Row { Section(t("laps").uppercase()); Spacer(Modifier.weight(1f)); Text(t("tap_lap"), color = Muted, fontSize = 11.sp) } }
    items(laps, key = { "l" + it.id }) { lap ->
        Panel(Modifier.clickable { vm.analyse(x, lap, laps, RefKind.MY_BEST); nav.navigate("lap") }) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("L${lap.n}", color = Muted, fontFamily = FontFamily.Monospace, modifier = Modifier.width(44.dp))
                Text(
                    lapTime(lap.time), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f),
                    color = when { !lap.valid -> Muted; lap.time == best -> Purple; else -> Fg },
                    textDecoration = if (!lap.valid) TextDecoration.LineThrough else TextDecoration.None
                )
                if (best != null && lap.valid && lap.time > best) Text("+%.3f".format(lap.time - best), color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                if (lap.inc > 0) Text("  ${lap.inc}x", color = Bad, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                if (!lap.valid) Text(t("invalid"), color = Bad, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                Icon(Icons.Default.ChevronRight, null, tint = Muted)
            }
            if (lap.drv.isNotEmpty()) Text(lap.drv, color = Accent, fontSize = 11.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (lap.sectors.isNotEmpty()) {
                Row(Modifier.fillMaxWidth().padding(top = 4.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    lap.sectors.forEachIndexed { i, sv ->
                        Text(
                            "S${i + 1} " + "%.3f".format(sv), fontSize = 11.sp, fontFamily = FontFamily.Monospace,
                            color = if (lap.valid && sv == bestSec.getOrNull(i)) Purple else Muted
                        )
                    }
                }
            }
        }
    }
}

/** A corner that costs time: its official turn, where, the phase that loses the most, the tip and what the line says.
 *  With the analysis: 👍/👎 on the tip (the coach learns from them, coachtips.js) and the corner card (where the fastest
 *  drivers here brake and how fast they take the corner, a range of real laps). */
@Composable
private fun CornerTip(k: Corner, an: LapAnalysis? = null, vm: PitlaneViewModel? = null) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(t("corner_n", k.n), fontWeight = FontWeight.Black, color = Accent)
        Text("  " + t("at_m", k.atM) + (k.phase?.let { " · " + t("phase_$it") } ?: ""), color = Muted, fontSize = 12.sp, modifier = Modifier.weight(1f))
        Text("+%.2f".format(k.lost), color = Bad, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
    }
    val tip = k.tip
    if (tip != null) {
        val ratings = vm?.tipRatings?.collectAsState()?.value
        val mine = if (an?.session != null) ratings?.get(an.session.id + ":" + k.apexM) ?: 0 else 0
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t(tip, *k.args.toTypedArray()), fontSize = 13.sp, modifier = Modifier.weight(1f))
            if (an?.session != null && vm != null) listOf(1 to "👍", -1 to "👎").forEach { (up, g) ->
                Text(g, fontSize = 12.sp, modifier = Modifier.padding(start = 4.dp).clip(RoundedCornerShape(6.dp))
                    .border(1.dp, if (mine == up) Accent else Line, RoundedCornerShape(6.dp)).clickable { vm.rateTip(an, k, up) }.padding(horizontal = 5.dp, vertical = 3.dp)
                    .alpha(if (mine == up) 1f else .55f))
            }
        }
    }
    k.lineTip?.let { lt -> Text(t(lt, *k.lineArgs.toTypedArray()), fontSize = 12.sp, color = Accent) }
    // how many drivers this tip helped on corners like this, when the admin lets the tips say it
    val ci = an?.coach
    if (ci != null && ci.confidence && tip != null) ci.conf[tip.removePrefix("tip_") + "|" + k.cls]?.let { (win, n) -> if (n >= ci.min) Text(t("tip_helped", win, n), fontSize = 11.sp, color = Muted) }
    an?.let { CornerCard.of(it.corners, k.apexM) }?.let { c ->
        Text(t("corner_fast", c.b0.toInt(), c.b1.toInt(), (c.v0 * 3.6).toInt(), (c.v1 * 3.6).toInt(), c.n), fontSize = 11.sp, color = Muted, lineHeight = 15.sp)
    }
}

/** Lap A's sectors against lap B's. */
private fun LazyListScope.sectorItems(an: LapAnalysis) {
    if (an.lap.sectors.isEmpty()) return
    item { Section(t("sectors")) }
    item {
        Panel {
            an.lap.sectors.forEachIndexed { i, sv ->
                val r = an.refSectors.getOrNull(i)
                Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
                    Text("S${i + 1}", color = Muted, fontFamily = FontFamily.Monospace, modifier = Modifier.width(40.dp))
                    Text("%.3f".format(sv), fontFamily = FontFamily.Monospace, color = Accent, modifier = Modifier.weight(1f))
                    Text(r?.let { "%.3f".format(it) } ?: "—", fontFamily = FontFamily.Monospace, color = Blue, modifier = Modifier.weight(1f))
                    Text(r?.let { "%+.3f".format(sv - it) } ?: "", fontFamily = FontFamily.Monospace, color = if (r != null && sv <= r) Good else Bad)
                }
            }
        }
    }
}

/** The coach's top card: the gap to the reference, both times and what to work on first. */
@Composable
private fun CoachGap(an: LapAnalysis, refName: String, first: Corner?, vm: PitlaneViewModel? = null) {
    val d = an.refTime?.let { an.lap.time - it }
    Card(Modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Surface), border = BorderStroke(1.dp, Line), shape = RoundedCornerShape(14.dp)) {
        Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(t("coach_vs", refName).uppercase(), color = Muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.3.sp, maxLines = 2)
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(d?.let { "%+.3f".format(it) } ?: "—", fontSize = 30.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold,
                    color = if (d == null) Fg else if (d <= 0) Good else Bad, modifier = Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.End) {
                    Text(t("you") + " · L${an.lap.n}  " + lapTime(an.lap.time), color = Accent, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                    Text(lapTime(an.refTime), color = Blue, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                }
            }
            Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Ink).padding(horizontal = 12.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(t("coach_first").uppercase(), color = Accent, fontSize = 10.sp, fontWeight = FontWeight.Bold, letterSpacing = 1.sp)
                if (first == null) Text(t("all_clean"), color = Good, fontSize = 13.sp) else CornerTip(first, an, vm)
            }
        }
    }
}

/**
 * The coach, like the web's: the gap to the reference with what to work on first, the plan, the map, the sectors and the
 * corners that cost the most (each with its four phases). The car card shows only when nobody known is ahead.
 */
private fun LazyListScope.coachItems(an: LapAnalysis, pick: Int?, vm: PitlaneViewModel? = null, onPick: (Int) -> Unit) {
    val tr = an.trace
    val refName = an.refLabel.ifBlank { t("ref") }
    val c0 = tr?.let { compare(it, an.ref) }
    val cs0 = if (c0 != null && an.ref != null) corners(c0, an.turns, an.coach?.off ?: emptySet()) else emptyList()
    val lose0 = cs0.filter { it.tip != null && it.lost > 0.03 }.sortedByDescending { it.lost }
    if (cs0.isNotEmpty()) item { CoachGap(an, refName, lose0.firstOrNull(), vm) }
    // the driver's habit first: a kind of tip that repeats on several of their tracks
    an.habits.firstOrNull()?.takeIf { it.tracks >= 3 }?.let { h -> item { Panel { Text(t("habit_line", t("kind_" + h.kind), h.tracks, h.sessions), fontSize = 13.sp) } } }
    if (cs0.isEmpty()) item {
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("you") + " · L${an.lap.n}", lapTime(an.lap.time), Modifier.weight(1f).fillMaxHeight(), Accent)
            Metric(refName, lapTime(an.refTime), Modifier.weight(1f).fillMaxHeight(), Blue)
            val d = an.refTime?.let { an.lap.time - it }
            Metric(t("delta"), d?.let { "%+.3f".format(it) } ?: "—", Modifier.weight(1f).fillMaxHeight(), if (d == null) Fg else if (d <= 0) Good else Bad)
        }
    }
    if (an.fastest) item { Text(t("coach_fastest"), color = Good, fontSize = 12.sp) }
    if (tr == null) { item { Empty(t("no_trace")) }; return }
    val c = compare(tr, an.ref)
    val cs = if (an.ref != null) corners(c, an.turns, an.coach?.off ?: emptySet()) else emptyList()
    val lose = cs.filter { it.tip != null && it.lost > 0.03 }.sortedByDescending { it.lost }
    if (an.ref == null) item { Text(t("no_reference"), color = Muted, fontSize = 12.sp) }
    else if (cs.isNotEmpty()) {
        item {
            val lost = cs.sumOf { maxOf(0.0, it.lost) }
            val gained = cs.sumOf { minOf(0.0, it.lost) }
            Text(t("coach_sum", "%.2f".format(lost), cs.size, "%.2f".format(-gained)), color = Muted, fontSize = 12.sp)
        }
        item { Section(t("corners_cost")) }
        item {
            Column {
                CornerStrip(cs, c.step, pick, title = false, onSel = onPick)
                val k = pick?.let { p -> cs.minByOrNull { kotlin.math.abs(it.atM / c.step - p) }?.takeIf { kotlin.math.abs(it.atM / c.step - p) <= 2 } }
                Panel(Modifier.padding(top = 8.dp)) { if (k == null) Text(t("corner_pick"), color = Muted, fontSize = 12.sp) else CornerTip(k, an, vm) }
            }
        }
        if (lose.isNotEmpty()) item {
            Panel {
                Section(t("coach_plan").uppercase())
                Text(t("coach_plan_note"), color = Muted, fontSize = 11.sp)
                lose.take(4).forEachIndexed { i, k ->
                    Row(Modifier.fillMaxWidth().padding(top = 6.dp)) {
                        Text("${i + 1}.", color = Accent, fontWeight = FontWeight.Black, modifier = Modifier.width(22.dp))
                        Column(Modifier.weight(1f)) {
                            Row {
                                Text(t("corner_n", k.n) + (k.phase?.let { " · " + t("phase_$it") } ?: ""), fontWeight = FontWeight.Bold, fontSize = 13.sp, modifier = Modifier.weight(1f))
                                Text("+%.2f s".format(k.lost), color = Bad, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                            }
                            k.tip?.let { Text(t(it, *k.args.toTypedArray()), color = Muted, fontSize = 12.sp) }
                        }
                    }
                }
            }
        }
    }
    if (tr.hasShape || an.layout != null) item { TrackMap(c, tr, pick, an.turns, an.layout, onPick) }
    sectorItems(an)
    if (lose.isNotEmpty()) {
        item { Section(t("coach_top").uppercase()) }
        items(lose.take(3)) { k ->
            Panel {
                CornerTip(k, an, vm)
                Row(Modifier.fillMaxWidth().padding(top = 6.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    PHASE_KEYS.forEach { p ->
                        val v = k.phases[p] ?: 0.0
                        Text(t("phase_$p") + " " + (if (v > 0) "+" else "") + "%.2f".format(v), fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = if (v > .03) Bad else Muted)
                    }
                }
                if (k.coastA - k.coastB > 10) Text(t("coasting") + ": ${k.coastA.toInt()} m · " + t("ref") + " ${k.coastB.toInt()} m", color = Muted, fontSize = 11.sp)
            }
        }
    }
    // what this car does on other tracks, when nobody known is ahead of this lap here
    if (an.car != null && (an.fastest || an.ref == null)) item { CarCard(an.car, tr) }
}

@Composable
private fun SessionDetail(vm: PitlaneViewModel, nav: NavHostController) {
    val x = vm.session ?: return
    val l by vm.laps.collectAsState()
    Screen(x.track, x.car, back = { nav.popBackStack() }) {
        state(l) { vm.loadLaps(x.id) }
        if (x.cat != null) item {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Text(t("viewing", x.car, discName(x.cat)), color = Muted, fontSize = 12.sp, modifier = Modifier.weight(1f, fill = false))
                LicBadge(x.lic)
            }
        }
        if (x.drvs.isNotEmpty() || x.ai) item { SessionBadges(x) }
        l.data?.let { lapItems(vm, nav, x, it) }
    }
}

@Composable
private fun LapDetail(vm: PitlaneViewModel, nav: NavHostController) {
    val x = vm.session ?: return
    val a by vm.analysis.collectAsState()
    val laps by vm.laps.collectAsState()
    var kind by rememberSaveable { mutableStateOf(RefKind.MY_BEST) }
    val an: LapAnalysis? = a.data
    // the point you touch on a chart, shared by the three charts
    var pick by remember(an) { mutableStateOf<Int?>(null) }
    Screen(t("lap_analysis") + (an?.let { " · L${it.lap.n}" } ?: ""), x.track + " · " + x.car, back = { nav.popBackStack() }) {
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("compare_with"), color = Muted, fontSize = 12.sp)
                RefKind.entries.forEach { k ->
                    FilterChip(kind == k, {
                        kind = k
                        an?.let { vm.analyse(x, it.lap, laps.data ?: emptyList(), k) }
                    }, label = { Text(when (k) { RefKind.MY_BEST -> t("my_best"); RefKind.LEVEL -> "▲ " + t("next_level"); RefKind.RECORD -> "★ " + t("record") }, fontSize = 12.sp) })
                }
            }
        }
        state(a) { an?.let { vm.analyse(x, it.lap, laps.data ?: emptyList(), kind) } }
        if (an != null) {
            item {
                Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Metric(t("you"), lapTime(an.lap.time), Modifier.weight(1f).fillMaxHeight(), Accent)
                    Metric(an.refLabel.ifBlank { t("ref") }, lapTime(an.refTime), Modifier.weight(1f).fillMaxHeight(), Blue)
                    val d = an.refTime?.let { an.lap.time - it }
                    Metric(t("delta"), d?.let { "%+.3f".format(it) } ?: "—", Modifier.weight(1f).fillMaxHeight(), if (d == null) Fg else if (d <= 0) Good else Bad)
                }
            }
            // every corner as a small bar under the key facts, like the web's analyzer: press one to read it on the map and the charts
            if (an.trace != null && an.ref != null) {
                val cc = compare(an.trace, an.ref)
                val cs = corners(cc, an.turns, an.coach?.off ?: emptySet())
                if (cs.isNotEmpty()) item { CornerStrip(cs, cc.step, pick) { pick = it } }
            }
            // the car card: what this car does on other tracks (its hardest braking, where the fast drivers shift up, its
            // top speed) against this lap, like the web's coach
            if (an.car != null && an.trace != null) item { CarCard(an.car, an.trace) }
            if (an.trace == null) item { Empty(t("no_trace")) }
            else {
                val c = compare(an.trace, an.ref)
                if (an.ref == null) item { Text(t("no_reference"), color = Muted, fontSize = 12.sp) }
                val refName = an.refLabel.ifBlank { t("ref") }
                val card: @Composable (Int) -> Unit = { i -> PointCard(c, i, refName, an.lap.sectors, an.refSectors) }
                if (an.trace.hasShape || an.layout != null) item { TrackMap(c, an.trace, pick, an.turns, an.layout) { pick = it } }
                item {
                    Chart(t("speed") + " (km/h)", listOfNotNull(Series(t("you"), c.speedA, Accent), c.speedB?.let { Series(refName, it, Blue) }), c.step, { "%.0f".format(it) },
                        sel = pick, onSel = { pick = it }, card = card)
                }
                c.delta?.let { d -> item { Chart(t("delta") + " (s)", listOf(Series(t("delta"), d, Purple)), c.step, { "%+.3f".format(it) }, zero = true,
                    sel = pick, onSel = { pick = it }) } }
                item { Chart(t("inputs"), listOf(Series(t("throttle"), c.thrA, Good), Series(t("brake"), c.brkA, Bad)), c.step, { "%.0f%%".format(it * 100) }, fixedMax = 1.0,
                    sel = pick, onSel = { pick = it }) }
                if (an.ref != null) {
                    // the coach in four phases (braking, entry, apex, exit), like the web's
                    val cs = corners(c, an.turns, an.coach?.off ?: emptySet())
                    if (cs.isEmpty()) {
                        item { Section(t("where_time")) }
                        val ls = losses(c)
                        if (ls.isEmpty()) item { Empty(t("all_clean")) }
                        items(ls) { lo ->
                            Panel {
                                Row {
                                    Text(t("at_m", lo.fromM), fontWeight = FontWeight.Black, modifier = Modifier.weight(1f))
                                    Text(t("lost", "%.3f".format(lo.lost)), color = Bad, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                                }
                                Text(t("min_speed", "%.0f".format(lo.minA), "%.0f".format(lo.minB)), color = Muted, fontSize = 12.sp)
                            }
                        }
                    } else {
                        val tot = PHASE_KEYS.associateWith { k -> cs.sumOf { maxOf(0.0, it.phases[k] ?: 0.0) } }
                        val worst = tot.maxBy { it.value }
                        item { Section(t("by_phase")) }
                        item {
                            Grid(PHASE_KEYS.map { k -> val v = tot[k] ?: 0.0; MetricData(t("phase_$k"), (if (v > 0) "+" else "") + "%.2f".format(v), if (v > .03) Bad else Muted) }, columns = 4)
                        }
                        item {
                            Text(if (worst.value > .05) t("most_phase", t("phase_" + worst.key).lowercase()) else t("no_phase"), color = Muted, fontSize = 12.sp)
                        }
                        item {
                            val ca = cs.sumOf { it.coastA }
                            val cb = cs.sumOf { it.coastB }
                            Panel { InfoRow(t("coasting"), "${ca.toInt()} m · " + t("ref") + " ${cb.toInt()} m", if (ca - cb > 20) Bad else Fg) }
                        }
                        item { Section(t("where_time")) }
                        val top = cs.filter { it.tip != null }.sortedByDescending { it.lost }.take(5)
                        if (top.isEmpty()) item { Empty(t("all_clean")) }
                        items(top) { k -> Panel { CornerTip(k, an, vm) } }
                    }
                }
            }
            sectorItems(an)
        }
    }
}

/** Practice, qualifying or race, from iRacing's session type. */
private fun kindText(k: String): String {
    val x = k.lowercase()
    return when {
        "race" in x -> t("kind_race")
        "qual" in x -> t("kind_qual")
        "warm" in x -> t("kind_warm")
        "practice" in x || "test" in x || "offline" in x -> t("kind_prac")
        else -> k
    }
}

data class Series(val label: String, val values: List<Double>, val color: Color)

/**
 * A line chart over the lap distance. Tap, or touch and hold and drag, to read the values at
 * that point, like hovering in the web and PC app. The charts of a lap share the point ([sel], a
 * point index); the first one shows [card], everything at that point, the others the line and their values.
 */
@Composable
private fun Chart(
    title: String, series: List<Series>, step: Double, fmt: (Double) -> String, zero: Boolean = false, fixedMax: Double? = null,
    sel: Int? = null, onSel: ((Int) -> Unit)? = null, card: (@Composable (Int) -> Unit)? = null
) {
    var own by remember { mutableStateOf<Int?>(null) }
    Panel {
        Section(title.uppercase())
        val all = series.flatMap { it.values }.filter { it.isFinite() }
        val n = series.maxOfOrNull { it.values.size } ?: 0
        if (all.isNotEmpty() && n >= 2) ChartBody(series, step, fmt, zero, fixedMax, all, n, if (onSel != null) sel else own, card, onSel ?: { own = it })
    }
}

@Composable
private fun ChartBody(
    series: List<Series>, step: Double, fmt: (Double) -> String, zero: Boolean, fixedMax: Double?, all: List<Double>, n: Int,
    sel: Int?, card: (@Composable (Int) -> Unit)?, onSel: (Int) -> Unit
) {
    var width by remember { mutableIntStateOf(1) }
    fun pickAt(x: Float) = onSel(((x / width.coerceAtLeast(1)) * (n - 1)).roundToInt().coerceIn(0, n - 1))
    Column {
        val idx = sel?.coerceIn(0, n - 1)
        if (card != null) {
            // its place is kept before you touch, so the chart does not move under your finger
            if (idx != null) card(idx)
            else Box(Modifier.fillMaxWidth().padding(bottom = 6.dp).heightIn(min = 108.dp).background(Surface2, RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
                Text(t("hold_hint"), color = Muted, fontSize = 12.sp)
            }
        } else Row(Modifier.fillMaxWidth().padding(vertical = 4.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // the values under the finger
            if (idx == null) Text(" ", fontSize = 11.sp)
            else {
                Text("${(idx * step).roundToInt()} m", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                series.forEach { se -> se.values.getOrNull(idx)?.let { Text(se.label + " " + fmt(it), color = se.color, fontSize = 11.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold) } }
            }
        }
        val lo = if (fixedMax != null) 0.0 else if (zero) minOf(all.min(), 0.0) else all.min()
        val hi = fixedMax ?: if (zero) maxOf(all.max(), 0.0) else all.max()
        val span = (hi - lo).takeIf { it > 1e-9 } ?: 1.0
        Canvas(
            Modifier.fillMaxWidth().height(130.dp)
                .onSizeChanged { width = it.width }
                // at once: the finger down picks the point, sliding sideways follows it (up and down still scrolls)
                .pointerInput(n) { detectTapGestures(onPress = { pickAt(it.x) }) }
                .pointerInput(n) {
                    detectHorizontalDragGestures(
                        onDragStart = { pickAt(it.x) },
                        onHorizontalDrag = { change, _ -> pickAt(change.position.x); change.consume() }
                    )
                }
        ) {
            fun y(v: Double) = (size.height * (1 - ((if (v.isFinite()) v else lo) - lo) / span)).toFloat()
            if (zero) drawLine(Line, Offset(0f, y(0.0)), Offset(size.width, y(0.0)), 1f)
            series.forEach { se ->
                val vals = se.values
                if (vals.size < 2) return@forEach
                val p = Path()
                vals.forEachIndexed { i, v ->
                    val px = size.width * i / (vals.size - 1)
                    if (i == 0) p.moveTo(px, y(v)) else p.lineTo(px, y(v))
                }
                drawPath(p, se.color, style = Stroke(width = 2f))
            }
            if (idx != null) {
                val x = size.width * idx / (n - 1).coerceAtLeast(1)
                drawLine(Fg.copy(alpha = 0.6f), Offset(x, 0f), Offset(x, size.height), 1.5f)
                series.forEach { se -> se.values.getOrNull(idx)?.let { drawCircle(se.color, 4f, Offset(x, y(it))) } }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(if (fixedMax == 1.0) "0%" else fmt(lo), color = Muted, fontSize = 10.sp)
            Text("${((n - 1) * step / 1000).let { "%.1f".format(it) }} km", color = Muted, fontSize = 10.sp)
            Text(if (fixedMax == 1.0) "100%" else fmt(hi), color = Muted, fontSize = 10.sp)
        }
    }
}

/** A small on/off chip, like the web's toggles over the map. */
@Composable
private fun Chip(label: String, on: Boolean, onClick: () -> Unit) {
    Text(
        label, fontSize = 11.sp, fontWeight = FontWeight.Bold, color = if (on) Bg else Muted,
        modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(if (on) Accent else Surface2).clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 5.dp)
    )
}

// the disciplines iRacing splits its licenses into, and the license classes, like on the web
private val DISCS = listOf("oval", "sports_car", "formula_car", "dirt_oval", "dirt_road")
/** The disciplines' symbols as SVG path data (24 × 24), the same strokes as the web's DISC_IC. */
private val DISC_PATHS = mapOf(
    "oval" to "M8.5 6h7a6 6 0 0 1 6 6a6 6 0 0 1-6 6h-7a6 6 0 0 1-6-6a6 6 0 0 1 6-6zM9.5 10h5a2 2 0 0 1 2 2a2 2 0 0 1-2 2h-5a2 2 0 0 1-2-2a2 2 0 0 1 2-2zM12 6v4",
    "sports_car" to "M3 15.5v-2.2l2.6-.9 3-3h5.6l3.4 3 2.4.6v2.5H3zM9.3 16a1.8 1.8 0 1 1-3.6 0a1.8 1.8 0 1 1 3.6 0zM18.3 16a1.8 1.8 0 1 1-3.6 0a1.8 1.8 0 1 1 3.6 0zM9.6 9.4l-.6 3h6l-1.2-3",
    "formula_car" to "M8 4h8M7 20h10M12 4v16M11.2 9.5h1.6a1.2 1.2 0 0 1 1.2 1.2v2.6a1.2 1.2 0 0 1-1.2 1.2h-1.6a1.2 1.2 0 0 1-1.2-1.2v-2.6a1.2 1.2 0 0 1 1.2-1.2zM5.5 6h1a1 1 0 0 1 1 1v2.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM17.5 6h1a1 1 0 0 1 1 1v2.5a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1V7a1 1 0 0 1 1-1zM5.5 13.5h1a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-2.5a1 1 0 0 1 1-1zM17.5 13.5h1a1 1 0 0 1 1 1V17a1 1 0 0 1-1 1h-1a1 1 0 0 1-1-1v-2.5a1 1 0 0 1 1-1z",
    "dirt_oval" to "M7.5 6.5h4a5.5 5.5 0 0 1 5.5 5.5a5.5 5.5 0 0 1-5.5 5.5h-4A5.5 5.5 0 0 1 2 12a5.5 5.5 0 0 1 5.5-5.5zM7.5 10.5h4a1.5 1.5 0 0 1 1.5 1.5a1.5 1.5 0 0 1-1.5 1.5h-4A1.5 1.5 0 0 1 6 12a1.5 1.5 0 0 1 1.5-1.5zM19.5 8.5h.01M21.5 11.5h.01M19.8 14.5h.01M21.6 17h.01",
    "dirt_road" to "M2 15l5-6 3.5 4L14 8.5 22 15M9 21c1.5-2 4.5-2.5 5-5M4 21h.01M18 21h.01M20.5 19h.01",
)
/** The kind of a session for the filter: race, qual(ifying), prac(tice) or test (drive). */
private fun kindOf(k: String): String { val x = k.lowercase(); return if ("race" in x) "race" else if ("qual" in x) "qual" else if ("test" in x) "test" else if ("prac" in x || "warm" in x || "offline" in x) "prac" else "" }
private val LICS = listOf("R", "D", "C", "B", "A", "P")
private fun discName(k: String?) = if (k in DISCS) t("disc_$k") else ""
/** Each discipline's colour, the same as the web's Community cards. */
private fun discColor(k: String) = when (k) { "oval" -> Color(0xFFFFB02E); "sports_car" -> Color(0xFF5AA9FF); "formula_car" -> Color(0xFFB98CFF); "dirt_oval" -> Color(0xFFC99A5B); "dirt_road" -> Color(0xFF8FBF6A); else -> Fg }
private fun licColor(k: String) = when (k) { "R" -> Color(0xFFFF6363); "D" -> Color(0xFFFF8F45); "C" -> Color(0xFFF2C94C); "B" -> Color(0xFF38C97C); "A" -> Color(0xFF5C9DFF); else -> Color(0xFFC9D1DC) }

/** The license class as a small coloured square (R, D, C, B, A, Pro). */
@Composable
private fun LicBadge(k: String?, sr: String? = null) {
    if (k == null || k !in LICS) return
    val c = licColor(k)
    Text((if (k == "P") "Pro" else k) + (sr?.let { " $it" } ?: ""), color = Fg, fontSize = 10.sp, fontWeight = FontWeight.Black,
        modifier = Modifier.clip(RoundedCornerShape(4.dp)).background(c.copy(alpha = 0.55f)).border(1.5.dp, c, RoundedCornerShape(4.dp)).padding(horizontal = 5.dp, vertical = 1.dp))
}

/** Your badges, wherever your name shows: Admin, and Supporter unless you hid it. */
@Composable
private fun MyBadges(a: AccountState) {
    if (a.admin) Status("ADMIN", Accent)
    if (a.supporter && !a.supporterHidden) SupBadge()
}

/** The supporter badge: people who donate, given by hand by the owner of Pitlane HQ. */
@Composable
private fun SupBadge() {
    Text("♥ SUPPORTER", color = Color(0xFFFFD6E7), fontSize = 9.sp, fontWeight = FontWeight.Black,
        modifier = Modifier.clip(RoundedCornerShape(999.dp)).background(Color(0x55E83E8C)).border(1.dp, Color(0xAAE83E8C), RoundedCornerShape(999.dp)).padding(horizontal = 6.dp, vertical = 1.dp))
}

/** An incident as the game names it, from its points: 1x off track, 2x loss of control (or a slight contact), 4x car contact. */
private fun incName(kind: String) = t(when (kind) { "contact" -> "inc_contact"; "light" -> "inc_light"; "loss" -> "inc_loss"; else -> "inc_off" })

/**
 * The track, drawn from where the car was on this lap (Pitlane HQ records it), coloured where you gain
 * (green) or lose (red) time against the reference, like the map in the web and the PC app. Touch
 * or drag on it to read that point: the charts follow it.
 */
@Composable
private fun TrackMap(c: Compared, tr: Trace, sel: Int?, turns: List<Double> = emptyList(), road: Pair<List<Double>, List<Double>>? = null, onSel: (Int) -> Unit) {
    // the road is the reference's path when both laps have one (B runs along the middle, A beside it by how far it was
    // from B); else this lap's own; else the track's layout drawn by the community (road). Its points are the compared
    // grid's then (c.step), the trace's (tr.bin), or the lap's length over the layout's points
    val useB = c.lat != null && c.bx != null && c.by != null
    val own = tr.hasShape
    val xs = (if (useB) c.bx else if (own) tr.x else road?.first) ?: return
    val ys = (if (useB) c.by else if (own) tr.y else road?.second) ?: return
    val bin = if (useB) c.step else if (own) tr.bin else (c.speedA.size - 1) * c.step / maxOf(1, xs.size - 1)
    val incs = tr.incidents
    var showInc by rememberSaveable { mutableStateOf(true) }
    var showBrk by rememberSaveable { mutableStateOf(true) }
    var showCoach by rememberSaveable { mutableStateOf(true) }
    var showLine by rememberSaveable { mutableStateOf(true) }
    val dpx = with(LocalDensity.current) { 1.dp.toPx() }
    val brkA = remember(c) { brakePoints(c.brkA, c.step) }
    val brkB = remember(c) { brakePoints(c.brkB, c.step) }
    val rings = remember(c, turns) { if (c.delta != null) corners(c, turns).filter { it.lost > .05 } else emptyList() }
    val labelPx = with(LocalDensity.current) { 9.sp.toPx() }
    val incPaint = remember(labelPx) { android.graphics.Paint().apply { color = android.graphics.Color.rgb(0xFF, 0x63, 0x63); textSize = labelPx; isFakeBoldText = true; isAntiAlias = true } }
    val secPaint = remember(labelPx) { android.graphics.Paint().apply { color = android.graphics.Color.rgb(0xFF, 0xB0, 0x2E); textSize = labelPx * 1.1f; isFakeBoldText = true; isAntiAlias = true } }
    val n = xs.size
    val m = c.speedA.size
    val len = (n - 1) * bin
    val idxAt = { i: Int -> ((i * bin) / c.step).roundToInt().coerceIn(0, m - 1) }
    val minX = xs.min(); val maxX = xs.max(); val minY = ys.min(); val maxY = ys.max()
    var size by remember { mutableStateOf(IntSize(1, 1)) }
    fun pt(i: Int): Offset {
        val pad = 18f
        val k = minOf((size.width - 2 * pad) / maxOf(1e-6, maxX - minX).toFloat(), (size.height - 2 * pad) / maxOf(1e-6, maxY - minY).toFloat())
        val ox = (size.width - 2 * pad - (maxX - minX).toFloat() * k) / 2
        val oy = (size.height - 2 * pad - (maxY - minY).toFloat() * k) / 2
        return Offset(pad + (xs[i] - minX).toFloat() * k + ox, size.height - pad - (ys[i] - minY).toFloat() * k - oy)
    }
    fun pickAt(p: Offset) {
        var bi = 0; var bd = Float.MAX_VALUE
        for (i in 0 until n) { val q = pt(i); val d = (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y); if (d < bd) { bd = d; bi = i } }
        if (bd < 60f * 60f) onSel(idxAt(bi))
    }
    Panel {
        Section(t("track_map").uppercase())
        Canvas(
            Modifier.fillMaxWidth().height(230.dp).onSizeChanged { size = it }
                .pointerInput(n) { detectTapGestures(onPress = { pickAt(it) }) }
                .pointerInput(n) { detectDragGestures(onDragStart = { pickAt(it) }, onDrag = { change, _ -> pickAt(change.position); change.consume() }) }
        ) {
            // the track as a road with some depth: its shadow, the rim and the darker asphalt inside (like the web)
            val track = Path()
            for (i in 0 until n) { val q = pt(i); if (i == 0) track.moveTo(q.x, q.y) else track.lineTo(q.x, q.y) }
            track.close()
            drawContext.canvas.save(); drawContext.canvas.translate(1.5f * dpx, 2.5f * dpx)
            drawPath(track, Color.Black.copy(alpha = .38f), style = Stroke(width = 11f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawContext.canvas.restore()
            drawPath(track, Line.copy(red = minOf(1f, Line.red + .12f), green = minOf(1f, Line.green + .12f), blue = minOf(1f, Line.blue + .12f)), style = Stroke(width = 10f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawPath(track, Color(0xFF151A21), style = Stroke(width = 7.5f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            // the way the cars go, like iRacing's maps: an arrow beside the start/finish line, on the outside of the track
            if (n > 20) {
                val p0 = pt(0); val p1 = pt(maxOf(2, n / 60))
                val dx = p1.x - p0.x; val dy = p1.y - p0.y; val m = maxOf(1e-6f, kotlin.math.hypot(dx, dy)); val ux = dx / m; val uy = dy / m
                var nx = -uy; var ny = ux
                if ((p0.x - size.width / 2f) * nx + (p0.y - size.height / 2f) * ny < 0) { nx = -nx; ny = -ny }
                val bx = p0.x + nx * 13f * dpx; val by = p0.y + ny * 13f * dpx; val tx = bx + ux * 18f * dpx; val ty = by + uy * 18f * dpx; val h = 6f * dpx
                drawLine(Bad, Offset(bx, by), Offset(tx - ux * h, ty - uy * h), strokeWidth = 2.2f * dpx, cap = StrokeCap.Round)
                val head = Path(); head.moveTo(tx, ty); head.lineTo(tx - ux * h + nx * h * .6f, ty - uy * h + ny * h * .6f); head.lineTo(tx - ux * h - nx * h * .6f, ty - uy * h - ny * h * .6f); head.close()
                drawPath(head, Bad)
            }
            // where lap A gains or loses against the reference: 48 stretches, stronger where more time changes hands
            val delta = c.delta
            if (delta != null && m > 2) {
                val segs = 48
                val vals = (0 until segs).map { j -> val a = j * (m - 1) / segs; val b = (j + 1) * (m - 1) / segs; delta[b] - delta[a] }
                val mx = maxOf(0.01, vals.maxOf { kotlin.math.abs(it) })
                for (j in 0 until segs) {
                    val v = vals[j]
                    if (kotlin.math.abs(v) < 0.003) continue
                    val i0 = (j * (n - 1) / segs); val i1 = ((j + 1) * (n - 1) / segs)
                    val p = Path()
                    for (i in i0..i1) { val q = pt(i); if (i == i0) p.moveTo(q.x, q.y) else p.lineTo(q.x, q.y) }
                    val col = if (v > 0) Bad else Good
                    drawPath(p, col.copy(alpha = (0.3 + 0.7 * minOf(1.0, kotlin.math.abs(v) / mx)).toFloat()), style = Stroke(width = 6.5f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
            }
            // the two lines: the reference along the middle, lap A beside it by how far it was from it (drawn bigger)
            val lat = c.lat
            if (showLine && lat != null) {
                val ex = 1.0f * dpx
                var run: Path? = null
                for (i in 0 until n) {
                    val v = lat.getOrElse(idxAt(i)) { Double.NaN }
                    if (v.isNaN()) { run?.let { drawPath(it, Accent, style = Stroke(width = 2.2f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round)) }; run = null; continue }
                    val i0 = maxOf(0, i - 2); val i1 = minOf(n - 1, i + 2)
                    val tx = xs[i1] - xs[i0]; val ty = ys[i1] - ys[i0]; val tm = maxOf(1e-6, kotlin.math.hypot(tx, ty))
                    val o = (v.coerceIn(-5.0, 5.0) * ex).toFloat()
                    val q = pt(i); val px = q.x + (-ty / tm).toFloat() * o; val py = q.y - (tx / tm).toFloat() * o
                    if (run == null) { run = Path(); run.moveTo(px, py) } else run.lineTo(px, py)
                }
                run?.let { drawPath(it, Accent, style = Stroke(width = 2.2f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round)) }
                drawPath(track, Color(0xFFCFE3FF).copy(alpha = .85f), style = Stroke(width = 1.3f * dpx, pathEffect = androidx.compose.ui.graphics.PathEffect.dashPathEffect(floatArrayOf(4f * dpx, 3f * dpx))))
            }
            // the sectors like the web: the start/finish line, a cut at each sector change, S1, S2, S3 in the middle of each
            val cnt = 3
            fun bar(i: Int, len: Float, col: Color, width: Float) {
                val q = pt(i); val q2 = pt((i + 3).coerceAtMost(n - 1)); val tx = q2.x - q.x; val ty = q2.y - q.y; val tm = maxOf(1e-3f, kotlin.math.hypot(tx, ty)); val nx = -ty / tm; val ny = tx / tm
                drawLine(col, Offset(q.x - nx * len, q.y - ny * len), Offset(q.x + nx * len, q.y + ny * len), width, StrokeCap.Round)
            }
            bar(0, 10f, Fg, 4f)
            for (k in 1 until cnt) bar(k * (n - 1) / cnt, 8f, Fg.copy(alpha = .8f), 2.5f)
            val cx = size.width / 2f; val cy = size.height / 2f
            for (k in 0 until cnt) {
                val i = ((k + .5f) * (n - 1) / cnt).toInt().coerceIn(0, n - 1); val q = pt(i); val q2 = pt((i + 3).coerceAtMost(n - 1))
                val tx = q2.x - q.x; val ty = q2.y - q.y; val tm = maxOf(1e-3f, kotlin.math.hypot(tx, ty)); var nx = -ty / tm; var ny = tx / tm
                if (nx * (q.x - cx) + ny * (q.y - cy) > 0) { nx = -nx; ny = -ny } // the label on the inside of the track
                drawContext.canvas.nativeCanvas.drawText("S${k + 1}", q.x + nx * 22f - labelPx * .6f, q.y + ny * 22f + labelPx * .35f, secPaint)
            }
            // the coach: the corners where you lose time against the reference
            if (showCoach) rings.forEach { k ->
                val q = pt((k.atM / bin).roundToInt().coerceIn(0, n - 1))
                drawCircle(Purple.copy(alpha = .18f), 14f, q); drawCircle(Purple, 14f, q, style = Stroke(width = 2.5f))
            }
            // where each lap brakes: you (accent), the reference (blue)
            if (showBrk) {
                brkB.forEach { d -> val q = pt((d / bin).roundToInt().coerceIn(0, n - 1)); drawCircle(Bg, 7f, q); drawCircle(Blue, 5f, q) }
                brkA.forEach { d -> val q = pt((d / bin).roundToInt().coerceIn(0, n - 1)); drawCircle(Bg, 8f, q); drawCircle(Accent, 6f, q) }
            }
            // the incidents of the lap (✕ and its points, like the game), where they happened
            if (showInc) incs.forEach { (d, pts) ->
                val q = pt((d / bin).roundToInt().coerceIn(0, n - 1))
                drawLine(Bad, Offset(q.x - 6f, q.y - 6f), Offset(q.x + 6f, q.y + 6f), 3.5f, StrokeCap.Round)
                drawLine(Bad, Offset(q.x + 6f, q.y - 6f), Offset(q.x - 6f, q.y + 6f), 3.5f, StrokeCap.Round)
                drawContext.canvas.nativeCanvas.drawText("${pts}x", q.x + 8f, q.y - 7f, incPaint)
            }
            // the point under the finger
            if (sel != null) { val i = ((sel * c.step) / bin).roundToInt().coerceIn(0, n - 1); val q = pt(i); drawCircle(Fg, 9f, q); drawCircle(Accent, 6f, q) }
        }
        // the same switches as the web and the race summary: braking, incidents, coach
        Row(Modifier.fillMaxWidth().padding(top = 6.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(t("map_braking"), showBrk) { showBrk = !showBrk }
            if (incs.isNotEmpty()) Chip("✕ " + t("map_incidents"), showInc) { showInc = !showInc }
            if (rings.isNotEmpty()) Chip("Coach", showCoach) { showCoach = !showCoach }
            if (c.lat != null) Chip(t("map_line"), showLine) { showLine = !showLine }
        }
        if (incs.isNotEmpty()) {
            val pts = incs.sumOf { it.pts }
            val by = incs.groupBy { incName(it.kind) }
            Text(t("incidents_sum", incs.size, pts) + ": " + by.entries.joinToString(" · ") { "${it.value.size} ${it.key.lowercase()}" }, color = Bad, fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp))
        }

        if (sel != null && showInc) {
            val d = sel * c.step
            incs.filter { kotlin.math.abs(it.d - d) < 60 }.forEach { e -> Text(incName(e.kind) + " (${e.pts}x)", color = Bad, fontSize = 11.sp, fontFamily = FontFamily.Monospace) }
        }
        val d = c.delta
        Text(
            if (sel != null) "${(sel * c.step).roundToInt()} m · ${"%.0f".format(c.speedA.getOrElse(sel) { 0.0 })} km/h" + (c.speedB?.getOrNull(sel)?.let { " · " + t("ref") + " ${"%.0f".format(it)}" } ?: "") + (d?.getOrNull(sel)?.let { " · %+.3f s".format(it) } ?: "")
            else if (d != null) t("map_hint") else t("map_hint_a"),
            color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace
        )
    }
}

/**
 * Everything at one point of the lap, like the box that follows the mouse on the web and the PC:
 * distance and sector, speed, throttle, brake and gear of both laps, the gap there and the sector
 * times.
 */
@Composable
private fun PointCard(c: Compared, i: Int, refName: String, sec: List<Double>, refSec: List<Double>) {
    val n = c.speedA.size
    val ns = sec.size.coerceAtMost(3).coerceAtLeast(1)
    val s = minOf(ns, i / maxOf(1, n / ns) + 1)
    val d = c.delta?.getOrNull(i)
    val mono = FontFamily.Monospace
    Column(
        Modifier.fillMaxWidth().padding(bottom = 6.dp).heightIn(min = 108.dp).background(Surface2, RoundedCornerShape(8.dp)).padding(horizontal = 10.dp, vertical = 8.dp),
        verticalArrangement = Arrangement.spacedBy(3.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("${(i * c.step).roundToInt()} m · S$s", fontWeight = FontWeight.Black, fontSize = 13.sp, fontFamily = mono, modifier = Modifier.weight(1f))
            if (d != null) Text("%+.3f s".format(d), color = if (d <= 0) Good else Bad, fontWeight = FontWeight.Bold, fontSize = 13.sp, fontFamily = mono)
        }
        Row(Modifier.fillMaxWidth()) {
            Spacer(Modifier.weight(1.4f))
            listOf("km/h", t("throttle"), t("brake"), t("gear")).forEach { h ->
                Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { Text(h, color = Muted, fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis) }
            }
        }
        PointRow(t("you"), Accent, c.speedA.getOrNull(i), c.thrA.getOrNull(i), c.brkA.getOrNull(i), c.gearA?.getOrNull(i))
        if (c.speedB != null) PointRow(refName, Blue, c.speedB.getOrNull(i), c.thrB?.getOrNull(i), c.brkB?.getOrNull(i), c.gearB?.getOrNull(i))
        val a = sec.getOrNull(s - 1)
        val b = refSec.getOrNull(s - 1)
        if (a != null) Row(Modifier.fillMaxWidth()) {
            Text("S$s", color = Muted, fontSize = 12.sp, fontFamily = mono, modifier = Modifier.weight(1.4f))
            Text("%.3f".format(a) + (b?.let { " · " + "%.3f".format(it) } ?: ""), fontSize = 12.sp, fontFamily = mono, modifier = Modifier.weight(3f))
            if (b != null) Text("%+.3f".format(a - b), color = if (a <= b) Good else Bad, fontSize = 12.sp, fontFamily = mono, fontWeight = FontWeight.Bold)
        }
    }
}

@Composable
private fun PointRow(name: String, color: Color, spd: Double?, thr: Double?, brk: Double?, gear: Double?) {
    Row(Modifier.fillMaxWidth()) {
        Box(Modifier.weight(1.4f)) { Text(name, color = color, fontSize = 12.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis) }
        listOf(spd?.let { "%.0f".format(it) }, thr?.let { "%.0f%%".format(it * 100) }, brk?.let { "%.0f%%".format(it * 100) }, gear?.let { "%.0f".format(it) })
            .forEach { v -> Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) { Text(v ?: "–", fontSize = 12.sp, fontFamily = FontFamily.Monospace, maxLines = 1) } }
    }
}

// ---------- Leagues: the hub ----------
/** The league hub (Community → Leagues), the web's on the phone: every league is a post with its disciplines (or
 *  Mixed), the days it races on a week strip, the usual start in its zone and in yours, its next race, whether it is
 *  looking for drivers, the cars, the language and who posted it. Opening a post counts a view and its Discord or
 *  website a click, once per driver and day: only the creator sees them, with the last 14 days. The server opens the
 *  hub to everyone with LEAGUES_OPEN=1; until then it answers "in development" and everyone but the admins reads
 *  that we are working on it. */
@Composable
private fun LeagueHub(vm: PitlaneViewModel, acc: AccountState) {
    val lg by vm.leagues.collectAsState()
    LaunchedEffect(Unit) { if (lg.data == null && !lg.loading) vm.loadLeagues() }
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var cat by rememberSaveable { mutableStateOf("") }
    var day by rememberSaveable { mutableIntStateOf(-1) }
    var onlyOpen by rememberSaveable { mutableStateOf(false) }
    var sortNext by rememberSaveable { mutableStateOf(true) }
    var q by rememberSaveable { mutableStateOf("") }
    var openId by rememberSaveable { mutableStateOf<String?>(null) }
    var edit by remember { mutableStateOf<League?>(null) }
    val closed = lg.error == "leagues are in development"
    val all = lg.data ?: emptyList()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (closed) Panel {
            Row(verticalAlignment = Alignment.CenterVertically) { Text(t("leagues"), fontWeight = FontWeight.Black, modifier = Modifier.weight(1f)); Status(t("in_development"), Accent) }
            Text(if (closed) t("leagues_wip") else t("leagues_admin_hub"), color = Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
        }
        if (!closed) {
            Text(t("leagues_hub_sub"), color = Muted, fontSize = 12.sp)
            Tabs(listOf(t("leagues_explore"), if (edit != null) t("leagues_edit") else t("leagues_post"), t("leagues_mine")), tab) { tab = it; if (it != 1) edit = null }
            if (tab == 1) LeagueForm(vm, edit) { edit = null; tab = 2 }
            else {
                if (lg.loading && lg.data == null) Text("…", color = Muted)
                lg.error?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
                if (tab == 0) {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Chip(t("disc_all") + " (" + all.size + ")", cat.isEmpty()) { cat = "" }
                        DISCS.forEach { k -> Chip(discName(k) + " (" + all.count { k in leagueDiscs(it) } + ")", cat == k) { cat = if (cat == k) "" else k } }
                    }
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Chip(t("league_any_day"), day < 0) { day = -1 }
                        (0..6).forEach { d -> Chip(t("wd_$d"), day == d) { day = if (day == d) -1 else d } }
                    }
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                        Chip(t("league_open"), onlyOpen) { onlyOpen = !onlyOpen }
                        Spacer(Modifier.width(6.dp))
                        Chip(t("league_sort_next"), sortNext) { sortNext = true }
                        Chip(t("league_sort_new"), !sortNext) { sortNext = false }
                    }
                    OutlinedTextField(q, { q = it }, label = { Text(t("league_search")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
                val shown = run {
                    val l = if (tab == 2) all.filter { it.mine } else all.filter { x -> (cat.isEmpty() || cat in leagueDiscs(x)) && (day < 0 || day in x.days) && (!onlyOpen || x.open) && (q.isBlank() || listOf(x.name, x.about, x.cars, x.lang, x.by).any { it.contains(q, true) }) }
                    if (tab == 0 && sortNext) l.map { it to leagueNext(it)?.toInstant()?.toEpochMilli() }.sortedWith(compareBy<Pair<League, Long?>> { it.second == null }.thenBy { it.second ?: 0L }.thenByDescending { it.first.updated }).map { it.first }
                    else l.sortedByDescending { it.created }
                }
                if (lg.data != null && shown.isEmpty()) Empty(t(if (tab == 2) "leagues_none_mine" else "leagues_none"))
                shown.forEach { x -> LeagueCard(x) { openId = x.id } }
                if (tab == 2 && shown.isNotEmpty()) Text(t("league_stats_note"), color = Muted, fontSize = 11.sp)
            }
        }
    }
    val opened = openId?.let { id -> all.find { it.id == id } }
    if (opened != null) LeagueDetail(vm, opened, acc, onClose = { openId = null }, onEdit = { edit = opened; tab = 1; openId = null })
}

/** The days it races as a week strip, the raced ones lit. */
@Composable
private fun WeekStrip(days: List<Int>) {
    Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        (0..6).forEach { d ->
            val on = d in days
            Box(Modifier.size(22.dp, 20.dp).clip(RoundedCornerShape(5.dp)).background(if (on) Accent else Surface2), contentAlignment = Alignment.Center) {
                Text(t("wd_$d").take(2), fontSize = 9.sp, fontWeight = FontWeight.Bold, color = if (on) Ink else Muted, fontFamily = FontFamily.Monospace)
            }
        }
    }
}

/** "20:30 CEST · 18:30 your time", or just the time; null without one. */
private fun leagueTimeText(x: League): String? {
    if (x.time.isBlank()) return null
    val next = leagueNext(x) ?: return x.time
    var s = x.time + " " + next.format(java.time.format.DateTimeFormatter.ofPattern("zzz", java.util.Locale.getDefault()))
    val lt = next.withZoneSameInstant(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("HH:mm"))
    if (lt != x.time) s += " · " + t("league_your_time", lt)
    return s
}

/** "Next: Thu 21:00 · in 2 d 3 h" in your time (true within a day), or "Racing now"; null without a schedule. */
private fun leagueNextText(x: League): Pair<String, Boolean>? {
    val next = leagueNext(x) ?: return null
    val dt = next.toInstant().toEpochMilli() - System.currentTimeMillis()
    if (dt <= 0) return t("league_now") to true
    val h = Math.round(dt / 3.6e6).toInt()
    val d = h / 24
    val hs = h % 24
    val ins = if (d > 0) "$d d" + (if (hs > 0) " $hs h" else "") else if (h > 0) "$h h" else "${maxOf(1, Math.round(dt / 6e4).toInt())} min"
    val local = next.withZoneSameInstant(java.time.ZoneId.systemDefault()).format(java.time.format.DateTimeFormatter.ofPattern("EEE HH:mm", java.util.Locale.getDefault()))
    return (t("league_next") + ": " + local + " · " + t("league_in", ins)) to (dt < 864e5)
}

/** One post in the hub; a tap opens it. */
@Composable
private fun LeagueCard(x: League, onOpen: () -> Unit) {
    val cs = leagueDiscs(x)
    Card(
        Modifier.fillMaxWidth().clickable(onClick = onOpen), colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, if (x.open) Good.copy(alpha = .5f) else Line), shape = MaterialTheme.shapes.small
    ) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                cs.forEach { DiscIcon(it, 26.dp) }
                Column(Modifier.weight(1f)) {
                    Text(x.name, fontWeight = FontWeight.Black)
                    Text(listOf(if (cs.size > 1) t("league_mixed") else "", x.lang, t("by_name", x.by)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp)
                }
            }
            if (x.open) Status(t("league_open"), Good)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                WeekStrip(x.days)
                Text(leagueTimeText(x) ?: t("league_no_schedule"), color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
            }
            leagueNextText(x)?.let { (s, soon) -> Text(s, color = if (soon) Good else Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold) }
            if (x.about.isNotBlank()) Text(x.about, fontSize = 13.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
            if (x.cars.isNotBlank()) Text("🏁 " + x.cars, color = Muted, fontSize = 12.sp)
            if (x.views >= 0) Text("👁 ${x.views} · ↗ ${x.clicks}", color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
        }
    }
}

/** A post opened: everything it says, its links (each counts a click), the link to share; the creator's numbers with
 *  the last 14 days, edit and remove. Opening it counts a view. */
@Composable
private fun LeagueDetail(vm: PitlaneViewModel, x: League, acc: AccountState, onClose: () -> Unit, onEdit: () -> Unit) {
    val uri = LocalUriHandler.current
    val clip = LocalClipboardManager.current
    var days by remember(x.id) { mutableStateOf<List<LeagueDay>?>(null) }
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(x.id) { if (!x.mine) vm.hitLeague(x.id, "view"); if (x.views >= 0) vm.leagueDays(x.id) { days = it } }
    val cs = leagueDiscs(x)
    AlertDialog(
        onDismissRequest = onClose,
        confirmButton = { TextButton(onClose) { Text(t("close"), color = Accent) } },
        title = { Text(x.name, fontWeight = FontWeight.Black) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    cs.forEach { DiscIcon(it, 24.dp) }
                    Text(listOf(cs.joinToString(" + ") { discName(it) }, x.lang, t("by_name", x.by)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp)
                }
                if (x.open) Status(t("league_open"), Good)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    WeekStrip(x.days)
                    Text(leagueTimeText(x) ?: t("league_no_schedule"), color = Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace)
                }
                leagueNextText(x)?.let { (s, soon) -> Text(s, color = if (soon) Good else Muted, fontSize = 12.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold) }
                if (x.about.isNotBlank()) Text(x.about, fontSize = 13.sp)
                if (x.cars.isNotBlank()) Text("🏁 " + x.cars, color = Muted, fontSize = 12.sp)
                Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    if (x.discord.isNotBlank()) Button({ if (!x.mine) vm.hitLeague(x.id, "discord"); uri.openUri(x.discord) }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("join_discord")) }
                    if (x.web.isNotBlank()) TextButton({ if (!x.mine) vm.hitLeague(x.id, "web"); uri.openUri(x.web) }) { Text(t("league_site"), color = Accent) }
                }
                TextButton({ clip.setText(AnnotatedString("https://pitlanehq.app/app?league=" + x.id)); copied = true }) { Text(if (copied) t("league_link_copied") else t("league_copy_link"), color = Accent) }
                if (x.views >= 0) {
                    Section(t("league_your_numbers"))
                    Text("👁 ${x.views} ${t("league_views")} · ↗ ${x.clicks} ${t("league_clicks")}", fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace)
                    LeagueBars(days)
                    Text(t("league_last14"), color = Muted, fontSize = 11.sp)
                }
                if (x.mine || acc.admin) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    TextButton(onEdit) { Text(t("edit"), color = Accent) }
                    TextButton({ vm.deleteLeague(x.id); onClose() }) { Text(t("remove"), color = Bad) }
                }
            }
        }
    )
}

/** The creator's last 14 days: views (amber) and clicks (blue) per day. */
@Composable
private fun LeagueBars(days: List<LeagueDay>?) {
    val by = days?.associateBy { it.day } ?: emptyMap()
    val keys = (13 downTo 0).map { java.time.LocalDate.now(java.time.ZoneOffset.UTC).minusDays(it.toLong()).toString() }
    val mx = maxOf(1, keys.maxOf { k -> maxOf(by[k]?.views ?: 0, by[k]?.clicks ?: 0) })
    Row(Modifier.fillMaxWidth().height(56.dp), horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom) {
        keys.forEach { k ->
            val v = by[k]?.views ?: 0
            val c = by[k]?.clicks ?: 0
            Row(Modifier.weight(1f).fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(1.dp), verticalAlignment = Alignment.Bottom) {
                Box(Modifier.weight(1f).fillMaxHeight(maxOf(0.04f, v.toFloat() / mx)).clip(RoundedCornerShape(2.dp)).background(Accent))
                Box(Modifier.weight(1f).fillMaxHeight(maxOf(0.04f, c.toFloat() / mx)).clip(RoundedCornerShape(2.dp)).background(Blue))
            }
        }
    }
}

/** Post a league, or edit yours: the days it races, the usual start (this phone's time zone), its disciplines, an
 *  optional Discord invite and website (one at least), the cars, the language, whether it is looking for drivers. */
@Composable
private fun LeagueForm(vm: PitlaneViewModel, edit: League?, onDone: () -> Unit) {
    var name by rememberSaveable(edit) { mutableStateOf(edit?.name ?: "") }
    var about by rememberSaveable(edit) { mutableStateOf(edit?.about ?: "") }
    var cats by rememberSaveable(edit) { mutableStateOf((edit?.let { leagueDiscs(it) } ?: emptyList()).joinToString(",")) }
    var days by rememberSaveable(edit) { mutableStateOf((edit?.days ?: emptyList()).joinToString(",")) }
    var time by rememberSaveable(edit) { mutableStateOf(edit?.time ?: "") }
    val tz = edit?.tz?.ifBlank { null } ?: java.util.TimeZone.getDefault().id
    var discord by rememberSaveable(edit) { mutableStateOf(edit?.discord ?: "") }
    var web by rememberSaveable(edit) { mutableStateOf(edit?.web ?: "") }
    var cars by rememberSaveable(edit) { mutableStateOf(edit?.cars ?: "") }
    var lang by rememberSaveable(edit) { mutableStateOf(edit?.lang ?: "") }
    var open by rememberSaveable(edit) { mutableStateOf(edit?.open ?: true) }
    var err by remember { mutableStateOf<String?>(null) }
    var busy by remember { mutableStateOf(false) }
    val catList = cats.split(",").filter { it.isNotBlank() }
    val dayList = days.split(",").filter { it.isNotBlank() }.map { it.toInt() }
    Panel {
        OutlinedTextField(name, { name = it }, label = { Text(t("league_name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Text(t("league_discs"), color = Muted, fontSize = 11.sp, modifier = Modifier.padding(top = 8.dp))
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            DISCS.forEach { k -> Chip(discName(k), k in catList) { cats = (if (k in catList) catList - k else catList + k).joinToString(",") } }
        }
        Text(t("league_days"), color = Muted, fontSize = 11.sp)
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            (0..6).forEach { d -> Chip(t("wd_$d"), d in dayList) { days = (if (d in dayList) dayList - d else dayList + d).sorted().joinToString(",") } }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(time, { time = it }, label = { Text(t("league_time")) }, placeholder = { Text("20:30") }, singleLine = true, modifier = Modifier.weight(1f))
            Column(Modifier.weight(1.4f)) {
                Text(t("league_tz"), color = Muted, fontSize = 11.sp)
                Text(tz.replace("_", " "), fontSize = 13.sp)
            }
        }
        OutlinedTextField(discord, { discord = it }, label = { Text(t("league_discord")) }, placeholder = { Text("https://discord.gg/…") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(web, { web = it }, label = { Text(t("league_web")) }, placeholder = { Text("https://…") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Text(t("league_need_link_note"), color = Muted, fontSize = 11.sp)
        OutlinedTextField(cars, { cars = it }, label = { Text(t("league_cars")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        OutlinedTextField(lang, { lang = it }, label = { Text(t("league_lang")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
            Switch(open, { open = it }, colors = SwitchDefaults.colors(checkedTrackColor = Accent))
            Text(t("league_open_f"), fontSize = 13.sp, modifier = Modifier.padding(start = 8.dp))
        }
        OutlinedTextField(about, { about = it }, label = { Text(t("league_about")) }, minLines = 3, modifier = Modifier.fillMaxWidth())
        err?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
        Button({
            err = when {
                name.trim().length < 3 -> "league_need_name"
                discord.isNotBlank() && !Regex("^https://(discord\\.gg|(www\\.)?discord\\.com/invite)/[A-Za-z0-9-]{2,40}/?$").matches(discord.trim()) -> "league_need_discord"
                web.isNotBlank() && !Regex("^https://[^\\s\"'<>]{4,190}$").matches(web.trim()) -> "league_need_web"
                discord.isBlank() && web.isBlank() -> "league_need_link"
                time.isNotBlank() && !Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(time.trim()) -> "league_bad_time"
                else -> null
            }
            if (err == null) {
                busy = true
                vm.saveLeague(edit?.id, League(edit?.id ?: "", name.trim(), about.trim(), null, discord.trim(), web.trim(), "", cars.trim(), lang.trim(), cats = catList, days = dayList, time = time.trim(), tz = tz, open = open)) { e ->
                    busy = false
                    if (e == null) onDone() else err = e
                }
            }
        }, enabled = !busy, modifier = Modifier.padding(top = 8.dp), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(if (edit != null) t("save") else t("league_publish")) }
        Text(t("league_note"), color = Muted, fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
        LeagueLimitNote(vm)
    }
}
/** How many leagues you may post (3, 10 as a supporter) and a small way to become one. */
@Composable
private fun LeagueLimitNote(vm: PitlaneViewModel) {
    val lg by vm.leagues.collectAsState()
    val lim by vm.leagueLimit.collectAsState()
    val uri = LocalUriHandler.current
    val used = t("league_used", lg.data?.count { it.mine } ?: 0, lim.limit)
    if (lim.supporter) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
            Text(used, color = Muted, fontSize = 11.sp)
            Text("  ♥ Supporter", color = Color(0xFFFF8FBF), fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        return
    }
    Text(used + ". " + t("league_more", lim.supporterLimit), color = Muted, fontSize = 11.sp, modifier = Modifier.padding(top = 4.dp))
    if (PATREON_URL.isNotEmpty()) Text("♥ " + t("league_donate"), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold,
        modifier = Modifier.padding(top = 2.dp).clickable { uri.openUri(PATREON_URL) }.padding(vertical = 4.dp))
}
// ---------- Community ----------
@Composable
private fun Community(vm: PitlaneViewModel, nav: NavHostController) {
    val c by vm.combos.collectAsState()
    val rp by vm.reports.collectAsState()
    val su by vm.setups.collectAsState()
    var tab by rememberSaveable { mutableIntStateOf(0) }
    var q by rememberSaveable { mutableStateOf("") }
    LaunchedEffect(tab) {
        when (tab) {
            0 -> if (c.data == null && !c.loading) vm.loadCombos()
            1 -> if (rp.data == null && !rp.loading) vm.loadReports()
            else -> if (su.data == null && !su.loading) vm.loadSetups()
        }
    }
    fun match(vararg s: String) = q.isBlank() || s.any { it.contains(q, true) }
    LaunchedEffect(Unit) { tab = 0 }
    var sec by rememberSaveable { mutableIntStateOf(0) }
    var cat by rememberSaveable { mutableStateOf("") }
    val acc by vm.account.collectAsState()
    val uri = LocalUriHandler.current
    Screen(t("community")) {
        item { Tabs(listOf(t("leaderboards"), t("leagues")), sec) { sec = it } }
        if (sec == 1) {
            item { LeagueHub(vm, acc) }
            return@Screen
        }
        item { WebNote(t("community_web")) }
        item { RecentRecords(vm, nav, cat) }
        // setups and shared race analyses are switched off for now: only the leaderboards, by lap time, per discipline
        item {
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Chip(t("disc_all"), cat.isEmpty()) { cat = "" }
                DISCS.forEach { k -> Chip(discName(k) + " (" + (c.data ?: emptyList()).count { it.cat == k } + ")", cat == k) { cat = if (cat == k) "" else k } }
            }
        }
        item { OutlinedTextField(q, { q = it }, label = { Text(t("search")) }, singleLine = true, modifier = Modifier.fillMaxWidth()) }
        when (tab) {
            0 -> {
                state(c) { vm.loadCombos() }
                val list = (c.data ?: emptyList()).filter { match(it.track, it.car) && (cat.isEmpty() || it.cat == cat) }
                if (c.data != null && list.isEmpty()) item { Empty(t("nothing_found")) }
                items(list, key = { "${it.trackId}-${it.carId}" }) { x ->
                    Panel(Modifier.clickable { vm.combo = x; vm.loadBoard(x); nav.navigate("combo") }) {
                        Text(x.track, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(x.car, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                            Text(listOf(discName(x.cat), t("laps_n", x.laps)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp)
                            Text(lapTime(x.best), color = Purple, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
            1 -> {
                state(rp) { vm.loadReports() }
                val list = (rp.data ?: emptyList()).filter { match(it.track, it.car, it.alias) }
                if (rp.data != null && list.isEmpty()) item { Empty(t("nothing_found")) }
                items(list, key = { it.id }) { x ->
                    Panel {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(x.track, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(x.car, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text((if (x.alias == "Anonymous") t("anonymous") else x.alias) + (if (x.mine) " · " + t("you_badge") else "") + " · " + day(x.created), color = if (x.mine) Accent else Muted, fontSize = 11.sp)
                            }
                            Column(horizontalAlignment = Alignment.End) {
                                Text(if (x.finish > 0) "P${x.finish}/${x.field}" else "—", fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                                Text(lapTime(x.best), color = Purple, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                            }
                        }
                    }
                }
            }
            else -> {
                state(su) { vm.loadSetups() }
                val list = (su.data ?: emptyList()).filter { match(it.track, it.car, it.name, it.alias) }
                if (su.data != null && list.isEmpty()) item { Empty(t("nothing_found")) }
                items(list, key = { it.id }) { x ->
                    Panel {
                        Text(x.name, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOf(x.car, x.track).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp, maxLines = 2)
                        if (x.notes.isNotBlank()) Text(x.notes, fontSize = 12.sp, maxLines = 3, overflow = TextOverflow.Ellipsis)
                        Text(x.alias + " · " + t("downloads", x.downloads) + " · " + day(x.created), color = Muted, fontSize = 11.sp)
                    }
                }
            }
        }
    }
}

/** Recent records: the fastest lap of every car and track, the newest first, with the lap it beat (filtered by the
 *  discipline chosen); a row opens its leaderboard, "Track" its track page. */
@Composable
private fun RecentRecords(vm: PitlaneViewModel, nav: NavHostController, cat: String) {
    val r by vm.records.collectAsState()
    LaunchedEffect(Unit) { if (r.data == null && !r.loading) vm.loadRecords() }
    var all by rememberSaveable { mutableStateOf(false) }
    var open by rememberSaveable { mutableStateOf("") }
    val list = (r.data ?: emptyList()).filter { cat.isEmpty() || it.cat == cat }
    fun name(a: String?) = if (a == null || a == "Anonymous") t("anonymous") else a
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f)) {
                Section(t("recent_records"))
                Text(t("recent_records_sub"), color = Muted, fontSize = 12.sp)
            }
            if (list.isNotEmpty()) Text(t("records_n", list.size), color = Muted, fontSize = 12.sp)
        }
        when {
            r.loading && r.data == null -> Text("…", color = Muted, modifier = Modifier.padding(top = 6.dp))
            r.error != null && r.data == null -> Text(t(r.error!!), color = Bad, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
            list.isEmpty() -> Text(t("no_records"), color = Muted, fontSize = 13.sp, modifier = Modifier.padding(top = 6.dp))
        }
        // each record a card: its discipline's stripe, the car and track, the time and who set it, the lap it beat as a
        // bar (longer the bigger the margin); touched, its leaderboard, its track page and its driver's profile
        val most = list.mapNotNull { x -> x.prevTime?.let { it - x.time } }.maxOrNull()?.coerceAtLeast(0.001) ?: 1.0
        (if (all) list else list.take(6)).forEach { x ->
            val on = open == x.id
            val col = discColor(x.cat ?: "")
            Column(
                Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(12.dp)).background(Ink)
                    .border(1.dp, if (on) Accent.copy(alpha = 0.45f) else Line, RoundedCornerShape(12.dp))
                    .clickable { open = if (on) "" else x.id }.padding(12.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                Row(Modifier.height(IntrinsicSize.Min), verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.width(4.dp).fillMaxHeight().clip(RoundedCornerShape(2.dp)).background(col))
                    Column(Modifier.weight(1f).padding(start = 10.dp)) {
                        Text(day(x.created) + (x.cat?.let { " · " + discName(it) } ?: ""), color = Muted, fontSize = 11.sp, maxLines = 1)
                        Text(x.car, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(x.track, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(lapTime(x.time), color = Purple, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, fontSize = 15.sp)
                        Text(name(x.alias) + (if (x.mine) " · " + t("you_badge") else ""), color = if (x.mine) Accent else Fg, fontWeight = FontWeight.SemiBold, fontSize = 12.sp, maxLines = 1)
                    }
                }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val by = x.prevTime?.let { it - x.time }
                    val f = if (by == null) 1f else (by / most).toFloat().coerceIn(0.06f, 1f)
                    Box(Modifier.weight(1f).height(6.dp).clip(RoundedCornerShape(3.dp)).background(Surface2)) {
                        Box(Modifier.fillMaxWidth(f).fillMaxHeight().background(Purple))
                    }
                    Text(if (by != null) t("record_beat", name(x.prevAlias), "%.3f".format(by)) else t("record_first"), color = Muted, fontSize = 12.sp, maxLines = 1)
                }
                if (on) Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    val btn = Modifier.weight(1f).heightIn(min = 36.dp)
                    Button({ vm.combo = x.combo; vm.loadBoard(x.combo); nav.navigate("combo") }, btn, shape = RoundedCornerShape(8.dp), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink), contentPadding = PaddingValues(4.dp)) { Text(t("rec_board"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
                    OutlinedButton({ vm.openTrack(x.trackId, x.track); nav.navigate("track") }, btn, shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, Line), contentPadding = PaddingValues(4.dp)) { Text(t("track_page_short"), color = Fg, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
                    if (x.prof) OutlinedButton({ vm.loadProfile(x.id); nav.navigate("profile") }, btn, shape = RoundedCornerShape(8.dp), border = BorderStroke(1.dp, Line), contentPadding = PaddingValues(4.dp)) { Text(t("profile"), color = Fg, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, maxLines = 1) }
                }
            }
        }
        if (list.size > 6) TextButton({ all = !all }) { Text(if (all) t("fewer") else t("show_all_n", list.size), color = Accent, fontWeight = FontWeight.Bold) }
    }
}

/** The track page: the map with the official turns and the direction arrow, how many drivers and laps the track has,
 *  and the record of every car on it. */
@Composable
private fun TrackPageScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val ref = vm.trackRef ?: return
    val p by vm.trackPage.collectAsState()
    Screen(ref.second.ifEmpty { t("track_page") }, t("track_page"), back = { nav.popBackStack() }) {
        state(p) { vm.openTrack(ref.first, ref.second) }
        val d = p.data ?: return@Screen
        item { Text(t("track_counts", d.drivers, d.laps, d.cars.size), color = Muted, fontSize = 12.sp) }
        item { Panel { TrackLayoutMap(d.layout, d.turns) } }
        item { TrackNotesPanel(vm, ref.first, d.track.ifEmpty { ref.second }) }
        item { Section(t("records_per_car")) }
        if (d.cars.isEmpty()) item { Empty(t("no_records")) }
        items(d.cars, key = { it.carId }) { x ->
            Panel(Modifier.clickable { vm.combo = x.combo; vm.loadBoard(x.combo); nav.navigate("combo") }) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(x.car, fontWeight = FontWeight.Black, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOf(discName(x.cat), (if (x.alias == "Anonymous") t("anonymous") else x.alias) + (if (x.mine) " · " + t("you_badge") else ""), t("drivers", x.n), day(x.created)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Text(lapTime(x.time), color = Purple, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                }
            }
        }
    }
}

/** A track's layout as a road with depth, its start/finish line, the direction arrow and the official turns: the
 *  same drawing as the live map, without the cars. */
@Composable
private fun TrackLayoutMap(layout: Pair<List<Double>, List<Double>>?, turns: List<Double>) {
    if (layout == null || layout.first.size < 20) { Text(t("track_no_map"), color = Muted, fontSize = 12.sp); return }
    val dpx = with(LocalDensity.current) { 1.dp.toPx() }
    val labelPx = with(LocalDensity.current) { 9.sp.toPx() }
    val turnPaint = remember(labelPx) { android.graphics.Paint().apply { color = android.graphics.Color.rgb(0x8A, 0x97, 0xA9); textSize = labelPx; isFakeBoldText = true; isAntiAlias = true; textAlign = android.graphics.Paint.Align.CENTER } }
    val xs = layout.first; val ys = layout.second; val n = xs.size
    val minX = xs.min(); val maxX = xs.max(); val minY = ys.min(); val maxY = ys.max()
    Canvas(Modifier.fillMaxWidth().height(240.dp)) {
        val pad = 22f * dpx
        val k = minOf((size.width - 2 * pad) / maxOf(1e-6, maxX - minX).toFloat(), (size.height - 2 * pad) / maxOf(1e-6, maxY - minY).toFloat())
        val ox = (size.width - 2 * pad - (maxX - minX).toFloat() * k) / 2; val oy = (size.height - 2 * pad - (maxY - minY).toFloat() * k) / 2
        fun pt(i: Int) = Offset(pad + (xs[i] - minX).toFloat() * k + ox, size.height - pad - (ys[i] - minY).toFloat() * k - oy)
        val track = Path()
        for (i in 0 until n) { val q = pt(i); if (i == 0) track.moveTo(q.x, q.y) else track.lineTo(q.x, q.y) }
        track.close()
        val w = 11f * dpx
        drawContext.canvas.save(); drawContext.canvas.translate(1.5f * dpx, 2.5f * dpx)
        drawPath(track, Color.Black.copy(alpha = .38f), style = Stroke(width = w + 2 * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawContext.canvas.restore()
        drawPath(track, Line.copy(red = minOf(1f, Line.red + .12f), green = minOf(1f, Line.green + .12f), blue = minOf(1f, Line.blue + .12f)), style = Stroke(width = w, cap = StrokeCap.Round, join = StrokeJoin.Round))
        drawPath(track, Color(0xFF151A21), style = Stroke(width = w - 3.5f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
        // the start/finish line across the road and the way the cars go beside it
        val p0 = pt(0); val p1 = pt(maxOf(2, n / 60))
        val dx = p1.x - p0.x; val dy = p1.y - p0.y; val m = maxOf(1e-6f, kotlin.math.hypot(dx, dy)); val ux = dx / m; val uy = dy / m
        var nx = -uy; var ny = ux
        if ((p0.x - size.width / 2f) * nx + (p0.y - size.height / 2f) * ny < 0) { nx = -nx; ny = -ny }
        drawLine(Color.White, Offset(p0.x - nx * w / 2, p0.y - ny * w / 2), Offset(p0.x + nx * w / 2, p0.y + ny * w / 2), strokeWidth = 3.5f * dpx)
        val bx = p0.x + nx * (w / 2 + 8 * dpx); val by = p0.y + ny * (w / 2 + 8 * dpx); val tx = bx + ux * 18f * dpx; val ty = by + uy * 18f * dpx; val h = 6f * dpx
        drawLine(Fg, Offset(bx, by), Offset(tx - ux * h, ty - uy * h), strokeWidth = 2f * dpx, cap = StrokeCap.Round)
        val head = Path(); head.moveTo(tx, ty); head.lineTo(tx - ux * h + nx * h * .6f, ty - uy * h + ny * h * .6f); head.lineTo(tx - ux * h - nx * h * .6f, ty - uy * h - ny * h * .6f); head.close()
        drawPath(head, Fg)
        // the official turns, beside the road
        turns.forEachIndexed { ti, f ->
            val i = (f * n).toInt().coerceIn(0, n - 1); val q = pt(i); val q1 = pt((i + 2) % n); val q0 = pt((i - 2 + n) % n)
            val tmx = q1.x - q0.x; val tmy = q1.y - q0.y; val tm = maxOf(1e-3f, kotlin.math.hypot(tmx, tmy))
            var qx = -tmy / tm; var qy = tmx / tm
            if ((q.x - size.width / 2) * qx + (q.y - size.height / 2) * qy < 0) { qx = -qx; qy = -qy }
            drawContext.canvas.nativeCanvas.drawText("T${ti + 1}", q.x + qx * (w / 2 + 9 * dpx), q.y + qy * (w / 2 + 9 * dpx) + labelPx * .35f, turnPaint)
        }
    }
}

@Composable
private fun ComboDetail(vm: PitlaneViewModel, nav: NavHostController) {
    val x = vm.combo ?: return
    val b by vm.board.collectAsState()
    val a by vm.account.collectAsState()
    val all = b.data ?: emptyList()
    val list = all
    val top = all.firstOrNull()?.time
    // the server marks the signed-in driver's own lap (anonymous ones too); older servers: by the public name
    val mineAll = all.indexOfFirst { it.mine }.let { i -> if (i >= 0) i else all.indexOfFirst { a.display.isNotBlank() && it.alias.equals(a.display, true) } }
    Screen(x.track, x.car, back = { nav.popBackStack() }) {
        item {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.End) {
                TextButton({ vm.openTrack(x.trackId, x.track); nav.navigate("track") }) { Text(t("track_page"), color = Accent, fontWeight = FontWeight.Bold, fontSize = 12.sp) }
            }
        }
        state(b) { vm.loadBoard(x) }
        if (b.data != null) item {
            Panel {
                if (mineAll == 0 && all.size > 1) {
                    Row(verticalAlignment = Alignment.CenterVertically) { Text("🏆 ", fontSize = 16.sp); Text(t("you_fastest"), color = Purple, fontWeight = FontWeight.Black) }
                    Text(t("you_fastest_sub", all.size, lapTime(all[0].time)), color = Muted, fontSize = 12.sp)
                } else if (mineAll >= 0) Text(t("your_position", mineAll + 1, all.size, lapTime(all[mineAll].time)), color = Accent, fontWeight = FontWeight.Bold)
                else Text(t("not_on_board"), color = Muted, fontSize = 12.sp)
                Text(listOf(discName(x.cat), t("drivers", all.size)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 11.sp)
            }
        }
        item { Section(t("fastest_drivers")) }
        items(list.size) { j ->
            val lap = list[j]
            val i = all.indexOf(lap)
            val me = i == mineAll
            Panel(if (lap.prof) Modifier.clickable { vm.loadProfile(lap.id); nav.navigate("profile") } else Modifier) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text("${i + 1}", color = if (i == 0) Purple else if (me) Accent else Muted, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.width(32.dp))
                    Column(Modifier.weight(1f)) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            Text(if (lap.alias == "Anonymous") t("anonymous") else lap.alias, fontWeight = FontWeight.Bold, color = if (me) Accent else Fg, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false),
                                textDecoration = if (lap.prof) TextDecoration.Underline else TextDecoration.None)
                            if (lap.sup) SupBadge()
                            if (lap.mine) Text(t("you_badge"), color = Accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        }
                        if (lap.sectors.isNotEmpty()) Text(lap.sectors.joinToString("  ") { "%.3f".format(it) }, color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace)
                        if (!lap.hasTrace) Text(t("trace_not_shared"), color = Muted, fontSize = 10.sp)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(lapTime(lap.time), color = if (i == 0) Purple else Fg, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                        if (top != null && i > 0) Text("+%.3f".format(lap.time - top), color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

/** A driver's profile: nickname (never the iRacing name), license classes, recent races, laps on the leaderboards. */
@Composable
private fun ProfileScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val st by vm.profile.collectAsState()
    val p = st.data
    val uri = LocalUriHandler.current
    Screen(p?.name ?: t("profile"), if (p != null) t("since", day(p.since)) else "", back = { nav.popBackStack() }) {
        if (p == null) {
            if (st.error != null) item { Empty(if (st.error!!.contains("anonymous", true)) t("anonymous_private") else t(st.error!!)) } else item { Empty(t("loading")) }
            return@Screen
        }
        item {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(p.name, fontWeight = FontWeight.Black, fontSize = 20.sp, modifier = Modifier.weight(1f, fill = false), maxLines = 2, overflow = TextOverflow.Ellipsis)
                    if (p.supporter && !(p.mine && p.supporterHidden)) SupBadge()
                }
                if (p.anonymous) Text("🔒 " + t(if (p.mine) "anon_mine" else "anon_admins_only"), color = Muted, fontSize = 12.sp)
                if (p.mine && p.supporter && p.supporterHidden) Text(t("badge_hidden"), color = Muted, fontSize = 12.sp)
                // their Discord, when they chose to show it
                if (p.discordId.isNotEmpty() && p.discordId.all { it in '0'..'9' }) Row(Modifier.padding(top = 4.dp)) {
                    Text("Discord: ", color = Muted, fontSize = 12.sp)
                    Text(if (p.discordHandle.isNotBlank()) "@" + p.discordHandle else t("discord_open"), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold,
                        modifier = Modifier.clickable { uri.openUri("https://discord.com/users/" + p.discordId) })
                }
                val ls = DISCS.filter { p.lics[it] != null }
                if (ls.isNotEmpty()) Row(Modifier.padding(top = 8.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ls.forEach { k -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) { LicBadge(p.lics[k]); Text(discName(k), fontSize = 12.sp) } }
                }
                if (p.mine && p.supporter) TextButton({ vm.setBadgeHidden(!p.supporterHidden) }) { Text(t(if (p.supporterHidden) "show_badge" else "hide_badge"), color = Accent) }
            }
        }
        // their leaderboards, records and podiums at a glance
        if (p.laps.isNotEmpty()) item {
            val recs = p.laps.count { it.pos == 1 }
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                StatTile(p.laps.size.toString(), t("boards_n"), Modifier.weight(1f))
                StatTile(recs.toString(), t("records_held"), Modifier.weight(1f), if (recs > 0) Purple else Fg)
                StatTile(p.laps.count { it.pos in 1..3 }.toString(), t("podiums_top3"), Modifier.weight(1f))
            }
        }
        item { Section(t("days_driven").uppercase() + " · " + t("days_in_6m", p.days.size)) }
        item { Panel { DayGrid(p.days) } }
        item { Section(t("recent_races").uppercase()) }
        if (p.races.isEmpty()) item { Empty(t("no_races_yet")) }
        items(p.races.size) { i ->
            val r = p.races[i]
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(listOf(day(r.whenMs), if (r.official) t("official") else "", discName(r.cat)).filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 11.sp, modifier = Modifier.weight(1f, fill = false))
                    LicBadge(r.lic)
                }
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(r.track, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(r.car, color = Muted, fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    Text(if (r.dnf) "DNF" else if (r.finish > 0) "P${r.finish}/${r.field}" else "—", fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
                }
                val dif = if (r.start > 0 && r.finish > 0) r.start - r.finish else 0
                Text(listOf(if (dif != 0) (if (dif > 0) "+" else "") + dif + " " + t("places") else "", "${r.inc}x", if (r.irChange != 0) "iR " + (if (r.irChange > 0) "+" else "") + r.irChange else "", if (r.best != null) t("best_short") + " " + lapTime(r.best) else "").filter { it.isNotBlank() }.joinToString(" · "), color = Muted, fontSize = 11.sp)
            }
        }
        item { Section(t("on_leaderboards").uppercase()) }
        if (p.laps.isEmpty()) item { Empty(t("no_laps_yet")) }
        items(p.laps.size) { i ->
            val l = p.laps[i]
            Panel(if (l.trackId > 0 && l.carId > 0) Modifier.clickable { val c = Combo(l.trackId, l.track, l.carId, l.car, 0, l.time, l.cat); vm.combo = c; vm.loadBoard(c); nav.navigate("combo") } else Modifier) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    LicBadge(l.lic)
                    Column(Modifier.weight(1f)) {
                        Text(l.track, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(listOf(l.car, discName(l.cat)).filter { it.isNotBlank() }.joinToString(" · ") + if (l.anon) " · 🔒 " + t(if (p.mine) "anon_lap_mine" else "anon_lap_admins") else "", color = Muted, fontSize = 11.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                    Column(horizontalAlignment = Alignment.End) {
                        Text(lapTime(l.time), fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                        if (l.pos > 0) Text("P${l.pos}" + if (l.of > 0) "/${l.of}" else "", color = if (l.pos == 1) Purple else Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

/** The last 26 weeks in squares, brighter the more sessions that day (keys "y-m-d" like the web). */
/** Text that came through a wrong encoding ("AutÃ³dromo") read back as it was written ("Autódromo"). */
fun fixText(s: String): String = if (s.contains('Ã') || s.contains('Â')) runCatching { String(s.toByteArray(Charsets.ISO_8859_1), Charsets.UTF_8) }.getOrNull()?.takeIf { !it.contains('\uFFFD') } ?: s else s
/** A name as a key: no accents, no case, letters and numbers only, so the same car or track is one entry. */
// one car under several badges is one car (the server's carfamily.js): the lists show the family without the brand
private val CAR_FAMS = listOf(
    "Super Formula SF23" to Regex("^Super Formula SF23\\b", RegexOption.IGNORE_CASE),
    "NASCAR Cup Series Next Gen" to Regex("^NASCAR Cup Series Next Gen\\b", RegexOption.IGNORE_CASE),
    "NASCAR Cup Series Gen 6" to Regex("^NASCAR (Cup|Monster Energy Cup) Series (Chevrolet|Ford|Toyota)\\b", RegexOption.IGNORE_CASE),
    "NASCAR Xfinity Series" to Regex("^NASCAR Xfinity\\b", RegexOption.IGNORE_CASE),
    "NASCAR Truck Series" to Regex("^NASCAR (Craftsman |Camping World |Gander (RV & )?Outdoors )?Truck\\b", RegexOption.IGNORE_CASE),
    "ARCA Menards Series" to Regex("^ARCA Menards\\b", RegexOption.IGNORE_CASE),
    "Supercars Gen3" to Regex("^Supercars?\\b.*\\bGen ?3\\b", RegexOption.IGNORE_CASE),
    "Supercars Gen2" to Regex("^Supercars? (Ford Mustang GT|Holden ZB Commodore)\\b", RegexOption.IGNORE_CASE),
    "V8 Supercars" to Regex("^V8 Supercars?\\b", RegexOption.IGNORE_CASE),
)
fun carFam(s: String): String { val n = fixText(s).trim(); return CAR_FAMS.firstOrNull { it.second.containsMatchIn(n) }?.first ?: n }
fun nameKey(s: String): String = java.text.Normalizer.normalize(fixText(s).lowercase(), java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").replace(Regex("[^a-z0-9]+"), "")

/** One small filter menu: "Every car (5)" and, when opened, each choice with how many sessions it has. */
@Composable
private fun FilterMenu(all: String, total: Int, items: List<Triple<String, String, Int>>, value: String, modifier: Modifier = Modifier, onPick: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    val cur = items.firstOrNull { it.first == value }
    Box(modifier) {
        OutlinedButton({ open = true }, Modifier.fillMaxWidth(), contentPadding = PaddingValues(horizontal = 10.dp, vertical = 6.dp),
            border = BorderStroke(1.dp, if (cur != null) Accent else Muted.copy(alpha = 0.4f))) {
            Text(cur?.let { "${it.second} (${it.third})" } ?: "$all ($total)", color = if (cur != null) Accent else Fg, fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
            Text(" ▾", color = Muted, fontSize = 12.sp)
        }
        DropdownMenu(open, { open = false }) {
            DropdownMenuItem({ Text("$all ($total)", fontWeight = if (cur == null) FontWeight.Bold else FontWeight.Normal) }, { open = false; onPick("") })
            items.forEach { (k, n, c) -> DropdownMenuItem({ Text("$n ($c)", fontWeight = if (k == value) FontWeight.Bold else FontWeight.Normal) }, { open = false; onPick(k) }) }
        }
    }
}

@Composable
private fun DayGrid(days: Map<String, Int>, selected: String = "", onDay: ((String) -> Unit)? = null) {
    val zone = java.time.ZoneId.systemDefault()
    val today = java.time.LocalDate.now(zone)
    val start = today.minusDays(((today.dayOfWeek.value - 1) + 25 * 7).toLong())
    val key = { d: java.time.LocalDate -> "${d.year}-${d.monthValue}-${d.dayOfMonth}" }
    val max = (days.values.maxOrNull() ?: 1).coerceAtLeast(1)
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        for (w in 0 until 26) Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            for (d in 0 until 7) {
                val day = start.plusDays((w * 7 + d).toLong())
                val n = if (day.isAfter(today)) -1 else days[key(day)] ?: 0
                val lv = if (n > 0) ((n.toFloat() / max) * 4).toInt().coerceIn(1, 4) else 0
                val k = key(day)
                // a day with sessions can be pressed (Analysis: only that day's sessions)
                Box(Modifier.size(if (onDay != null) 14.dp else 10.dp).clip(RoundedCornerShape(2.dp))
                    .background(if (n < 0) Color.Transparent else if (lv == 0) Surface2 else Accent.copy(alpha = 0.25f + lv * 0.18f))
                    .then(if (k == selected) Modifier.border(2.dp, Fg, RoundedCornerShape(2.dp)) else Modifier)
                    .then(if (onDay != null && n > 0) Modifier.clickable { onDay(k) } else Modifier))
            }
        }
    }
}

// ---------- Live ----------
@Composable
private fun Live(vm: PitlaneViewModel) {
    val s by vm.liveState.collectAsState()
    val notes by vm.driverNotes.collectAsState()
    var sub by rememberSaveable { mutableIntStateOf(0) }
    var lmode by rememberSaveable { mutableIntStateOf(0) }
    LaunchedEffect(Unit) { vm.loadDriverNotes() }
    DisposableEffect(Unit) {
        vm.startLive()
        onDispose { vm.stopLive() }
    }
    val (label, color) = when {
        s.link != LinkState.OPEN -> (if (s.link == LinkState.CONNECTING) t("connecting") else t("offline_s")) to Muted
        !s.pcOnline -> t("pc_offline") to Muted
        !s.simConnected -> t("pc_no_sim") to Accent
        else -> t("live_s") to Good
    }
    val uri = LocalUriHandler.current
    var codeIn by rememberSaveable { mutableStateOf("") }
    var codeErr by remember { mutableStateOf(false) }
    Screen(t("live_title")) {
        // your PC, from anywhere: Connect when it is online, Disconnect to stop the live data on this phone
        item {
            Panel {
                Text(t("your_pc_anywhere"), fontWeight = FontWeight.Black)
                when (s.mode) {
                    LiveMode.OWN -> if (s.pcOnline && s.ask == "wait") {
                        // your PC asks you there: Accept / Decline
                        var now by remember { mutableStateOf(System.currentTimeMillis()) }
                        LaunchedEffect(s.askAt) { kotlinx.coroutines.delay(61_000); now = System.currentTimeMillis() }
                        val late = now - s.askAt >= 60_000
                        Text(if (late) t("pc_no_answer") else t("accept_on_pc"), color = Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            if (late) Button({ vm.liveAskAgain() }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("try_again")) }
                            OutlinedButton({ vm.liveWatch(LiveMode.IDLE) }) { Text(t("cancel"), color = Bad) }
                        }
                    } else {
                        Text(if (s.pcOnline) t("watching_pc") else t("waiting_pc"), color = if (s.pcOnline) Good else Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                        OutlinedButton({ vm.liveWatch(LiveMode.IDLE) }) { Text(t("disconnect"), color = Bad) }
                        if (s.pcOnline && s.ask == "ok") {
                            HorizontalDivider(Modifier.padding(vertical = 10.dp), color = Line)
                            Text(t("your_code"), fontWeight = FontWeight.Bold)
                            if (s.myCode.isNotBlank()) {
                                Text(s.myCode, color = Accent, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Black, fontSize = 22.sp, letterSpacing = 2.sp, modifier = Modifier.padding(vertical = 4.dp))
                                Text(t("your_code_sub"), color = Muted, fontSize = 12.sp)
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                    TextButton({ vm.liveShare(true, true) }) { Text(t("new_code"), color = Accent) }
                                    TextButton({ vm.liveShare(false) }) { Text(t("stop_sharing"), color = Bad) }
                                }
                            } else {
                                Text(t("get_code_sub"), color = Muted, fontSize = 12.sp)
                                TextButton({ vm.liveShare(true) }) { Text(t("get_code"), color = Accent) }
                            }
                        }
                    }
                    LiveMode.CODE -> {
                        Text(t("watching_other_back"), color = Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                        Button({ vm.liveWatch(LiveMode.OWN) }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("connect")) }
                    }
                    else -> {
                        Text(if (s.pcOnline) t("pc_is_online") else t("open_pc"), color = if (s.pcOnline) Good else Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                        Button({ vm.liveWatch(LiveMode.OWN) }, enabled = s.pcOnline, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("connect")) }
                        if (System.currentTimeMillis() - s.declinedAt < 60_000) Text(t("declined_on_pc"), color = Bad, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
                    }
                }
            }
        }
        // the PC app, right under it: it is what sends the telemetry
        item { Action(t("download_pc").uppercase(), t("download_pc_sub"), Icons.Default.Computer) { uri.openUri("https://pitlanehq.app/dl/PitlaneHQ-Setup.exe") } }
        // someone else's telemetry with the code they give you
        item {
            Panel {
                Text(t("watch_other"), fontWeight = FontWeight.Black)
                if (s.mode == LiveMode.CODE) {
                    Text((if (s.pcOnline) t("watching") else t("waiting_their_pc")) + " · " + s.code.chunked(4).joinToString("-"), color = if (s.pcOnline) Good else Muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 6.dp))
                    OutlinedButton({ vm.liveWatch(LiveMode.IDLE) }) { Text(t("disconnect"), color = Bad) }
                } else {
                    Text(t("watch_other_sub"), color = Muted, fontSize = 12.sp, modifier = Modifier.padding(vertical = 6.dp))
                    OutlinedTextField(codeIn, { codeIn = it; codeErr = false }, label = { Text("ABCD-EFGH-JK") }, singleLine = true, modifier = Modifier.fillMaxWidth(), isError = codeErr)
                    if (codeErr) Text(t("code_bad"), color = Bad, fontSize = 12.sp)
                    Button({ val c = com.pitlanehq.android.data.Crypto.codeNorm(codeIn); if (com.pitlanehq.android.data.Crypto.codeOk(c)) vm.liveWatch(LiveMode.CODE, c) else codeErr = true },
                        modifier = Modifier.padding(top = 6.dp), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("watch")) }
                }
            }
        }
        if (s.mode == LiveMode.IDLE || (s.mode == LiveMode.OWN && s.ask != "ok")) return@Screen
        item { Status(label, color) }
        s.message?.let { item { Text(t(it), color = Bad, fontSize = 12.sp) } }
        // the same three tabs as the PC's Telemetry: what matters while driving, the standings, the tyres
        item { Tabs(listOf(t("tab_telemetry"), t("tab_standings"), t("tab_tyres")), sub) { sub = it } }
        when (sub) {
            0 -> {
                // Basic, Full (the lap's traces too) or Compare laps, live, like the PC and the web
                item { LiveModeBar(lmode) { lmode = it } }
                if (lmode == 2) item { LiveCompare(vm, s) }
                else {
                    item { LiveTop(s) }
                    item { LiveDeltaBar(s) }
                    if (lmode == 1) item { LiveTraces(s) }
                    item { LiveMap(vm, s) }
                    item { LiveRelative(s, notes) }
                    item { LiveFuel(s) }
                    item { LiveIncidents(s) }
                }
            }
            1 -> { item { LiveStandings(s, notes) }; item { PosHistory(s) } }
            else -> item { LiveTyres(s) }
        }
    }
}

// ---------- DRINKS mode (admins) ----------
// the admin profile: every shared lap and race analysis with the name it shows and who really
// uploaded it (anonymous items and DRINKS drivers too), and the accounts
@Composable
private fun AdminScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val st by vm.admin.collectAsState()
    LaunchedEffect(Unit) { vm.loadAdmin("status") }
    Screen(t("admin_profile"), back = { nav.popBackStack() }) {
        item {
            Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                listOf("status" to t("admin_server"), "users" to t("admin_accounts"), "sessions" to t("admin_activity_t"), "uploads" to t("admin_shared"), "blocked" to t("admin_blocked")).forEach { (k, l) ->
                    FilterChip(st.kind == k, { vm.loadAdmin(k) }, label = { Text(l) }, colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Accent, selectedLabelColor = Ink))
                }
            }
        }
        val list = st.items
        when {
            st.error != null -> item { Empty(t(st.error!!)) }
            list == null -> item { Empty(t("loading")) }
            list.isEmpty() -> item { Empty(t("admin_nothing")) }
            st.kind == "status" -> item {
                val x = list.first()
                val m = x.optJSONObject("mail") ?: org.json.JSONObject()
                val c = x.optJSONObject("counts") ?: org.json.JSONObject()
                val e = m.optJSONObject("lastError")
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Panel {
                    Text(t("admin_mail") + ": " + if (m.optBoolean("ready")) t("admin_mail_ok") + " (" + m.optString("via") + ")" else t("admin_mail_off"), fontWeight = FontWeight.Bold, color = if (m.optBoolean("ready")) Good else Bad)
                    Text(m.optString("from"), color = Muted, fontSize = 12.sp)
                    Text(t("admin_mail_last", dayTime(m.optLong("lastOk"))), color = Muted, fontSize = 12.sp)
                    if (e != null) Text(t("admin_mail_err") + ": " + listOf("message", "reply", "status", "body").map { e.optString(it) }.filter { it.isNotBlank() }.joinToString(" · "), color = Bad, fontSize = 12.sp)
                }
                val g = x.optJSONObject("config") ?: org.json.JSONObject()
                Panel {
                    Text(t("admin_counts", c.optInt("accounts"), c.optInt("verified"), c.optInt("sessions"), c.optInt("shared")), fontSize = 12.sp)
                    Text(t("admin_activity", c.optInt("new7"), c.optInt("drivers7"), c.optInt("sessions1"), c.optInt("sessions7")), color = Muted, fontSize = 12.sp)
                    Text(t("admin_community", c.optInt("boards"), c.optInt("leagues"), if (g.optBoolean("leaguesOpen")) t("admin_open") else t("admin_only")), color = Muted, fontSize = 12.sp)
                    Text(t("admin_sup", c.optInt("supporters"), c.optInt("supportersPatreon"), c.optInt("patrons")), color = Muted, fontSize = 12.sp)
                    Text(t("admin_model", c.optInt("learnt"), c.optInt("models")) + " · " + t("admin_dirty", c.optInt("modelsDirty")), color = Muted, fontSize = 12.sp)
                    Text(if (g.optBoolean("patreon")) t("admin_patreon_ok") else t("admin_patreon_off"), color = if (g.optBoolean("patreon")) Good else Bad, fontSize = 12.sp)
                }
                // the tools: the coach models learn again, the blocked sign-ins open again
                Panel {
                    Text(t("admin_tools_t"), fontWeight = FontWeight.Bold)
                    TextButton({ vm.adminTool("models") }) { Text(t("admin_rebuild"), color = Accent) }
                    TextButton({ vm.adminTool("unlock") }) { Text(t("admin_unlock", c.optInt("authFails")), color = Accent) }
                }
                }
            }
            st.kind == "sessions" -> items(list.size) { i ->
                val x = list[i]
                Panel {
                    Text(x.optString("track") + (x.optString("trackConfig").takeIf { it.isNotBlank() && it != "null" }?.let { " · $it" } ?: ""), fontWeight = FontWeight.Bold)
                    Text(x.optString("car") + " · " + kindText(x.optString("kind")) + " · " + t("laps_n", x.optInt("laps")), color = Muted, fontSize = 12.sp)
                    Text(dayTime(x.optLong("started")) + " · " + x.optString("who").takeIf { it.isNotBlank() && it != "null" }.orEmpty(), color = Muted, fontSize = 12.sp)
                }
            }
            st.kind == "blocked" -> items(list.size) { i ->
                val x = list[i]
                val a = x.optJSONObject("account")
                Panel {
                    Text(x.optString("kind") + " · " + (a?.optString("display") ?: x.optString("net").takeIf { it.isNotBlank() && it != "null" } ?: "—") + if (x.optBoolean("blocked")) " · " + t("admin_is_blocked") else "", fontWeight = FontWeight.Bold, color = if (x.optBoolean("blocked")) Bad else Fg)
                    Text(t("admin_tries", x.optInt("n")) + " · " + dayTime(x.optLong("last")), color = Muted, fontSize = 12.sp)
                    TextButton({ vm.adminUnlock("k", x.optString("k"), "blocked") }) { Text(t("admin_unblock"), color = Accent) }
                }
            }
            st.kind == "users" -> items(list.size) { i ->
                val u = list[i]
                var ask by remember { mutableStateOf(false) }
                var since by remember { mutableStateOf<String?>(null) }
                val id = u.optString("id")
                val ms = u.optLong("memberSince").takeIf { it > 0 } ?: u.optLong("created")
                Panel {
                    Text(u.optString("display", "–") + if (u.optBoolean("admin")) " · Admin" else "", fontWeight = FontWeight.Bold)
                    Text(id, color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    Text(t("admin_since", day(ms)) + if (u.optLong("memberSince") > 0) " ✎" else "", color = Muted, fontSize = 12.sp)
                    Text(t("admin_user_line", u.optInt("sessions"), u.optInt("laps"), u.optInt("guests")), color = Muted, fontSize = 12.sp)
                    // help with an account: confirm its email, turn off its two-step sign-in, sign it out, rename it, unblock it,
                    // join a DRINKS driver to it (what was shared under the driver's name goes to the account, later laps too)
                    var rename by remember { mutableStateOf<String?>(null) }
                    var linkGuest by remember { mutableStateOf<String?>(null) }
                    val guestLinks = (u.opt("guestLinked") as? String ?: "").split(",").filter { it.isNotBlank() }.map { it.substringAfter("|") } // "gid|name,…", null when none
                    if (guestLinks.isNotEmpty()) Text(t("admin_guest_linked", guestLinks.joinToString(", ")), color = Accent, fontSize = 12.sp)
                    Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        if (u.optInt("verified") != 1) TextButton({ vm.adminAccount(id, "verify") }) { Text(t("admin_verify"), color = Accent) }
                        if (u.optInt("twoFactor") == 1) TextButton({ vm.adminAccount(id, "2fa-off") }) { Text(t("admin_2fa_off"), color = Accent) }
                        TextButton({ vm.adminAccount(id, "signout") }) { Text(t("admin_signout"), color = Accent) }
                        if (u.optInt("driverLinked") == 1) TextButton({ vm.adminAccount(id, "unlink-driver") }) { Text(t("admin_unlink_driver"), color = Accent) }
                        TextButton({ rename = u.optString("display") }) { Text(t("admin_rename"), color = Accent) }
                        TextButton({ vm.adminUnlock("account", id, "users") }) { Text(t("admin_unblock"), color = Accent) }
                        TextButton({ linkGuest = "" }) { Text(t("admin_link_guest"), color = Accent) }
                        guestLinks.forEach { g -> TextButton({ vm.adminAccount(id, "unlink-guest", g) }) { Text(t("admin_unlink_guest", g), color = Accent) } }
                    }
                    linkGuest?.let { v ->
                        AlertDialog(
                            onDismissRequest = { linkGuest = null },
                            title = { Text(t("admin_link_guest")) },
                            text = { Column { Text(t("admin_link_guest_hint"), color = Muted, fontSize = 12.sp); OutlinedTextField(v, { linkGuest = it.take(32) }, singleLine = true) } },
                            confirmButton = { TextButton({ val n = v.trim(); linkGuest = null; if (n.isNotEmpty()) vm.adminAccount(id, "link-guest", n) }) { Text(t("save"), color = Accent) } },
                            dismissButton = { TextButton({ linkGuest = null }) { Text(t("cancel"), color = Muted) } }
                        )
                    }
                    rename?.let { v ->
                        AlertDialog(
                            onDismissRequest = { rename = null },
                            title = { Text(t("admin_rename")) },
                            text = { OutlinedTextField(v, { rename = it.take(32) }, singleLine = true) },
                            confirmButton = { TextButton({ val n = v.trim(); rename = null; if (n.isNotEmpty()) vm.adminAccount(id, "rename", n) }) { Text(t("save"), color = Accent) } },
                            dismissButton = { TextButton({ rename = null }) { Text(t("cancel"), color = Muted) } }
                        )
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                        TextButton({ vm.loadProfile("acct:$id"); nav.navigate("profile") }) { Text(t("profile"), color = Accent) }
                        TextButton({ since = java.time.Instant.ofEpochMilli(ms).atZone(java.time.ZoneId.systemDefault()).toLocalDate().toString() }) { Text(t("admin_set_since"), color = Accent) }
                    }
                    val sup = u.optInt("supporter") == 1
                    TextButton({ vm.adminSupporter(u.optString("id"), !sup) }) {
                        Text((if (sup) "♥ " + t("supporter_remove") else t("supporter_give")) + if (sup && u.optInt("supporterHidden") == 1) " · " + t("supporter_hidden_by") else "", color = if (sup) Color(0xFFFF8FBF) else Accent)
                    }
                    if (!u.optBoolean("admin")) TextButton({ ask = true }) { Text(t("admin_delete_account"), color = Bad) }
                }
                since?.let { v ->
                    val ok = runCatching { java.time.LocalDate.parse(v.trim()) }.getOrNull()
                    AlertDialog(
                        onDismissRequest = { since = null },
                        title = { Text(t("admin_set_since")) },
                        text = { OutlinedTextField(v, { since = it }, label = { Text(t("admin_since_hint")) }, singleLine = true, isError = ok == null) },
                        confirmButton = { TextButton({ if (ok != null) { since = null; vm.adminSince(id, ok.atTime(12, 0).atZone(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()) } }, enabled = ok != null) { Text(t("save"), color = Accent) } },
                        dismissButton = { Row { if (u.optLong("memberSince") > 0) TextButton({ since = null; vm.adminSince(id, null) }) { Text(t("admin_account_date"), color = Muted) }; TextButton({ since = null }) { Text(t("cancel"), color = Muted) } } }
                    )
                }
                if (ask) AlertDialog(
                    onDismissRequest = { ask = false },
                    text = { Text(t("admin_delete_ask", u.optString("display"))) },
                    confirmButton = { TextButton({ ask = false; vm.adminDeleteUser(u.optString("id")) }) { Text(t("delete"), color = Bad) } },
                    dismissButton = { TextButton({ ask = false }) { Text(t("cancel"), color = Muted) } }
                )
            }
            else -> items(list.size) { i ->
                val x = list[i]
                Panel {
                    Text(x.optString("track") + " · " + x.optString("car"), fontWeight = FontWeight.Bold)
                    Text((if (x.optString("kind") == "laps") t("lap") else t("race")) + " · " + lapTime(x.optDouble("time").takeIf { !it.isNaN() }), color = Muted, fontSize = 12.sp)
                    Text(t("admin_shown_as", x.optString("shownAs")) + if (x.optInt("anon") == 1) " 🔒" else "", fontSize = 12.sp)
                    Text(t("admin_real", x.optString("realUploader")), fontSize = 12.sp, fontWeight = FontWeight.Bold)
                    TextButton({ vm.adminDelete(x.optString("kind"), x.optString("id")) }) { Text(t("delete"), color = Bad) }
                }
            }
        }
    }
}

@Composable
private fun DrinksScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val s by vm.liveState.collectAsState()
    val demo by vm.demo.collectAsState()
    var name by rememberSaveable { mutableStateOf("") }
    val taken by vm.drinksTaken.collectAsState()
    DisposableEffect(Unit) {
        vm.startLive()
        onDispose { vm.stopLive() }
    }
    val d = s.drinks
    var editing by rememberSaveable { mutableStateOf<String?>(null) }
    var newName by rememberSaveable { mutableStateOf("") }
    var forgetting by rememberSaveable { mutableStateOf<String?>(null) }
    editing?.let { from ->
        AlertDialog(
            onDismissRequest = { editing = null },
            title = { Text(t("drinks_rename"), fontWeight = FontWeight.Black) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(t("drinks_rename_note", from), color = Muted, fontSize = 12.sp)
                    OutlinedTextField(newName, { newName = it.take(32) }, label = { Text(t("drinks_name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                }
            },
            confirmButton = { TextButton({ vm.renameDrinksGuest(from, newName, d?.guests ?: emptyList()); editing = null }, enabled = newName.isNotBlank() && newName.trim() != from) { Text(t("save"), color = Accent) } },
            dismissButton = { TextButton({ editing = null }) { Text(t("cancel"), color = Muted) } }
        )
    }
    forgetting?.let { g ->
        AlertDialog(
            onDismissRequest = { forgetting = null },
            title = { Text(t("drinks_forget"), fontWeight = FontWeight.Black) },
            text = { Text(t("drinks_forget_q", g), color = Muted, fontSize = 13.sp) },
            confirmButton = { TextButton({ vm.forgetDrinksGuest(g); forgetting = null }) { Text(t("drinks_forget"), color = Bad) } },
            dismissButton = { TextButton({ forgetting = null }) { Text(t("cancel"), color = Muted) } }
        )
    }
    Screen(t("drinks"), back = { nav.popBackStack() }) {
        item { Status(if (s.pcOnline) t("pc_online") else if (s.link == LinkState.CONNECTING) t("connecting") else t("pc_offline"), if (s.pcOnline) Good else Muted) }
        s.message?.let { item { Text(t(it), color = Bad, fontSize = 12.sp) } }
        item { Panel { Text(t("drinks_note"), color = Muted, fontSize = 12.sp) } }
        when {
            demo -> item { Empty(t("drinks_demo")) }
            d == null -> item { Empty(t("drinks_wait")) }
            !d.admin -> item { Empty(t("drinks_pc_admin")) }
            else -> {
                item {
                    Panel {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text(t("drinks_on"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                            Switch(d.on, { vm.setDrinks(it, d.guest, d.guestAuto) })
                        }
                        Text(t("drinks_now", d.driver.ifBlank { t("you") }), color = if (d.on) Accent else Muted, fontWeight = FontWeight.Bold)
                    }
                }
                if (d.on) {
                    item {
                        Panel {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(t("drinks_auto"), fontSize = 13.sp, modifier = Modifier.weight(1f))
                                Switch(d.guestAuto, { vm.setDrinks(true, d.guest, it) })
                            }
                            if (!d.guestAuto) {
                                taken?.let { Text(t("name_taken_drinks", it), color = Bad, fontSize = 12.sp) }
                                OutlinedTextField(name, { name = it.take(32) }, label = { Text(t("drinks_name")) }, singleLine = true, modifier = Modifier.fillMaxWidth())
                                Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.padding(top = 6.dp)) {
                                    Button({ vm.setDrinksGuest(name.trim(), d.guests); name = "" }, enabled = name.isNotBlank(), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("drinks_set")) }
                                    OutlinedButton({ vm.setDrinks(true, "", false) }) { Text(t("drinks_me")) }
                                }
                            }
                        }
                    }
                    if (!d.guestAuto && d.guests.isNotEmpty()) {
                        item { Section(t("drinks_recent")) }
                        item {
                            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                d.guests.forEach { g ->
                                    FilterChip(g.equals(d.guest, true), { vm.setDrinks(true, g, false) }, label = { Text(g) },
                                        colors = FilterChipDefaults.filterChipColors(selectedContainerColor = Accent, selectedLabelColor = Ink))
                                }
                            }
                        }
                        // change a name (the laps already shared change too) or take it off the list (they stay)
                        item {
                            Panel {
                                d.guests.forEach { g ->
                                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                                        Text(g, modifier = Modifier.weight(1f), fontWeight = FontWeight.Bold)
                                        IconButton({ editing = g; newName = g }) { Icon(Icons.Default.Edit, t("drinks_rename"), tint = Muted) }
                                        IconButton({ forgetting = g }) { Icon(Icons.Default.Close, t("drinks_forget"), tint = Muted) }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

// ---------- Settings ----------
@Composable
private fun Settings(vm: PitlaneViewModel, nav: NavHostController) {
    val a by vm.account.collectAsState()
    val d by vm.devices.collectAsState()
    val demo by vm.demo.collectAsState()
    val uri = LocalUriHandler.current
    LaunchedEffect(Unit) { if (d.data == null && !d.loading) vm.loadDevices() }
    // the Discord card is read when the screen shows and when the app comes back (from Discord's sign-in in the browser)
    LifecycleEventEffect(Lifecycle.Event.ON_START) { vm.loadDiscord() }
    Screen(t("account_tab")) {
        item { Section(t("account")) }
        item {
            Panel {
                var showMail by remember { mutableStateOf(false) }
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(a.display.ifBlank { t("driver") }, fontWeight = FontWeight.Black, fontSize = 20.sp, modifier = Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    MyBadges(a)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(if (showMail) a.email else "•".repeat(a.email.length.coerceIn(8, 14)), color = Muted, fontSize = 12.sp, modifier = Modifier.weight(1f, fill = false))
                    TextButton({ showMail = !showMail }) { Text(t(if (showMail) "hide" else "show"), color = Accent, fontSize = 12.sp) }
                }
                Text(if (a.verified) t("verified") else t("not_verified"), color = if (a.verified) Good else Accent, fontSize = 11.sp)
            }
        }
        item { TwoFactorPanel(vm, a) }
        item { Action(t("web").uppercase(), t("web_sub"), Icons.Default.OpenInBrowser) { uri.openUri(WEB_APP) } }
        if (PATREON_URL.isNotEmpty()) item { Action(t("support").uppercase(), t("support_sub"), Icons.Default.Favorite) { uri.openUri(PATREON_URL) } }
        item { Section(t("devices")) }
        state(d) { vm.loadDevices() }
        items(d.data ?: emptyList(), key = { it.id }) { dev ->
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (dev.device.contains("Android", true) || dev.device.contains("iPhone", true)) Icons.Default.PhoneAndroid else Icons.Default.Computer, null, tint = Muted)
                    Spacer(Modifier.width(10.dp))
                    Column(Modifier.weight(1f)) {
                        Text(if (dev.current) t("this_device") else dev.device.ifBlank { "—" }, fontWeight = FontWeight.Bold)
                        Text(dayTime(dev.lastSeen), color = Muted, fontSize = 11.sp)
                    }
                    if (!dev.current) TextButton({ vm.revoke(dev.id) }) { Text(t("sign_out_device"), color = Bad, fontSize = 12.sp) }
                }
            }
        }
        if ((d.data?.size ?: 0) > 1) item { TextButton({ vm.revoke("others") }) { Text(t("sign_out_others"), color = Bad) } }
        item { Section("DISCORD") }
        item { DiscordPanel(vm) }
        item { Section(t("language")) }
        item {
            Panel {
                listOf("system" to t("lang_system"), "en" to "English", "es" to "Español").forEach { (k, label) ->
                    Row(Modifier.fillMaxWidth().clickable { vm.setLanguage(k) }.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                        RadioButton(I18n.choice == k, { vm.setLanguage(k) })
                        Text(label)
                    }
                }
            }
        }
        // admins: the app as everyone sees it, to test it (everything for admins and in development hides)
        if (a.realAdmin) item {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(t("as_user"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Switch(!a.admin, { vm.setAsUser(it) })
                }
                Text(t("as_user_sub"), color = Muted, fontSize = 12.sp)
            }
        }
        if (a.admin) item { Section(t("admin_tools")) }
        if (a.signedIn) item { Action(t("my_profile").uppercase(), t("my_profile_sub"), Icons.Default.Person) { vm.loadProfile(null); nav.navigate("profile") } }
        if (a.signedIn) item { Action(t("track_notes").uppercase(), t("track_notes_sub"), Icons.Default.EditNote) { vm.loadTrackNotes(); nav.navigate("notes") } }
        if (a.admin) item { Action(t("admin_profile").uppercase(), t("admin_profile_sub"), Icons.Default.AdminPanelSettings) { nav.navigate("admin") } }
        if (a.admin) item { Action(t("drinks").uppercase(), t("drinks_sub"), Icons.Default.LocalBar) { nav.navigate("drinks") } }
        if (a.admin) item {
            Panel {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(t("demo_mode"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
                    Switch(demo, { vm.setDemo(it) })
                }
                Text(t("demo_note"), color = Muted, fontSize = 12.sp)
            }
        }
        item {
            Button(
                onClick = { vm.logout() }, modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = Surface2, contentColor = Bad)
            ) { Text(t("sign_out").uppercase(), fontWeight = FontWeight.Bold) }
        }
        item { Text(t("version", BuildConfig.VERSION_NAME.replace("-", " ")), color = Muted, fontSize = 11.sp, modifier = Modifier.fillMaxWidth()) }
    }
}

/** Account → Discord: link it with Discord's sign-in (in the browser), show it on your profile so other drivers can find
 *  you there (off until you say), or unlink it. Without Discord's sign-in on the server, the bot's /link does it. */
@Composable
private fun DiscordPanel(vm: PitlaneViewModel) {
    val st by vm.discord.collectAsState()
    val d = st.data
    val uri = LocalUriHandler.current
    var opened by remember { mutableStateOf(false) }
    var unlinking by remember { mutableStateOf(false) }
    Panel {
        if (d == null) { if (st.error == null) Text(t("loading"), color = Muted, fontSize = 12.sp) }
        else if (!d.linked) {
            Text(t("discord_intro"), color = Muted, fontSize = 12.sp)
            Spacer(Modifier.height(8.dp))
            if (d.oauth) Button({ vm.discordStart { u -> if (u != null) { uri.openUri(u); opened = true } } }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) {
                Text(t("discord_link").uppercase(), fontWeight = FontWeight.Black)
            }
            else Text(t("discord_no_oauth"), color = Muted, fontSize = 12.sp)
            if (opened) Text(t("discord_finish"), color = Accent, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp))
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (d.handle.isNotBlank()) "@" + d.handle else t("discord_linked"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f, fill = false), maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(t("discord_linked_pill"), color = Good, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1,
                    modifier = Modifier.border(1.dp, Good.copy(alpha = 0.55f), RoundedCornerShape(50)).padding(horizontal = 8.dp, vertical = 2.dp))
            }
            Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(t("discord_show"), fontSize = 13.sp, modifier = Modifier.weight(1f))
                Switch(d.shown, { vm.discordShow(it) })
            }
            Text(t("discord_show_note"), color = Muted, fontSize = 12.sp)
            OutlinedButton({ unlinking = true }, modifier = Modifier.padding(top = 8.dp)) { Text(t("discord_unlink"), color = Bad) }
        }
        st.error?.let { Text(t(it), color = Bad, fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)) }
    }
    if (unlinking) AlertDialog(
        onDismissRequest = { unlinking = false },
        text = { Text(t("discord_unlink_ask")) },
        confirmButton = { TextButton({ unlinking = false; vm.discordUnlink() }) { Text(t("discord_unlink"), color = Bad) } },
        dismissButton = { TextButton({ unlinking = false }) { Text(t("cancel"), color = Muted) } }
    )
}

/** Two-step sign-in with an authenticator app: optional, recommended. Setup: password → link/key → first code → recovery codes once. */
@Composable
private fun TwoFactorPanel(vm: PitlaneViewModel, a: AccountState) {
    val setup by vm.twoFactorSetup.collectAsState()
    val codes by vm.recoveryCodes.collectAsState()
    val err by vm.twoFactorError.collectAsState()
    var step by remember { mutableStateOf("") } // "", "pw", "off"
    var pw by remember { mutableStateOf("") }
    var code by remember { mutableStateOf("") }
    val uri = LocalUriHandler.current
    val clip = LocalClipboardManager.current
    Panel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(t("two_factor"), fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f))
            Text(if (a.twoFactor) t("two_factor_on").uppercase() else t("recommended").uppercase(), color = if (a.twoFactor) Good else Accent, fontSize = 10.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace)
        }
        Text(if (a.twoFactor) t("two_factor_is_on", a.recoveryLeft) else t("two_factor_rec"), color = Muted, fontSize = 12.sp, modifier = Modifier.padding(top = 4.dp))
        Spacer(Modifier.height(8.dp))
        if (a.twoFactor) OutlinedButton({ pw = ""; code = ""; vm.twoFactorError.value = null; step = "off" }) { Text(t("turn_off").uppercase(), color = Bad) }
        else Button({ pw = ""; code = ""; vm.twoFactorError.value = null; step = "pw" }, colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("turn_on").uppercase(), fontWeight = FontWeight.Black) }
    }
    val field: @Composable (String, Boolean) -> Unit = { label, secret ->
        OutlinedTextField(
            if (secret) pw else code, { if (secret) pw = it else code = it }, label = { Text(label) }, singleLine = true,
            visualTransformation = if (secret) PasswordVisualTransformation() else androidx.compose.ui.text.input.VisualTransformation.None,
            keyboardOptions = KeyboardOptions(keyboardType = if (secret) KeyboardType.Password else KeyboardType.Number), modifier = Modifier.fillMaxWidth()
        )
    }
    if (step == "pw" && setup == null) AlertDialog(
        onDismissRequest = { step = "" },
        title = { Text(t("turn_on") + " · " + t("two_factor"), fontWeight = FontWeight.Black) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(t("two_factor_pw"), color = Muted, fontSize = 12.sp); field(t("password"), true); err?.let { Text(t(it), color = Bad, fontSize = 12.sp) } } },
        confirmButton = { TextButton({ vm.setup2fa(pw) }, enabled = pw.isNotEmpty()) { Text(t("continue"), color = Accent) } },
        dismissButton = { TextButton({ step = "" }) { Text(t("cancel"), color = Muted) } }
    )
    setup?.let { st ->
        AlertDialog(
            onDismissRequest = { vm.twoFactorSetup.value = null; step = "" },
            title = { Text(t("two_factor"), fontWeight = FontWeight.Black) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(t("two_factor_scan"), color = Muted, fontSize = 12.sp)
                    Button({ uri.openUri(st.url) }, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Accent, contentColor = Ink)) { Text(t("open_in_app").uppercase(), fontWeight = FontWeight.Black) }
                    Text(t("key") + ": " + st.secret.chunked(4).joinToString(" "), fontFamily = FontFamily.Monospace, fontSize = 12.sp, modifier = Modifier.clickable { clip.setText(AnnotatedString(st.secret)) })
                    field(t("code"), false)
                    err?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
                }
            },
            confirmButton = { TextButton({ vm.enable2fa(code) }, enabled = code.length >= 6) { Text(t("turn_on"), color = Accent) } },
            dismissButton = { TextButton({ vm.twoFactorSetup.value = null; step = "" }) { Text(t("cancel"), color = Muted) } }
        )
    }
    codes?.let { cs ->
        AlertDialog(
            onDismissRequest = {},
            title = { Text(t("two_factor") + " · " + t("two_factor_on"), fontWeight = FontWeight.Black) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(t("two_factor_codes"), color = Muted, fontSize = 12.sp)
                    Text(cs.joinToString("\n"), fontFamily = FontFamily.Monospace, fontSize = 15.sp, modifier = Modifier.fillMaxWidth().background(Surface2).padding(10.dp))
                }
            },
            confirmButton = { TextButton({ vm.recoveryCodes.value = null; step = "" }) { Text(t("saved_them"), color = Accent, fontWeight = FontWeight.Bold) } },
            dismissButton = { TextButton({ clip.setText(AnnotatedString(cs.joinToString("\n"))) }) { Text(t("copy"), color = Muted) } }
        )
    }
    if (step == "off") AlertDialog(
        onDismissRequest = { step = "" },
        title = { Text(t("turn_off") + " · " + t("two_factor"), fontWeight = FontWeight.Black) },
        text = { Column(verticalArrangement = Arrangement.spacedBy(8.dp)) { Text(t("two_factor_off"), color = Muted, fontSize = 12.sp); field(t("password"), true); field(t("code"), false); err?.let { Text(t(it), color = Bad, fontSize = 12.sp) } } },
        confirmButton = { TextButton({ vm.disable2fa(pw, code) { step = "" } }, enabled = pw.isNotEmpty() && code.isNotBlank()) { Text(t("turn_off"), color = Bad) } },
        dismissButton = { TextButton({ step = "" }) { Text(t("cancel"), color = Muted) } }
    )
}

// ---------- pieces ----------
private data class MetricData(val label: String, val value: String, val color: Color = Fg, val sub: String? = null)

/** Metric boxes in rows of the same height, so every box lines up. */
@Composable
private fun Grid(items: List<MetricData>, columns: Int) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        items.chunked(columns).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { m -> Metric(m.label, m.value, Modifier.weight(1f).fillMaxHeight(), m.color, m.sub) }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/** Licence summary, like the web's Home: one card per discipline (its symbol and colour), your iRating with what your
 *  last races of it gave, and the licence (class and safety rating) as the PC last saw them (the game only says the
 *  discipline of the session you are in, so each updates when you drive it with Pitlane HQ open). */
@Composable
private fun Licences(vm: PitlaneViewModel) {
    val acc by vm.account.collectAsState()
    val r by vm.races.collectAsState()
    val all = remember(acc) { vm.ratings() }
    val races = r.data ?: emptyList()
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Section(t("licences"))
        DISCS.chunked(2).forEach { row ->
            Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEach { k -> LicCard(k, all[k], races, Modifier.weight(1f).fillMaxHeight()) }
                repeat(2 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
        Text(t("lic_note"), color = Muted, fontSize = 11.sp)
    }
}

/** One discipline's card: its symbol, the iRating (with what your last five races of it gave, like the web) and the
 *  licence pill ("B 3.21" in the licence's colour); dim while the PC has seen nothing of it. */
@Composable
private fun LicCard(k: String, r: Triple<Int, String, Long>?, races: List<Race>, m: Modifier) {
    val col = discColor(k)
    val last = races.filter { raceDisc(it.cat, it.car) == k && !it.ai && it.ir != 1 }.take(5) // races against the AI give no iRating
    val chg = last.sumOf { it.irChange }
    val lic = r?.second?.trim()?.uppercase() ?: ""
    val cls = lic.takeIf { it.isNotEmpty() }?.let { if (it.startsWith("WC") || it.startsWith("PRO")) "P" else it.take(1) }
    val sr = lic.split(Regex("\\s+")).getOrNull(1)
    val line = irRaces(races, k, 10)
    var sel by remember(line.size) { mutableStateOf<Int?>(null) }
    Card(
        m.alpha(if (r == null) 0.55f else 1f), colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, col.copy(alpha = 0.4f)), shape = RoundedCornerShape(12.dp)
    ) {
      Column(Modifier.fillMaxHeight()) {
        Row(Modifier.padding(start = 12.dp, end = 12.dp, top = 12.dp, bottom = if (line.size >= 2) 4.dp else 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            DiscIcon(k, 30.dp)
            Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
                Text(discName(k), color = Muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, lineHeight = 14.sp)
                Row(verticalAlignment = Alignment.Bottom, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(r?.first?.toString() ?: "–", color = if (r == null) Muted else col, fontSize = 20.sp, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, lineHeight = 22.sp)
                    if (r != null && last.isNotEmpty() && chg != 0)
                        Text(signed(chg), color = if (chg > 0) Good else Bad, fontSize = 11.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(bottom = 3.dp))
                }
                if (r != null && cls != null) LicBadge(cls, sr)
            }
        }
        // the iRating after each of its last races: the finger reads the race under it
        if (line.size >= 2) Column(Modifier.padding(start = 12.dp, end = 12.dp, bottom = 10.dp)) {
            val x = sel?.let { line.getOrNull(it) }
            Text(x?.let { it.track + " " + signed(it.irChange) } ?: t("spark_last", line.size), color = if (x == null) Muted else if (x.irChange >= 0) Good else Bad,
                fontSize = 10.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
            IrLine(irVals(line, r?.first), col, 30.dp, sel) { sel = it }
        }
      }
    }
}

/** The discipline's symbol, the same strokes as the web's (our own, never iRacing's), in a rounded square of its colour. */
@Composable
private fun DiscIcon(k: String, size: Dp) {
    val col = discColor(k)
    val d = DISC_PATHS[k] ?: return
    Box(Modifier.size(size).clip(RoundedCornerShape(8.dp)).background(col.copy(alpha = 0.12f)).border(1.5.dp, col, RoundedCornerShape(8.dp)), contentAlignment = Alignment.Center) {
        Canvas(Modifier.size(size * 0.6f)) {
            val s = this.size.width / 24f
            val path = PathParser().parsePathString(d).toPath()
            withTransform({ scale(s, s, Offset.Zero) }) { drawPath(path, col, style = Stroke(width = 1.8f, cap = StrokeCap.Round, join = StrokeJoin.Round)) }
        }
    }
}

/** Every corner as a small bar, like the web's analyzer: taller the more time it costs (red; green when it gains), its
 *  official turn number under it. Press one to read it on the map and the charts. */
@Composable
private fun CornerStrip(cs: List<Corner>, step: Double, sel: Int?, title: Boolean = true, onSel: (Int) -> Unit) {
    val mx = (cs.maxOfOrNull { kotlin.math.abs(it.lost) } ?: 0.0).coerceAtLeast(0.05)
    Panel {
        if (title) Section(t("corners_strip"))
        Row(Modifier.fillMaxWidth().padding(top = 6.dp).horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            cs.forEach { k ->
                val idx = (k.atM / step).roundToInt()
                val on = sel != null && kotlin.math.abs(sel - idx) <= 2
                val col = if (k.lost > .02) Bad else if (k.lost < -.02) Good else Muted
                Column(
                    Modifier.width(36.dp).clip(RoundedCornerShape(6.dp)).background(if (on) Surface2 else Color.Transparent).clickable { onSel(idx) }.padding(vertical = 4.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(3.dp)
                ) {
                    Box(Modifier.height(40.dp), contentAlignment = Alignment.BottomCenter) {
                        Box(Modifier.width(14.dp).height((6 + 34 * kotlin.math.abs(k.lost) / mx).dp).clip(RoundedCornerShape(3.dp)).background(col))
                    }
                    Text("T${k.n}", color = if (on) Accent else Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
                    Text((if (k.lost >= 0) "+" else "−") + "%.2f".format(kotlin.math.abs(k.lost)), color = col, fontSize = 9.sp, fontFamily = FontFamily.Monospace)
                }
            }
        }
    }
}

/** What is only in the web and PC app for now, with a button to open the web. */
/** The facts of one lap, as the server reads them: its hardest braking (m/s², the top 5 % of its braking), the speed
 *  it shifted up at in every gear (the highest point it took the gear to), its top speed. Rows [speed, throttle, brake, gear, steering, time]. */
private class LapFacts(val brake: Double?, val shifts: Map<Int, Double>, val vmax: Double)
private fun lapFacts(rows: List<DoubleArray>): LapFacts {
    val dec = ArrayList<Double>()
    val shifts = HashMap<Int, Double>()
    var vmax = 0.0
    for (i in 0 until rows.size - 1) {
        val a = rows[i]
        val b = rows[i + 1]
        if (a.size < 6 || b.size < 6) continue
        if (a[0] > vmax) vmax = a[0]
        val dt = b[5] - a[5]
        if (dt > 0.01 && dt < 2 && a[2] >= 0.5 && a[0] > 12 && a[0] > b[0]) dec.add((a[0] - b[0]) / dt)
        val g = a[3].toInt()
        if (g >= 1 && b[3].toInt() == g + 1 && a[0] > 5) shifts[g] = maxOf(shifts[g] ?: 0.0, a[0])
    }
    dec.sort()
    val brake = if (dec.size >= 5) dec[minOf(dec.size - 1, Math.floor(0.95 * (dec.size - 1) + 0.5).toInt())] else null
    return LapFacts(brake, shifts, vmax)
}

/** The car card: what this car does on other tracks (its hardest braking, where the fast drivers shift up, its top
 *  speed), learnt by the server from its laps everywhere, against what this lap did. Like the web's coach. */
@Composable
private fun CarCard(k: org.json.JSONObject, tr: Trace) {
    val f = remember(tr) { lapFacts(tr.rows) }
    val kmh = { v: Double -> "${Math.round(v * 3.6)} km/h" }
    val gee = { v: Double -> "%.2f g".format(v / 9.81) }
    val cardBrake = k.optDouble("brake", 0.0).takeIf { it > 0 }
    // the gear this lap shifted earliest against the fast drivers (the highest gear when the lap has no gear read)
    var pg = 0
    var pv = 0.0
    var pm: Double? = null
    var pd: Double? = null
    val sh = k.optJSONArray("shifts")
    if (sh != null) for (i in 0 until sh.length()) {
        val p = sh.optJSONArray(i) ?: continue
        val g = p.optInt(0)
        val v = p.optDouble(1)
        val mv = f.shifts[g]
        val d = mv?.let { it - v }
        val better = pd
        if (pg == 0 || (d != null && (better == null || d < better))) { pg = g; pv = v; pm = mv; pd = d }
    }
    val brakeLine = t("car_brake") + ": " + (cardBrake?.let(gee) ?: "—") + " · " +
        (f.brake?.let { b -> t("this_lap") + " " + gee(b) + (cardBrake?.let { c -> " (${Math.round(b / c * 100)} %)" } ?: "") } ?: t("car_no_brake"))
    val mine = pm
    val shiftLine = t("car_shifts") + ": " + if (pg > 0) "$pg→${pg + 1} ${kmh(pv)}" +
        (mine?.let { " · " + t("this_lap") + " " + kmh(it) + " (" + (if (it >= pv) "+" else "−") + Math.round(Math.abs(it - pv) * 3.6) + ")" } ?: "") else t("car_no_shifts")
    val at = k.optString("vmaxTrack").takeIf { it.isNotBlank() && it != "null" }
    val vmaxLine = t("car_vmax") + ": " + kmh(k.optDouble("vmax", 0.0)) + (at?.let { " " + t("car_at", it) } ?: "") + (if (f.vmax > 0) " · " + t("this_lap") + " " + kmh(f.vmax) else "")
    Panel {
        Text(t("car_card"), fontWeight = FontWeight.Bold)
        Text(t("car_card_from", k.optInt("n"), k.optInt("tracks")), color = Muted, fontSize = 12.sp)
        Spacer(Modifier.height(6.dp))
        Text(brakeLine, fontSize = 13.sp)
        Text(shiftLine, fontSize = 13.sp)
        Text(vmaxLine, fontSize = 13.sp)
    }
}

@Composable
private fun WebNote(text: String) {
    val uri = LocalUriHandler.current
    Panel {
        Row(verticalAlignment = Alignment.Top) {
            Icon(Icons.Default.Info, null, tint = Blue, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(8.dp))
            Column(Modifier.weight(1f)) {
                Text(text, fontSize = 12.sp, color = Fg)
                TextButton({ uri.openUri(WEB_APP) }, contentPadding = PaddingValues(0.dp)) { Text(t("open_web"), color = Accent, fontSize = 12.sp, fontWeight = FontWeight.Bold) }
            }
        }
    }
}
@Composable
private fun Tabs(labels: List<String>, selected: Int, onSelect: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        // the sub-tabs: the chosen one amber, the others quiet blocks
        labels.forEachIndexed { i, l ->
            val on = selected == i
            Text(
                l, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Ink else Muted, maxLines = 1,
                modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(if (on) Accent else Surface).clickable { onSelect(i) }.padding(horizontal = 12.dp, vertical = 9.dp)
            )
        }
    }
}

@Composable
private fun Panel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(
        modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = Surface),
        border = BorderStroke(1.dp, Line), shape = RoundedCornerShape(12.dp)
    ) { Column(Modifier.padding(12.dp), content = content) }
}

@Composable
private fun Section(s: String) {
    Text(s, color = Muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.3.sp)
}

@Composable
private fun Status(s: String, c: Color) {
    Surface(color = Color.Transparent, border = BorderStroke(1.dp, c), shape = MaterialTheme.shapes.extraLarge) {
        Text(s, color = c, fontFamily = FontFamily.Monospace, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 9.dp, vertical = 5.dp))
    }
}

@Composable
private fun Metric(l: String, v: String, m: Modifier, color: Color = Fg, sub: String? = null) {
    Panel(m) {
        Text(l.uppercase(), color = Muted, fontFamily = FontFamily.Monospace, fontSize = 10.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
        Text(v, color = color, fontWeight = FontWeight.Black, fontSize = 18.sp, fontFamily = FontFamily.Monospace, maxLines = 1)
        sub?.let { Text(it, color = Muted, fontSize = 10.sp, maxLines = 1) }
    }
}

@Composable
private fun InfoRow(l: String, v: String, color: Color = Fg) {
    Row(Modifier.fillMaxWidth().padding(vertical = 3.dp)) {
        Text(l, color = Muted, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Text(v, color = color, fontSize = 13.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold)
    }
}

@Composable
private fun Bar(label: String, v: Double?, c: Color) {
    Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(90.dp))
        LinearProgressIndicator(
            progress = { (v ?: 0.0).toFloat().coerceIn(0f, 1f) }, color = c, trackColor = Surface2,
            modifier = Modifier.weight(1f).height(10.dp)
        )
    }
}

@Composable
private fun Empty(s: String) = Panel { Text(s, color = Muted, fontSize = 13.sp) }

@Composable
private fun Action(title: String, sub: String, icon: ImageVector, onClick: () -> Unit) {
    Panel(Modifier.clickable(onClick = onClick)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = Accent)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(title, fontWeight = FontWeight.Black)
                Text(sub, color = Muted, fontSize = 12.sp)
            }
            Icon(Icons.Default.ChevronRight, null, tint = Muted)
        }
    }
}

// ---------- Telemetry: the same three tabs as the PC's (what matters while driving, the standings, the tyres) ----------

/** the delta of the top card and the delta bar: iRacing's to your best lap; in DRINKS mode the driver's own (LiveLaps) */
private fun liveDelta(s: LiveState): Double? =
    if (s.drinks?.on == true) s.ownDelta else if (s.num("LapDeltaToBestLap_OK") == 0.0) null else s.num("LapDeltaToBestLap")

private fun liveBestLap(s: LiveState): Double? = if (s.drinks?.on == true) s.ownBest else s.num("LapBestLapTime")?.takeIf { it > 0 }

private fun signedS(v: Double, d: Int = 1) = (if (v >= 0) "+" else "−") + "%.${d}f".format(kotlin.math.abs(v))

/** the laps a car is up (+) or down (−) on you: a red "+1L" or a blue "−1L", like the relative of the PC */
@Composable
private fun LapPill(lapDiff: Double) {
    val n = kotlin.math.round(lapDiff).toInt()
    if (kotlin.math.abs(lapDiff) < 0.5 || n == 0) return
    val col = if (n > 0) Bad else Blue
    Text((if (n > 0) "+$n" else "−${-n}") + "L", color = col, fontSize = 9.sp, fontWeight = FontWeight.Bold, fontFamily = FontFamily.Monospace,
        modifier = Modifier.padding(start = 4.dp).border(1.dp, col.copy(alpha = .6f), RoundedCornerShape(50)).padding(horizontal = 4.dp, vertical = 1.dp))
}

/** the top of the Telemetry screen: where you are, the delta and your best, the last lap, the fuel; beside it the
 *  gaps to the cars just ahead and behind, your incidents and what is left of the session */
@Composable
private fun LiveTop(s: LiveState) {
    val ses = s.session
    val sn = s.num("SessionNum")?.toInt()
    val kind = sn?.let { ses?.kinds?.get(it) }.orEmpty()
    val drk = s.drinks?.on == true
    val dlt = liveDelta(s)
    val best = liveBestLap(s)
    val last = s.num("LapLastLapTime")?.takeIf { it > 0 }
    val field = ses?.drivers?.values?.count { !it.pace && !it.spectator } ?: 0
    val pos = s.num("PlayerCarPosition")?.toInt()?.takeIf { it > 0 }
    val total = sn?.let { ses?.laps?.get(it) }?.takeIf { it in 1..31999 }
    val lap = s.num("Lap")?.toInt()
    val fuel = s.num("FuelLevel")
    val perLap = s.num("FuelUsePerLap")?.takeIf { it > 0.01 }
    val (ahead, behind) = s.aheadBehind()
    val inc = s.num("PlayerCarMyIncidentCount")?.toInt()
    val lapsLeft = s.num("SessionLapsRemainEx")?.toInt()?.takeIf { it in 0..31999 }
    val timeLeft = s.num("SessionTimeRemain")?.takeIf { it > 0 && it < 604800 }
    Panel {
        Text(ses?.track?.takeIf { it.isNotBlank() } ?: t("tab_telemetry"), fontWeight = FontWeight.Black, fontSize = 18.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
        if (kind.isNotBlank()) Text(kind, color = Muted, fontSize = 12.sp)
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("lt_position"), pos?.let { "P$it" + if (field > 1) "/$field" else "" } ?: "—", Modifier.weight(1f).fillMaxHeight(),
                sub = lap?.let { t("lt_lap_of", "$it" + (total?.let { tt -> "/$tt" } ?: "")) })
            Metric("Delta", dlt?.let { signedS(it, 2) } ?: "—", Modifier.weight(1f).fillMaxHeight(), color = if (dlt == null) Fg else if (dlt <= 0) Good else Bad,
                sub = best?.let { t("lt_best_t", lapTime(it)) + (s.drinks?.driver?.takeIf { drk && it.isNotBlank() }?.let { " · $it" } ?: "") })
        }
        Spacer(Modifier.height(8.dp))
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("lt_last"), lapTime(last), Modifier.weight(1f).fillMaxHeight(), color = if (last != null && best != null && last <= best + 0.001) Purple else Fg,
                sub = if (last != null && best != null) (if (last <= best + 0.001) t("lt_your_best") else t("lt_off_best", "%.2f".format(last - best))) else null)
            Metric(t("lt_fuel"), fuel?.let { "%.1f L".format(it) } ?: "—", Modifier.weight(1f).fillMaxHeight(),
                sub = if (fuel != null && perLap != null) t("lt_laps", "%.1f".format(fuel / perLap)) else null)
        }
    }
    Panel {
        Section((if (kind.contains("race", true)) t("lt_race") else t("lt_session")).uppercase())
        InfoRow(t("lt_ahead"), ahead?.let { "−%.1f s".format(it) } ?: "—")
        InfoRow(t("lt_behind"), behind?.let { "+%.1f s".format(it) } ?: "—")
        InfoRow(t("lt_incidents"), inc?.let { "${it}x" } ?: "—", if ((inc ?: 0) >= 8) Bad else Fg)
        InfoRow(t("lt_left"), lapsLeft?.let { t("lt_laps", it) } ?: timeLeft?.let { "%d:%02d".format((it / 60).toInt(), (it % 60).toInt()) } ?: "—")
    }
}

/** the delta bar: a track with the delta from its centre (one second to each side) and the value in a pill */
@Composable
private fun LiveDeltaBar(s: LiveState) {
    val d = liveDelta(s)
    Panel {
        Section(t("lt_deltabar").uppercase())
        Row(verticalAlignment = Alignment.CenterVertically) {
            Canvas(Modifier.weight(1f).height(14.dp)) {
                val r = size.height / 2
                drawRoundRect(Surface2, cornerRadius = androidx.compose.ui.geometry.CornerRadius(r, r))
                if (d != null) {
                    val f = (d.coerceIn(-1.0, 1.0) / 1.0).toFloat()
                    val cx = size.width / 2; val w = kotlin.math.abs(f) * size.width / 2
                    drawRect(if (d <= 0) Good else Bad, topLeft = Offset(if (f < 0) cx - w else cx, 0f), size = androidx.compose.ui.geometry.Size(w, size.height))
                }
                drawLine(Fg, Offset(size.width / 2, 0f), Offset(size.width / 2, size.height), strokeWidth = 2f)
            }
            Text(d?.let { signedS(it, 2) } ?: "—", color = if (d == null) Fg else if (d <= 0) Good else Bad, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Black,
                modifier = Modifier.padding(start = 10.dp).widthIn(min = 64.dp))
        }
    }
}

/** a driver's name in the relative and the standings: your note's icon first, then the name, its laps up or down */
@Composable
private fun RowScope.LiveName(r: LiveRow, notes: Map<String, DriverNote>) {
    val d = r.d
    val note = if (r.me || d == null) null else noteFor(notes, d.key, d.name)
    if (note != null && note.tag.isNotEmpty()) { TagIcon(note.tag, 12.dp); Spacer(Modifier.width(4.dp)) }
    Text(d?.name ?: "#${r.idx}", fontSize = 12.sp, fontWeight = if (r.me) FontWeight.Black else FontWeight.Normal, color = if (r.me) Accent else Fg,
        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
    if (d?.ai == true) Text(" " + t("ai_driver"), color = Blue, fontSize = 9.sp, fontWeight = FontWeight.Bold)
    if (!r.me) LapPill(r.lapDiff)
    if (r.pit) Text(" " + t("lt_pit"), color = Muted, fontSize = 9.sp, fontWeight = FontWeight.Bold)
}

/** the relative: the cars just ahead and behind you on track, with the time to them */
@Composable
private fun LiveRelative(s: LiveState, notes: Map<String, DriverNote>) {
    val rows = s.relative(3)
    Panel {
        Section(t("lt_relative").uppercase())
        if (rows.isEmpty()) { Text(t("lt_no_cars"), color = Muted, fontSize = 12.sp); return@Panel }
        rows.forEach { r ->
            Row(Modifier.fillMaxWidth().background(if (r.me) Accent.copy(alpha = .12f) else Color.Transparent, RoundedCornerShape(4.dp)).padding(vertical = 4.dp, horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(if (r.pos > 0) "P${r.pos}" else "", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(34.dp))
                Text(r.d?.number?.let { "#$it" } ?: "", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(36.dp))
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) { LiveName(r, notes) }
                val lic = r.d?.lic.orEmpty()
                if (lic.isNotBlank()) Text(lic.split(" ").first(), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.padding(horizontal = 4.dp))
                Text(if (r.me) "—" else r.gap?.let { signedS(it) } ?: "—", fontSize = 12.sp, fontFamily = FontFamily.Monospace, fontWeight = FontWeight.Bold, modifier = Modifier.widthIn(min = 48.dp))
            }
        }
    }
}

/** the standings: every car in order, its last and best lap and its gap to the leader */
@Composable
private fun LiveStandings(s: LiveState, notes: Map<String, DriverNote>) {
    val all = s.standings()
    var cls by rememberSaveable { mutableStateOf("") }
    var interval by rememberSaveable { mutableStateOf(false) }
    val classes = all.mapNotNull { it.d?.cls?.takeIf { c -> c.isNotBlank() } }.distinct()
    val rows = if (classes.size > 1 && cls.isNotEmpty()) all.filter { it.d?.cls == cls } else all
    val bestAll = rows.mapNotNull { it.best }.minOrNull()
    Panel {
        Section(t("tab_standings").uppercase() + if (rows.isNotEmpty()) " · " + t("lt_drivers_n", rows.size) else "")
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(t("lm_to_leader"), !interval) { interval = false }
            Chip(t("lm_interval"), interval) { interval = true }
            if (classes.size > 1) {
                Spacer(Modifier.width(6.dp))
                Chip(t("lm_all_classes"), cls.isEmpty()) { cls = "" }
                classes.forEach { c -> Chip(c, cls == c) { cls = c } }
            }
        }
        if (rows.isEmpty()) { Text(t("lt_no_cars"), color = Muted, fontSize = 12.sp); return@Panel }
        val lead = rows.first().gap ?: 0.0
        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp)) {
            listOf("P" to 30, "#" to 34).forEach { (h, w) -> Text(h, color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(w.dp)) }
            Text(t("lt_driver"), color = Muted, fontSize = 10.sp, modifier = Modifier.weight(1f))
            Text(t("last"), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(62.dp))
            Text(t("best"), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(62.dp))
            Text(if (interval) t("lm_int") else t("lt_gap"), color = Muted, fontSize = 10.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(44.dp))
        }
        rows.forEachIndexed { k, r ->
            Row(Modifier.fillMaxWidth().background(if (r.me) Accent.copy(alpha = .12f) else Color.Transparent, RoundedCornerShape(4.dp)).padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${r.pos}", color = if (r.me) Accent else Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(30.dp))
                Text(r.d?.number ?: "", color = Muted, fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(34.dp))
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) { LiveName(r, notes) }
                Text(r.last?.let { lapTime(it) } ?: "—", fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(62.dp))
                Text(r.best?.let { lapTime(it) } ?: "—", fontSize = 11.sp, fontFamily = FontFamily.Monospace, color = if (r.best != null && r.best == bestAll) Purple else Fg, modifier = Modifier.width(62.dp))
                val g = if (k == 0) null else if (interval) rows[k - 1].gap?.let { p -> r.gap?.let { it - p } } else r.gap?.let { it - lead }
                Text(if (k == 0) "—" else g?.let { "+%.1f".format(it) } ?: "—", fontSize = 11.sp, fontFamily = FontFamily.Monospace, modifier = Modifier.width(44.dp))
            }
        }
    }
}

/** the fuel: what is in the tank, how many laps it lasts and the use per lap */
@Composable
private fun LiveFuel(s: LiveState) {
    val fuel = s.num("FuelLevel"); val per = s.num("FuelUsePerLap")?.takeIf { it > 0.01 }
    Panel {
        Section(t("lt_fuel").uppercase())
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("lt_in_tank"), fuel?.let { "%.1f L".format(it) } ?: "—", Modifier.weight(1f).fillMaxHeight())
            Metric(t("lt_laps_fuel"), if (fuel != null && per != null) "%.1f".format(fuel / per) else "—", Modifier.weight(1f).fillMaxHeight())
            Metric(t("lt_per_lap"), per?.let { "%.2f L".format(it) } ?: "—", Modifier.weight(1f).fillMaxHeight())
        }
    }
}

/** your incidents in this session */
@Composable
private fun LiveIncidents(s: LiveState) {
    val inc = s.num("PlayerCarMyIncidentCount")?.toInt()
    Panel {
        Section(t("lt_incident_log").uppercase())
        Text(inc?.let { "${it}x" } ?: "—", fontSize = 30.sp, fontWeight = FontWeight.Black, color = if ((inc ?: 0) >= 8) Bad else Fg)
        if (inc == 0) Text(t("lt_clean"), color = Good, fontSize = 12.sp)
    }
}

/** the live map: the track's layout drawn by the community, as a road with depth, the start/finish line with the
 *  direction, the official turns, and every car where its lap distance puts it (you in amber) */
@Composable
private fun LiveMap(vm: PitlaneViewModel, s: LiveState) {
    val tid = s.session?.trackId ?: 0L
    LaunchedEffect(tid) { if (tid > 0) vm.loadLiveTrack(tid) }
    val lt by vm.liveTrack.collectAsState()
    val lay = lt?.takeIf { it.first == tid }?.second
    val turns = lt?.takeIf { it.first == tid }?.third ?: emptyList()
    val dpx = with(LocalDensity.current) { 1.dp.toPx() }
    val labelPx = with(LocalDensity.current) { 9.sp.toPx() }
    val turnPaint = remember(labelPx) { android.graphics.Paint().apply { color = android.graphics.Color.rgb(0x8A, 0x97, 0xA9); textSize = labelPx; isFakeBoldText = true; isAntiAlias = true; textAlign = android.graphics.Paint.Align.CENTER } }
    Panel {
        Section(t("lt_map").uppercase())
        if (lay == null) { Text(if (tid > 0) t("lt_map_none") else t("lt_no_cars"), color = Muted, fontSize = 12.sp); return@Panel }
        val xs = lay.first; val ys = lay.second; val n = xs.size
        val minX = xs.min(); val maxX = xs.max(); val minY = ys.min(); val maxY = ys.max()
        Canvas(Modifier.fillMaxWidth().height(240.dp)) {
            val pad = 22f * dpx
            val k = minOf((size.width - 2 * pad) / maxOf(1e-6, maxX - minX).toFloat(), (size.height - 2 * pad) / maxOf(1e-6, maxY - minY).toFloat())
            val ox = (size.width - 2 * pad - (maxX - minX).toFloat() * k) / 2; val oy = (size.height - 2 * pad - (maxY - minY).toFloat() * k) / 2
            fun pt(i: Int) = Offset(pad + (xs[i] - minX).toFloat() * k + ox, size.height - pad - (ys[i] - minY).toFloat() * k - oy)
            fun at(f: Double): Offset { val q = (((f % 1) + 1) % 1) * n; val i = q.toInt() % n; val j = (i + 1) % n; val r = (q - q.toInt()).toFloat(); val a = pt(i); val b = pt(j); return Offset(a.x + (b.x - a.x) * r, a.y + (b.y - a.y) * r) }
            val track = Path()
            for (i in 0 until n) { val q = pt(i); if (i == 0) track.moveTo(q.x, q.y) else track.lineTo(q.x, q.y) }
            track.close()
            val w = 11f * dpx
            drawContext.canvas.save(); drawContext.canvas.translate(1.5f * dpx, 2.5f * dpx)
            drawPath(track, Color.Black.copy(alpha = .38f), style = Stroke(width = w + 2 * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawContext.canvas.restore()
            drawPath(track, Line.copy(red = minOf(1f, Line.red + .12f), green = minOf(1f, Line.green + .12f), blue = minOf(1f, Line.blue + .12f)), style = Stroke(width = w, cap = StrokeCap.Round, join = StrokeJoin.Round))
            drawPath(track, Color(0xFF151A21), style = Stroke(width = w - 3.5f * dpx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            // the start/finish line across the road and the way the cars go beside it
            val p0 = pt(0); val p1 = pt(maxOf(2, n / 60))
            val dx = p1.x - p0.x; val dy = p1.y - p0.y; val m = maxOf(1e-6f, kotlin.math.hypot(dx, dy)); val ux = dx / m; val uy = dy / m
            var nx = -uy; var ny = ux
            if ((p0.x - size.width / 2f) * nx + (p0.y - size.height / 2f) * ny < 0) { nx = -nx; ny = -ny }
            drawLine(Color.White, Offset(p0.x - nx * w / 2, p0.y - ny * w / 2), Offset(p0.x + nx * w / 2, p0.y + ny * w / 2), strokeWidth = 3.5f * dpx)
            val bx = p0.x + nx * (w / 2 + 8 * dpx); val by = p0.y + ny * (w / 2 + 8 * dpx); val tx = bx + ux * 18f * dpx; val ty = by + uy * 18f * dpx; val h = 6f * dpx
            drawLine(Fg, Offset(bx, by), Offset(tx - ux * h, ty - uy * h), strokeWidth = 2f * dpx, cap = StrokeCap.Round)
            val head = Path(); head.moveTo(tx, ty); head.lineTo(tx - ux * h + nx * h * .6f, ty - uy * h + ny * h * .6f); head.lineTo(tx - ux * h - nx * h * .6f, ty - uy * h - ny * h * .6f); head.close()
            drawPath(head, Fg)
            // the official turns, beside the road
            turns.forEachIndexed { ti, f ->
                val i = (f * n).toInt().coerceIn(0, n - 1); val q = pt(i); val q1 = pt((i + 2) % n); val q0 = pt((i - 2 + n) % n)
                val tmx = q1.x - q0.x; val tmy = q1.y - q0.y; val tm = maxOf(1e-3f, kotlin.math.hypot(tmx, tmy))
                var qx = -tmy / tm; var qy = tmx / tm
                if ((q.x - size.width / 2) * qx + (q.y - size.height / 2) * qy < 0) { qx = -qx; qy = -qy }
                drawContext.canvas.nativeCanvas.drawText("${ti + 1}", q.x + qx * (w / 2 + 9 * dpx), q.y + qy * (w / 2 + 9 * dpx) + labelPx * .35f, turnPaint)
            }
            // the cars: you on top, the others dimmed in the pits, laps up red and down blue
            val pct = s.arrays["CarIdxLapDistPct"] ?: emptyList()
            val me = s.meIdx()
            val lapsArr = s.arrays["CarIdxLap"] ?: emptyList()
            val pitArr = s.arrays["CarIdxOnPitRoad"] ?: emptyList()
            val order = pct.indices.filter { pct[it] >= 0 && s.session?.drivers?.get(it)?.let { d -> !d.pace && !d.spectator } != false }.sortedBy { if (it == me) 1 else 0 }
            order.forEach { i ->
                val p = at(pct[i])
                val diff = (lapsArr.getOrElse(i) { 0.0 } + pct[i]) - (lapsArr.getOrElse(me) { 0.0 } + pct.getOrElse(me) { 0.0 })
                val col = if (i == me) Accent else if (diff > .5) Bad else if (diff < -.5) Blue else Fg
                val a = if (pitArr.getOrElse(i) { 0.0 } != 0.0) .45f else 1f
                drawCircle(Ink, radius = (if (i == me) 7f else 5f) * dpx + 1.5f * dpx, center = p, alpha = a)
                drawCircle(col, radius = (if (i == me) 7f else 5f) * dpx, center = p, alpha = a)
            }
        }
    }
}

/** the tyres: each one's three zones (outer, middle, inner) by temperature, the wear and the cold pressure, from the
 *  last stop in the pit box (iRacing sends them only then) */
@Composable
private fun LiveTyres(s: LiveState) {
    val any = listOf("LF", "RF", "LR", "RR").any { s.num(it + "tempCM") != null }
    Panel {
        Section(t("tab_tyres").uppercase())
        Text(t("lt_tyres_note"), color = Muted, fontSize = 12.sp, modifier = Modifier.padding(bottom = 8.dp))
        if (!any) { Text(t("lt_tyres_none"), color = Muted, fontSize = 12.sp); return@Panel }
        listOf(listOf("LF" to t("lt_fl"), "RF" to t("lt_fr")), listOf("LR" to t("lt_rl"), "RR" to t("lt_rr"))).forEach { pair ->
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                pair.forEach { (c, nm) -> TyreCard(s, c, nm, Modifier.weight(1f)) }
            }
        }
    }
}

private fun heatColor(t: Double?): Color {
    if (t == null) return Surface2
    val f = ((t - 60) / 50).coerceIn(0.0, 1.0).toFloat() // blue cold, green in the window, red hot
    return if (f < .5f) lerpColor(Blue, Good, f * 2) else lerpColor(Good, Bad, (f - .5f) * 2)
}

private fun lerpColor(a: Color, b: Color, f: Float) = Color(a.red + (b.red - a.red) * f, a.green + (b.green - a.green) * f, a.blue + (b.blue - a.blue) * f, 1f)

@Composable
private fun TyreCard(s: LiveState, c: String, name: String, m: Modifier) {
    val left = c[0] == 'L'
    val zones = if (left) listOf("tempCL" to "O", "tempCM" to "M", "tempCR" to "I") else listOf("tempCL" to "I", "tempCM" to "M", "tempCR" to "O")
    val wear = listOf("wearL", "wearM", "wearR").map { s.num(c + it) }
    val temps = zones.map { s.num(c + it.first) }
    val avg = if (temps.all { it != null }) temps.sumOf { it!! } / 3 else null
    Column(m.background(Surface2, RoundedCornerShape(8.dp)).padding(8.dp)) {
        Row { Text("$c · $name", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis); Text(avg?.let { "%.0f°".format(it) } ?: "—", fontSize = 12.sp, fontFamily = FontFamily.Monospace) }
        Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            zones.forEachIndexed { k, (_, lab) ->
                Column(Modifier.weight(1f).background(heatColor(temps[k]), RoundedCornerShape(4.dp)).padding(vertical = 6.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(temps[k]?.let { "%.0f".format(it) } ?: "–", color = Ink, fontSize = 12.sp, fontWeight = FontWeight.Black)
                    Text(lab, color = Ink, fontSize = 9.sp)
                }
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) { wear.forEach { w -> Text(w?.let { "${(it * 100).roundToInt()}%" } ?: "–", fontSize = 10.sp, fontFamily = FontFamily.Monospace, color = Muted) } }
        val wl = wear.filterNotNull().minOrNull()
        if (wl != null) Box(Modifier.fillMaxWidth().padding(top = 4.dp).height(5.dp).clip(RoundedCornerShape(3.dp)).background(Line)) {
            Box(Modifier.fillMaxWidth(wl.toFloat().coerceIn(0f, 1f)).fillMaxHeight().background(if (wl > .7) Good else if (wl > .4) Accent else Bad))
        }
        s.num(c + "coldPressure")?.let { Text(t("lt_cold", "%.0f kPa".format(it)), fontSize = 10.sp, color = Muted, modifier = Modifier.padding(top = 4.dp)) }
    }
}

// ---------- Telemetry's modes: Basic, Full (the lap's traces) and Compare laps (live), like the PC and the web ----------

@Composable
private fun LiveModeBar(mode: Int, onPick: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        listOf(t("lm_basic"), t("lm_full"), t("lm_cmp")).forEachIndexed { i, l -> Chip(l, mode == i) { onPick(i) } }
    }
}

/** the rows of a lap against another, along the lap: speed, throttle and brake, the delta and the gear. A is drawn
 *  up to [upto] (the point of the lap now), B whole. */
@Composable
private fun LapRows(a: RecLap, b: RecLap?, upto: Int, total: Int, bCol: Color = Purple) {
    val dpx = with(LocalDensity.current) { 1.dp.toPx() }
    val labelPx = with(LocalDensity.current) { 9.sp.toPx() }
    val paint = remember(labelPx) { android.graphics.Paint().apply { color = android.graphics.Color.rgb(0x9A, 0xA6, 0xB8); textSize = labelPx; isAntiAlias = true; isFakeBoldText = true } }
    val names = listOf(t("lr_speed"), t("lr_pedals"), "Delta", t("lr_gear"))
    Canvas(Modifier.fillMaxWidth().height(250.dp)) {
        val n = maxOf(total, a.size, b?.size ?: 0, 2)
        val gap = 8f * dpx; val rh = (size.height - gap * 3) / 4
        fun x(i: Int) = i.toFloat() / (n - 1) * size.width
        val top = FloatArray(4) { it * (rh + gap) }
        top.forEach { y -> drawRect(Surface2, Offset(0f, y), androidx.compose.ui.geometry.Size(size.width, rh)) }
        fun line(vals: (Int) -> Float?, count: Int, row: Int, lo: Float, hi: Float, col: Color, w: Float = 1.6f) {
            val p = Path(); var on = false
            for (i in 0 until count) {
                val v = vals(i) ?: continue
                val y = top[row] + rh - ((v - lo) / maxOf(1e-6f, hi - lo)).coerceIn(0f, 1f) * rh
                if (!on) { p.moveTo(x(i), y); on = true } else p.lineTo(x(i), y)
            }
            drawPath(p, col, style = Stroke(width = w * dpx))
        }
        val vmax = maxOf(a.sp.maxOrNull() ?: 1f, b?.sp?.maxOrNull() ?: 1f, 1f) * 1.05f
        val aN = minOf(upto + 1, a.size)
        if (b != null) {
            line({ b.sp.getOrNull(it) }, b.size, 0, 0f, vmax, bCol.copy(alpha = .8f), 1.2f)
            line({ b.thr.getOrNull(it) }, b.size, 1, 0f, 1f, Good.copy(alpha = .35f), 1.0f)
            line({ b.brk.getOrNull(it) }, b.size, 1, 0f, 1f, Bad.copy(alpha = .35f), 1.0f)
            line({ b.gear.getOrNull(it)?.toFloat() }, b.size, 3, 0f, 8f, bCol.copy(alpha = .7f), 1.2f)
            // the delta: A's time against B's at the same point, ± from the middle of its row
            val ds = (0 until minOf(aN, b.size)).map { a.t[it] - b.t[it] }
            val m = maxOf(.3f, ds.maxOfOrNull { kotlin.math.abs(it) } ?: .3f)
            drawLine(Line, Offset(0f, top[2] + rh / 2), Offset(size.width, top[2] + rh / 2), strokeWidth = 1f * dpx)
            line({ ds.getOrNull(it) }, ds.size, 2, -m, m, if ((ds.lastOrNull() ?: 0f) <= 0f) Good else Bad, 1.8f)
        }
        line({ a.sp.getOrNull(it) }, aN, 0, 0f, vmax, Accent, 1.8f)
        line({ a.thr.getOrNull(it) }, aN, 1, 0f, 1f, Good, 1.6f)
        line({ a.brk.getOrNull(it) }, aN, 1, 0f, 1f, Bad, 1.6f)
        line({ a.gear.getOrNull(it)?.toFloat() }, aN, 3, 0f, 8f, Accent, 1.6f)
        drawLine(Fg.copy(alpha = .5f), Offset(x(aN - 1), 0f), Offset(x(aN - 1), size.height), strokeWidth = 1f * dpx)
        names.forEachIndexed { k, s -> drawContext.canvas.nativeCanvas.drawText(s, 4 * dpx, top[k] + labelPx + 2 * dpx, paint) }
    }
}

/** Full mode: the lap now drawn as it goes, against your best lap seen here */
@Composable
private fun LiveTraces(s: LiveState) {
    val rec = s.rec; val a = rec?.cur; val b = rec?.best()
    val total = ((s.session?.trackLen ?: 0.0) / 5).toInt()
    Panel {
        Section(t("lm_traces").uppercase())
        if (a == null || a.size < 2) { Text(t("lm_wait_lap"), color = Muted, fontSize = 12.sp); return@Panel }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.padding(bottom = 6.dp)) {
            Text("● " + t("lm_now"), color = Accent, fontSize = 11.sp, fontWeight = FontWeight.Bold)
            if (b != null) Text("● " + t("lm_my_best") + " " + lapTime(b.time), color = Purple, fontSize = 11.sp, fontWeight = FontWeight.Bold)
        }
        LapRows(a, b, a.size - 1, total)
    }
}

/** Compare laps, live: the lap now against the one you choose (your best in purple, the last one, any other lap seen
 *  here), the delta now and corner by corner by the official turns */
@Composable
private fun LiveCompare(vm: PitlaneViewModel, s: LiveState) {
    val rec = s.rec; val a = rec?.cur
    var pick by rememberSaveable { mutableStateOf("best") }
    val tid = s.session?.trackId ?: 0L
    LaunchedEffect(tid) { if (tid > 0) vm.loadLiveTrack(tid) }
    val lt by vm.liveTrack.collectAsState()
    val turns = lt?.takeIf { it.first == tid }?.third ?: emptyList()
    val total = ((s.session?.trackLen ?: 0.0) / 5).toInt()
    val best = rec?.best(); val last = rec?.last()
    val b = when {
        pick == "best" -> best
        pick == "last" -> last
        else -> rec?.laps?.firstOrNull { "lap:${it.n}" == pick } ?: best
    }
    Panel {
        Section(t("lm_cmp").uppercase())
        if (rec == null || a == null || rec.laps.isEmpty()) { Text(t("lm_wait_cmp"), color = Muted, fontSize = 12.sp); return@Panel }
        Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Chip(t("lm_my_best"), pick == "best") { pick = "best" }
            Chip(t("lm_last"), pick == "last") { pick = "last" }
            rec.laps.filter { it.time > 0 && it !== best && it !== last }.takeLast(8).reversed().forEach { l ->
                Chip(t("lm_lap_n", l.n + 1) + " · " + lapTime(l.time), pick == "lap:${l.n}") { pick = "lap:${l.n}" }
            }
        }
        val i = a.size - 1
        val now = if (b != null && i in b.t.indices && i > 3) (a.t[i] - b.t[i]).toDouble() else null
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Metric(t("lm_best"), best?.let { lapTime(it.time) } ?: "—", Modifier.weight(1f).fillMaxHeight(), color = Purple)
            Metric(t("lm_last"), last?.let { lapTime(it.time) } ?: "—", Modifier.weight(1f).fillMaxHeight())
            Metric(t("lm_now_vs"), now?.let { signedS(it, 2) } ?: "—", Modifier.weight(1f).fillMaxHeight(), color = if (now == null) Fg else if (now <= 0) Good else Bad)
        }
        Spacer(Modifier.height(8.dp))
        if (b != null) LapRows(a, b, i, total, if (b === best) Purple else Blue)
        // corner by corner: from the middle of the straight before each turn to the middle of the one after it
        val n = maxOf(total, b?.size ?: 0)
        if (b != null && turns.isNotEmpty() && n > 0) {
            val cuts = turns.map { (it * n).toInt() }
            val chips = cuts.mapIndexedNotNull { k, c ->
                val s0 = if (k == 0) 0 else (cuts[k - 1] + c) / 2
                val e0 = if (k == cuts.size - 1) minOf(n - 1, c + (n - c) / 2) else (c + cuts[k + 1]) / 2
                val done = e0 < a.size && e0 < b.size && s0 < e0
                Triple(k + 1, if (done) ((a.t[e0] - a.t[s0]) - (b.t[e0] - b.t[s0])).toDouble() else null, done)
            }
            Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(top = 8.dp), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                chips.forEach { (no, d, _) ->
                    Column(Modifier.clip(RoundedCornerShape(8.dp)).background(Surface2).padding(horizontal = 8.dp, vertical = 5.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Text("T$no", color = Muted, fontSize = 10.sp, fontWeight = FontWeight.Bold)
                        Text(d?.let { signedS(it, 2) } ?: "·", color = if (d == null) Muted else if (d <= 0) Good else Bad, fontSize = 11.sp, fontFamily = FontFamily.Monospace)
                    }
                }
            }
        }
    }
}

/** your place at the end of every lap of this session */
@Composable
private fun PosHistory(s: LiveState) {
    val h = s.rec?.posHist?.toList() ?: emptyList()
    if (h.size < 2) return
    val dpx = with(LocalDensity.current) { 1.dp.toPx() }
    Panel {
        Section(t("lm_pos_hist").uppercase())
        val lo = h.minOf { it.second }; val hi = maxOf(h.maxOf { it.second }, lo + 1)
        Canvas(Modifier.fillMaxWidth().height(110.dp)) {
            val p = Path()
            h.forEachIndexed { k, (_, pos) ->
                val x = k.toFloat() / (h.size - 1) * size.width
                val y = (pos - lo).toFloat() / (hi - lo) * (size.height - 8 * dpx) + 4 * dpx
                if (k == 0) p.moveTo(x, y) else p.lineTo(x, y)
            }
            drawPath(p, Accent, style = Stroke(width = 2f * dpx, join = StrokeJoin.Round))
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text("P$lo", color = Muted, fontSize = 10.sp); Text(t("lt_lap_of", h.last().first), color = Muted, fontSize = 10.sp); Text("P" + h.last().second, color = Accent, fontSize = 10.sp, fontWeight = FontWeight.Bold)
        }
    }
}

/** One number with its label, for a row of three (the profile's leaderboards, records and podiums). */
@Composable
private fun StatTile(value: String, label: String, modifier: Modifier = Modifier, tint: Color = Fg) {
    Panel(modifier) {
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            Text(value, color = tint, fontWeight = FontWeight.Black, fontFamily = FontFamily.Monospace, fontSize = 20.sp)
            Text(label, color = Muted, fontSize = 11.sp, textAlign = TextAlign.Center, maxLines = 2)
        }
    }
}

/** Your notes on a track (the same the PC and the web keep): the general note, which you can write here, and the
 *  corner notes made on the PC or the web. */
@Composable
private fun TrackNotesPanel(vm: PitlaneViewModel, trackId: Long, track: String) {
    val all by vm.trackNotes.collectAsState()
    LaunchedEffect(trackId) { vm.loadTrackNotes() }
    val n = all[trackId]
    var editing by remember { mutableStateOf(false) }
    var text by remember { mutableStateOf("") }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    Column {
        Section(t("my_notes"))
        Panel {
            if (n != null && n.general.isNotEmpty()) Text(n.general, fontSize = 14.sp)
            else if (n == null || n.corners.isEmpty()) Text(t("no_track_notes"), color = Muted, fontSize = 12.sp)
            n?.corners?.forEach { c ->
                Row(Modifier.padding(top = 4.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(c.name.ifEmpty { t("corner_n", c.n) }, color = Accent, fontWeight = FontWeight.Bold, fontSize = 12.sp, modifier = Modifier.widthIn(min = 64.dp))
                    Text(c.note, fontSize = 12.sp)
                }
            }
            TextButton({ text = n?.general ?: ""; error = null; editing = true }, contentPadding = PaddingValues(horizontal = 0.dp)) {
                Text(t(if (n?.general.isNullOrEmpty()) "write_note" else "edit_note"), color = Accent, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            }
        }
    }
    if (editing) AlertDialog(
        onDismissRequest = { if (!busy) editing = false },
        title = { Text(track, fontWeight = FontWeight.Black) },
        text = {
            Column {
                OutlinedTextField(text, { text = it.take(2000) }, modifier = Modifier.fillMaxWidth().heightIn(min = 160.dp))
                error?.let { Text(t(it), color = Bad, fontSize = 12.sp) }
            }
        },
        confirmButton = {
            TextButton({ busy = true; vm.setTrackNote(trackId, track, text) { e -> busy = false; error = e; if (e == null) editing = false } }, enabled = !busy) { Text(t("save"), color = Accent) }
        },
        dismissButton = { TextButton({ editing = false }, enabled = !busy) { Text(t("cancel"), color = Muted) } }
    )
}

/** Every track you wrote notes on, the newest first; each opens its track page (with the notes). */
@Composable
private fun TrackNotesScreen(vm: PitlaneViewModel, nav: NavHostController) {
    val all by vm.trackNotes.collectAsState()
    LaunchedEffect(Unit) { vm.loadTrackNotes() }
    val list = all.values.sortedByDescending { it.updated }
    Screen(t("track_notes"), back = { nav.popBackStack() }) {
        if (list.isEmpty()) item { Empty(t("no_notes_any")) }
        items(list, key = { it.trackId }) { n ->
            Panel(Modifier.clickable { vm.openTrack(n.trackId, n.track); nav.navigate("track") }) {
                Text(n.track.ifEmpty { "#" + n.trackId }, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(n.general.ifEmpty { t("corner_notes_n", n.corners.size) }, color = Muted, fontSize = 12.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}
