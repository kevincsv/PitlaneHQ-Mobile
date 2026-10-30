package com.pitlanehq.android.viewmodel

import android.app.Application
import org.json.JSONObject
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.pitlanehq.android.data.*
import com.pitlanehq.android.model.*
import com.pitlanehq.android.ui.I18n
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** A lap next to the lap it is compared with. */
data class LapAnalysis(val lap: CloudLap, val trace: Trace?, val ref: Trace?, val refLabel: String, val refTime: Double?, val refSectors: List<Double>, val car: JSONObject? = null,
    val turns: List<Double> = emptyList(), val pit: PitLane? = null, val fastest: Boolean = false,
    // the track's layout drawn by the community: the map's road (the lap's own path only when there is none)
    val layout: Pair<List<Double>, List<Double>>? = null,
    // the session, its car and track as the community knows them, and the model's corner card (where the fastest drivers
    // here brake and how fast they take each corner): the thumbs on a tip and the hint beside it
    val session: CloudSession? = null, val trackId: Long = 0, val carId: Long = 0, val corners: List<CornerCard> = emptyList(),
    // what the coach learnt from everyone (the tips turned off, how many drivers each helped) and this driver's habits
    val coach: CoachInfo? = null, val habits: List<Habit> = emptyList(),
    // the web's analysis of these two laps (pitwall-analysis.js) in each language: its corners, tips, plan and sectors are
    // what the screens show; null when the phone cannot run it, and the screens use LapMath
    val js: Map<String, JsResult>? = null) {
    /** the web's analysis in the app's language */
    val jsNow: JsResult? get() = js?.get(com.pitlanehq.android.ui.I18n.lang)
}

/** The pit lane of a track (from laps through the pits): [5 m point of a lap of n points, metres to the left of the track]. */
data class PitLane(val n: Int, val pts: List<Pair<Int, Double>>)

/** lap B: your best lap of the session, or the model's next level (the driver just ahead) or record */
enum class RefKind { MY_BEST, LEVEL, RECORD }

/** Sign in with Steam or Discord ([prov]) on the sign-in screen: the authenticator's code or the password comes next, or
 *  that Steam or Discord has no account yet ([sid] and its name for the new account's form). */
data class AuthUi(val prov: String = "", val busy: Boolean = false, val needCode: Boolean = false, val needKey: Boolean = false,
    val newName: String? = null, val sid: String = "", val error: String? = null)

class PitlaneViewModel(app: Application) : AndroidViewModel(app) {
    private val repo = AccountRepository(app)
    private val live = PitWallRepository(repo)

    private val _account = MutableStateFlow(repo.storedState())
    val account = _account.asStateFlow()
    val liveState = live.state
    val demo = MutableStateFlow(repo.demo)
    val online = MutableStateFlow(true)
    val update = MutableStateFlow<AppUpdate?>(null)
    val news = MutableStateFlow<List<com.pitlanehq.android.data.AppNews>>(emptyList())
    val inboxSeen = MutableStateFlow(repo.inboxSeen())
    fun inboxMark(ids: Collection<String>) { repo.inboxMark(ids); inboxSeen.value = repo.inboxSeen() }

    val races = MutableStateFlow(Loadable<List<Race>>())
    val sessions = MutableStateFlow(Loadable<List<CloudSession>>())
    val bests = MutableStateFlow(Loadable<List<PersonalBest>>())
    val laps = MutableStateFlow(Loadable<List<CloudLap>>())
    val analysis = MutableStateFlow(Loadable<LapAnalysis>())
    val coach = MutableStateFlow(Loadable<LapAnalysis>()) // Analysis → Coach: the best lap of the chosen session
    var coachKey = ""
    val combos = MutableStateFlow(Loadable<List<Combo>>())
    val board = MutableStateFlow(Loadable<List<CommunityLap>>())
    val reports = MutableStateFlow(Loadable<List<SharedReport>>())
    val setups = MutableStateFlow(Loadable<List<SharedSetup>>())
    val devices = MutableStateFlow(Loadable<List<Device>>())
    val discord = MutableStateFlow(Loadable<DiscordLink>())
    val profile = MutableStateFlow(Loadable<DriverProfile>())
    private var profileLap: String? = null

    // what the detail screens show
    // the session Analysis → Laps and Coach show (and the one a session screen opens)
    var session by mutableStateOf<CloudSession?>(null)
    // the Analysis tab to open next (Home's "See all" opens My races)
    var analysisTab: Int? = null
    var combo: Combo? = null
    var race: Race? = null

    // ---------- the game you look at: iRacing or Le Mans Ultimate (Home, Analysis, Community) ----------
    // Only what this phone shows: never what your PC reads. Telemetry follows the PC's live game.
    /** the game chosen on this phone (remembered), else the one your PC reads live, else iRacing */
    var game by mutableStateOf(repo.gameChoice.ifEmpty { "iracing" })
        private set
    /** the game your PC is reading live (null: not live), marked ● in the selector */
    val pcGame = live.pcGame
    /** per game: how many sessions you have and the last one's date (the sheet that asks which game to see) */
    val gameStats = MutableStateFlow<Map<String, Pair<Int, Long>>>(emptyMap())
    /** "What do you want to see?": once when the app opens, the PC not live and sessions of both games */
    var askGame by mutableStateOf(false)
    private var gameAsked = false
    @Volatile private var allRaces: List<Race> = emptyList()
    /** Home's four numbers of the month for the chosen game, counted by the server (GET /api/sessions/summary) */
    val monthStats = MutableStateFlow(Loadable<MonthStats>())
    /** goes up each time the account's bundle comes back with a new version: what is read from it is read again */
    val bundleVer = MutableStateFlow(0)
    @Volatile private var allBests: List<PersonalBest>? = null

    fun setGame(g: String, remember: Boolean = true) {
        if (g !in GAMES) return
        if (remember) repo.gameChoice = g
        askGame = false
        if (g == game) return
        game = g
        track("game:$g")
        repo.game = g
        // every list shows the new game: the account's from what is already here, the community's read again
        races.value = races.value.copy(data = allRaces.filter { it.game == g })
        // the sessions and the month's numbers are the server's for each game: asked again for the new one
        val had = sessions.value.data != null || sessions.value.loading || sessions.value.error != null
        sessions.value = Loadable(); monthStats.value = Loadable()
        if (had) loadSessions()
        allBests?.let { a -> bests.value = bests.value.copy(data = a.filter { it.game == g }) }
        session = null
        laps.value = Loadable(); analysis.value = Loadable(); coach.value = Loadable(); coachKey = ""
        listOf(board, reports, setups, trackPage).forEach { (it as MutableStateFlow<Loadable<*>>).value = Loadable<Any>() }
        if (combos.value.data != null || combos.value.loading) loadCombos() else combos.value = Loadable()
        if (records.value.data != null || records.value.loading) loadRecords() else records.value = Loadable()
        // each game has its own leagues
        if (leagues.value.data != null || leagues.value.loading) loadLeagues() else leagues.value = Loadable()
    }

    private fun noteStats(st: Map<String, Pair<Int, Long>>) {
        gameStats.value = st
        if (!gameAsked && !demo.value) {
            gameAsked = true
            if (st.values.count { it.first > 0 } > 1 && pcGame.value == null) askGame = true
        }
    }

    private val cm = app.getSystemService(ConnectivityManager::class.java)
    private val netCallback = object : ConnectivityManager.NetworkCallback() {
        override fun onAvailable(network: Network) {
            val was = online.value
            online.value = true
            if (!was) refreshStale()
        }

        override fun onLost(network: Network) {
            online.value = cm?.activeNetwork != null && cm.activeNetwork != network
        }
    }

    init {
        I18n.choice = repo.language
        online.value = cm?.activeNetwork?.let { cm.getNetworkCapabilities(it)?.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET) } ?: false
        runCatching { cm?.registerNetworkCallback(NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(), netCallback) }
        repo.game = game
        loadRaces()
        checkUpdate()
        // nothing chosen on this phone yet: the selector follows the game your PC reads live
        viewModelScope.launch { pcGame.collect { g -> if (g != null && repo.gameChoice.isEmpty() && g != game) setGame(g, remember = false) } }
        // back from Steam's or Discord's sign-in in the browser (MainActivity)
        // (dispatched, never at once: the properties below are set by then)
        viewModelScope.launch(Dispatchers.Main) { AuthReturns.pending.collect { r -> if (r != null) { AuthReturns.pending.value = null; onReturn(r.first, r.second) } } }
        // another device uploaded the account (the server tells the live room): this phone reads it again at once
        viewModelScope.launch { live.syncNudges.collect { onSyncNudge(it) } }
    }

    /** A newer version on GitHub: shown as a banner on top. */
    fun checkUpdate() {
        viewModelScope.launch(Dispatchers.IO) { Updates.check(com.pitlanehq.android.BuildConfig.VERSION_NAME)?.let { update.value = it } }
        viewModelScope.launch(Dispatchers.IO) { news.value = Updates.news(com.pitlanehq.android.data.SERVER, com.pitlanehq.android.ui.I18n.lang) }
    }

    // back online: load again what was shown from the phone's saved copy
    private fun refreshStale() {
        if (!_account.value.signedIn) return
        if (sessions.value.stale || sessions.value.error != null) loadSessions()
        else if (monthStats.value.stale || monthStats.value.error != null) loadMonthStats()
        if (bests.value.stale || bests.value.error != null) loadBests()
        if (combos.value.stale || combos.value.error != null) loadCombos()
        if (reports.value.stale || reports.value.error != null) loadReports()
        if (setups.value.stale || setups.value.error != null) loadSetups()
        if (_account.value.error != null) sync()
    }

    private fun errKey(e: Throwable) = (e as? AppError)?.message ?: e.message ?: "server_down"

    // any call that finds the session gone signs the app out
    private fun <T> load(target: MutableStateFlow<Loadable<T>>, block: () -> Got<T>) {
        target.value = target.value.copy(loading = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching(block)
                .onSuccess { target.value = Loadable(data = it.data, stale = it.stale) }
                .onFailure { e ->
                    target.value = target.value.copy(loading = false, error = errKey(e))
                    if (e is SignedOut) signedOut()
                }
        }
    }

    private fun signedOut() {
        live.stop()
        supportUnread.value = 0; supportOpen.value = null
        demo.value = false
        _account.value = AccountState(error = "signed_out")
    }

    fun login(email: String, password: String) {
        _account.value = AccountState(email = email, busy = true)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.login(email, password) }
                .onSuccess { _account.value = it; demo.value = repo.demo; loadRaces(); resumeLive(); checkSupport() }
                .onFailure { _account.value = AccountState(email = email, error = errKey(it)) }
        }
    }

    /** Second step of the sign-in: the authenticator code. */
    fun loginCode(code: String) {
        val a = _account.value
        _account.value = a.copy(busy = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.loginCode(code) }
                .onSuccess { _account.value = it; demo.value = repo.demo; loadRaces(); resumeLive(); checkSupport() }
                .onFailure { e -> _account.value = if (e.message == "sign_in_again") AccountState(email = a.email, error = "sign_in_again") else a.copy(busy = false, error = errKey(e)) }
        }
    }

    fun cancelCode() { _account.value = AccountState(email = _account.value.email) }

    // ---------- Sign in with Steam or Discord, and linking them (Account) ----------
    val authUi = MutableStateFlow(AuthUi())

    /** Steam's or Discord's sign-in in the browser ([open]); it comes back to this app (pitlanehq://…, onReturn). */
    fun socialSignIn(prov: String, open: (String) -> Unit) {
        authUi.value = AuthUi(prov, busy = true)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val url = repo.loginStart(prov)
                authUi.value = AuthUi(prov)
                withContext(Dispatchers.Main) { open(url) }
            } catch (e: Exception) {
                authUi.value = AuthUi(prov, error = errKey(e))
            }
        }
    }

    /** The browser came back with the answer of a start of this app: signs in, opens the new account's form, or links. */
    private fun onReturn(prov: String, q: Map<String, String>) {
        val start = repo.takeStart(q["state"].orEmpty(), prov)
        if (start == null) { authUi.value = AuthUi(prov, error = prov + "_again"); return } // another start, or the app was closed meanwhile
        if (start.kind == "link") { finishLink(prov, start, q); return }
        authUi.value = AuthUi(prov, busy = true)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val g = q[prov + "Login"].orEmpty()
                val sid = q["sid"].orEmpty()
                authUi.value = when {
                    g == "0" && q["new"] == "1" && sid.isNotEmpty() -> { repo.keepSignup(start.code); AuthUi(prov, newName = q[if (prov == "discord") "name" else "persona"].orEmpty(), sid = sid) }
                    g == "0" && q["relink"] == "1" -> AuthUi(prov, error = "discord_relink_login")
                    g.isEmpty() || g == "0" -> AuthUi(prov, error = prov + "_failed")
                    else -> socialStep(prov, repo.socialLogin(prov, g, start.code, I18n.lang))
                }
            } catch (e: Exception) {
                authUi.value = AuthUi(prov, error = errKey(e))
            }
        }
    }

    /** What Account → Steam or Discord says went wrong (null: nothing). */
    private fun linkError(prov: String, e: String?) {
        if (prov == "discord") discord.value = discord.value.copy(error = e) else steam.value = steam.value.copy(error = e)
    }
    private fun linkReload(prov: String) { if (prov == "discord") loadDiscord() else loadSteam() }

    private fun finishLink(prov: String, start: AccountRepository.AuthStart, q: Map<String, String>) {
        val g = q[prov + "Link"].orEmpty()
        if (g.isEmpty()) {
            linkError(prov, if (q[prov + "Linked"] == "taken") "this ${if (prov == "discord") "Discord" else "Steam"} account is already linked to another account" else prov + "_not_linked")
            return
        }
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.socialLink(prov, g, start.code) }
                .onSuccess { linkReload(prov) }
                .onFailure { e -> linkError(prov, errKey(e)) }
        }
    }

    /** The sign-in left halfway: a half-done session is closed on the server. */
    fun socialCancel() {
        authUi.value = AuthUi()
        viewModelScope.launch(Dispatchers.IO) { repo.socialCancel() }
    }

    fun socialCode(code: String) {
        authUi.value = authUi.value.copy(busy = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.socialLoginCode(code) }
                .onSuccess { authUi.value = socialStep(authUi.value.prov, it) }
                .onFailure { e -> authUi.value = if (e.message == "sign_in_again") AuthUi(error = "sign_in_again") else authUi.value.copy(busy = false, error = errKey(e)) }
        }
    }

    /** Where a sign-in with Steam or Discord goes on: signed in (the server's copy of the key), the code or the password. */
    private fun socialStep(prov: String, s: AccountRepository.Social): AuthUi = when (s.step) {
        "code" -> AuthUi(prov, needCode = true)
        "in" -> { s.state?.let { _account.value = it }; demo.value = repo.demo; loadRaces(); resumeLive(); AuthUi() }
        else -> AuthUi(prov, needKey = true)
    }

    /** The password once on this phone after Steam or Discord: the data key, and you are in. */
    fun socialKey(email: String, password: String) {
        authUi.value = authUi.value.copy(busy = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.socialKey(email, password) }
                .onSuccess { authUi.value = AuthUi(); _account.value = it; demo.value = repo.demo; loadRaces(); resumeLive() }
                .onFailure { e -> authUi.value = authUi.value.copy(busy = false, error = errKey(e)) }
        }
    }

    /** The new account (from Steam or Discord: linked to it at once). Without a session yet, the email to confirm comes first. */
    fun register(email: String, password: String, name: String) {
        val u = authUi.value
        authUi.value = u.copy(busy = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.register(email, password, name, u.prov, u.sid, I18n.lang) }
                .onSuccess { r ->
                    authUi.value = AuthUi()
                    val st = r.state
                    if (st == null) _account.value = AccountState(email = email, error = if (r.discordTaken) "discord_taken_verify" else "verify your email first: we sent you a link, open it and then sign in")
                    else { _account.value = if (r.discordTaken) st.copy(error = "discord_taken") else st; demo.value = repo.demo; loadRaces(); resumeLive() }
                }
                .onFailure { e -> authUi.value = authUi.value.copy(busy = false, error = errKey(e)) }
        }
    }

    // Account → Steam (and Discord, below)
    val steam = MutableStateFlow(Loadable<SteamLink>())
    fun loadSteam() = load(steam) { Got(repo.steam()) }
    /** Linking asks the password, then Steam's or Discord's sign-in in the browser; it comes back to this app and links it. */
    fun linkStart(prov: String, password: String, open: (String) -> Unit) {
        linkError(prov, null)
        viewModelScope.launch(Dispatchers.IO) {
            try {
                val url = repo.linkStart(prov, password)
                withContext(Dispatchers.Main) { open(url) }
            } catch (e: Exception) {
                linkError(prov, errKey(e))
            }
        }
    }
    fun steamShow(shown: Boolean) = viewModelScope.launch(Dispatchers.IO) {
        runCatching { repo.steamShow(shown) }.onSuccess { loadSteam() }.onFailure { steam.value = steam.value.copy(error = errKey(it)) }
    }
    fun socialUnlink(prov: String, password: String) = viewModelScope.launch(Dispatchers.IO) {
        runCatching { repo.socialUnlink(prov, password) }.onSuccess { linkReload(prov) }.onFailure { linkError(prov, errKey(it)) }
    }

    // two-step sign-in: the screens wait on these (null = nothing pending)
    val twoFactorSetup = MutableStateFlow<com.pitlanehq.android.data.TwoFactorSetup?>(null)
    val recoveryCodes = MutableStateFlow<List<String>?>(null)
    val twoFactorError = MutableStateFlow<String?>(null)

    fun setup2fa(password: String) {
        twoFactorError.value = null
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.setup2fa(password) }.onSuccess { twoFactorSetup.value = it }.onFailure { twoFactorError.value = errKey(it) }
        }
    }

    fun enable2fa(code: String) {
        twoFactorError.value = null
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.enable2fa(code) }
                .onSuccess { twoFactorSetup.value = null; recoveryCodes.value = it; _account.value = repo.storedState().copy(busy = false) }
                .onFailure { twoFactorError.value = errKey(it) }
        }
    }

    fun disable2fa(password: String, code: String, done: () -> Unit) {
        twoFactorError.value = null
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.disable2fa(password, code) }
                .onSuccess { _account.value = repo.storedState().copy(busy = false); done() }
                .onFailure { twoFactorError.value = errKey(it) }
        }
    }

    /** quiet: by itself (the app opened or came back), without the spinner and without an error on screen. */
    fun sync(quiet: Boolean = false) {
        if (!quiet) _account.value = _account.value.copy(busy = true, error = null)
        viewModelScope.launch(Dispatchers.IO) {
            val before = _account.value.syncVersion
            runCatching { repo.sync() }
                .onSuccess {
                    // a new version of the bundle: the races and ratings held here are dropped and read again from it
                    if (it.syncVersion != before) { allRaces = emptyList(); bundleVer.value = bundleVer.value + 1 }
                    _account.value = it; demo.value = repo.demo; loadRaces()
                    // what is already on screen is read again too
                    if (sessions.value.data != null) loadSessions()
                    if (bests.value.data != null) loadBests()
                    // your profile's recent races (your own result in each), when they changed
                    runCatching { repo.publishProfileRaces() }
                }
                .onFailure { e -> if (e is SignedOut) signedOut() else if (!quiet) _account.value = _account.value.copy(busy = false, error = errKey(e)) }
        }
    }

    private var lastAuto = 0L

    /**
     * The app came to the screen (it opened, or came back from the background): your account, public
     * name, races and laps are read again by themselves, at most every 30 seconds.
     */
    fun onForeground() {
        startMinuteSync()
        startUsage()
        startSupport()
        track("game:$game")
        val a = _account.value
        resumeLive()
        if (!a.signedIn || a.busy || demo.value) return
        val now = System.currentTimeMillis()
        if (now - lastAuto < 30_000) return
        lastAuto = now
        sync(quiet = true)
    }

    private var minuteJob: Job? = null

    /** While the app is on the screen it reads the account once a minute (the same read as above), like the PC and the
     *  web; it stops when the app goes to the background. */
    private fun startMinuteSync() {
        if (minuteJob?.isActive == true) return
        minuteJob = viewModelScope.launch {
            while (true) {
                delay(60_000)
                val a = _account.value
                // a read made meanwhile (the nudge, coming back) counts: never two within the minute
                if (!a.signedIn || a.busy || demo.value || System.currentTimeMillis() - lastAuto < 55_000) continue
                lastAuto = System.currentTimeMillis()
                sync(quiet = true)
            }
        }
    }

    private var nudgeJob: Job? = null

    /** The server said another device uploaded the account: read it again in a moment (bursts become one read). */
    private fun onSyncNudge(version: Long) {
        val a = _account.value
        if (!a.signedIn || demo.value) return
        if (version != 0L && version <= a.syncVersion) return // this phone's own upload, or already read
        nudgeJob?.cancel()
        nudgeJob = viewModelScope.launch { delay(400); lastAuto = System.currentTimeMillis(); sync(quiet = true) }
    }

    fun logout() {
        live.stop()
        supportUnread.value = 0; supportLast.value = ""; supportOpen.value = null
        allRaces = emptyList(); allBests = null
        listOf(races, sessions, monthStats, bests, laps, analysis, combos, board, reports, setups, devices, discord, steam).forEach { (it as MutableStateFlow<Loadable<*>>).value = Loadable<Any>() }
        viewModelScope.launch(Dispatchers.IO) {
            repo.logout()
            demo.value = false
            _account.value = AccountState()
        }
    }

    /** Admins: admin mode on this phone (off by default: the app as everyone sees it), on to see what is for admins. */
    fun setAdminMode(on: Boolean) {
        if (!_account.value.realAdmin) return
        val wasDemo = demo.value
        repo.adminMode = on
        _account.value = repo.storedState()
        if (wasDemo && !repo.demo) setDemo(false) else demo.value = repo.demo
        supportUnread.value = 0; checkSupport()
    }

    // ---------- what the drivers use: counted on the phone, sent every 5 minutes on the screen and when it goes away ----------
    /** One use of a screen ("view:laps"), an action ("act:compare") or a game ("game:lmu"); never in demo data. */
    fun track(key: String) { if (key.startsWith("view:")) curView = key.removePrefix("view:"); if (!demo.value) repo.use(key) }
    /** The screen on view, by the PC's view names: where the feedback button was pressed ("menu:<view>"). */
    var curView = "home"
    /** Sends the feedback button's "Send feedback"; null when it went, else the error's key or the server's message. */
    suspend fun sendFeedback(text: String, rating: Int?): String? = withContext(Dispatchers.IO) {
        val err = runCatching { repo.sendFeedback(text, rating, curView) }.exceptionOrNull()
        if (err == null) track("act:feedback_sent")
        if (err is SignedOut) signedOut()
        err?.let { errKey(it) }
    }
    // ---------- the support chat (the feedback button) ----------
    /** Support's messages the driver has not read (an admin in admin mode: the drivers' messages not read), and the
     *  newest one's line when the server gives it; the button's count and the inbox's "Support replied". */
    val supportUnread = MutableStateFlow(0)
    val supportLast = MutableStateFlow("")
    /** The support chat open: "" the driver's own (or an admin's inbox), else that driver's thread (admins). */
    val supportOpen = MutableStateFlow<String?>(null)
    var supportNick = ""
    fun openSupport(accountId: String = "", nick: String = "") {
        if (demo.value || !_account.value.signedIn) return
        supportNick = nick; supportOpen.value = accountId; track("act:support_open")
    }
    fun closeSupport() { supportOpen.value = null; checkSupport() }
    private var supportJob: Job? = null
    /** Every 2 minutes while the app is on the screen and signed in: has Support (or a driver, for an admin) written? */
    private fun startSupport() {
        supportJob?.cancel()
        supportJob = viewModelScope.launch(Dispatchers.IO) { while (true) { supportCount(); delay(2 * 60_000L) } }
    }
    fun checkSupport() { viewModelScope.launch(Dispatchers.IO) { supportCount() } }
    private fun supportCount() {
        val a = _account.value
        if (!a.signedIn || demo.value) { supportUnread.value = 0; return }
        runCatching {
            if (a.admin) { supportUnread.value = repo.adminSupportUnread(); supportLast.value = "" }
            else repo.supportUnread().let { (n, last) -> supportUnread.value = n; supportLast.value = last }
        }.onFailure { if (it is SignedOut) signedOut() }
    }
    /** The driver's thread; reading it marks Support's messages read. */
    suspend fun supportThread(accountId: String): List<SupportMsg>? = withContext(Dispatchers.IO) {
        runCatching { if (accountId.isEmpty()) repo.support().also { supportUnread.value = 0; supportLast.value = "" } else repo.adminSupportThread(accountId) }
            .onFailure { if (it is SignedOut) signedOut() }.getOrNull()
    }
    suspend fun supportInbox(): List<SupportConv>? = withContext(Dispatchers.IO) {
        runCatching { repo.adminSupport() }.onFailure { if (it is SignedOut) signedOut() }.getOrNull()
    }
    /** Sends a message: the driver's to Support, or (an account id) an admin's reply as Support. Null when it went. */
    suspend fun supportSend(accountId: String, text: String): String? = withContext(Dispatchers.IO) {
        val err = runCatching { if (accountId.isEmpty()) repo.sendSupport(text, curView) else repo.adminSupportReply(accountId, text) }.exceptionOrNull()
        if (err == null) { track(if (accountId.isEmpty()) "act:support_sent" else "act:support_reply"); supportCount() }
        if (err is SignedOut) signedOut()
        err?.let { errKey(it) }
    }
    private var usageJob: Job? = null
    private fun startUsage() {
        usageJob?.cancel()
        usageJob = viewModelScope.launch(Dispatchers.IO) {
            while (true) { delay(5 * 60_000L); runCatching { repo.sendUsage() } }
        }
    }
    private fun sendUsageNow() { usageJob?.cancel(); usageJob = null; viewModelScope.launch(Dispatchers.IO) { runCatching { repo.sendUsage() } } }

    fun setDemo(on: Boolean) {
        if (on && !_account.value.admin) return
        repo.demo = on
        demo.value = on
        live.stop()
        if (on) { supportUnread.value = 0; supportOpen.value = null } else checkSupport()
        allBests = null
        listOf(sessions, monthStats, bests, laps, analysis, combos, board, reports, setups).forEach { (it as MutableStateFlow<Loadable<*>>).value = Loadable<Any>() }
        loadRaces()
    }

    fun setLanguage(l: String) {
        repo.language = l
        I18n.choice = l
    }

    fun loadRaces() = load(races) { val all = repo.races(); allRaces = all; Got(all.filter { it.game == game }) }

    /** Your iRating of every discipline, as the PC last saw it. */
    fun ratings(): Map<String, Triple<Int, String, Long>> = runCatching { repo.ratings() }.getOrDefault(emptyMap())
    fun lmuRating(): Pair<String, String>? = runCatching { repo.lmuRating() }.getOrNull()

    /** Your notes on other drivers (the race summary shows their tag and lets you change it). */
    val driverNotes = MutableStateFlow<Map<String, DriverNote>>(emptyMap())
    fun loadDriverNotes() { driverNotes.value = runCatching { repo.driverNotes() }.getOrDefault(emptyMap()) }
    fun setDriverNote(key: String, name: String, tag: String, note: String, done: (String?) -> Unit) = viewModelScope.launch(Dispatchers.IO) {
        val err = runCatching { repo.setDriverNote(key, name, tag, note) }.exceptionOrNull()
        loadDriverNotes()
        withContext(Dispatchers.Main) { done(err?.message) }
    }
    /** Your notes on each track (the track page shows them and lets you write the general one). */
    val trackNotes = MutableStateFlow<Map<Long, TrackNote>>(emptyMap())
    fun loadTrackNotes() { trackNotes.value = runCatching { repo.trackNotes() }.getOrDefault(emptyMap()) }
    fun setTrackNote(trackId: Long, track: String, general: String, done: (String?) -> Unit) = viewModelScope.launch(Dispatchers.IO) {
        val err = runCatching { repo.setTrackNote(trackId, track, general) }.exceptionOrNull()
        loadTrackNotes()
        withContext(Dispatchers.Main) { done(err?.message) }
    }
    /** The coach's plan to the coach overlay of your PC (its chosen corners in the account's settings): [done] gets whether
     *  it reached the account (false: no PC has synced settings yet) or the error. */
    fun planToOverlay(turns: List<String>, trackId: Long, done: (Boolean, String?) -> Unit) = viewModelScope.launch(Dispatchers.IO) {
        track("act:plan_to_overlay")
        val r = runCatching { repo.setCoachTurns(turns, trackId) }
        withContext(Dispatchers.Main) { done(r.getOrDefault(false), r.exceptionOrNull()?.message) }
    }
    /** Your sessions of the chosen game, asked like the web (limit=100&game=…), and Home's numbers of the month with them. */
    fun loadSessions() {
        val gm = game
        load(sessions) {
            val g = repo.sessions(gm)
            if (!gameAsked) noteStats(repo.gameCounts())
            g
        }
        loadMonthStats()
    }
    fun loadMonthStats() { val gm = game; load(monthStats) { repo.monthStats(gm) } }
    fun loadBests() = load(bests) { val g = repo.bests(); allBests = g.data; Got(g.data.filter { it.game == game }, g.stale) }
    fun loadLaps(id: String) { laps.value = Loadable(); load(laps) { repo.laps(id) } }
    fun loadCombos() = load(combos) { repo.combos() }

    // ---------- the Planner (in development: admins with admin mode on) ----------
    val season = MutableStateFlow(Loadable<SeasonData>())
    fun loadSeason() { if (season.value.data == null && !season.value.loading) load(season) { repo.season() } }
    val plannerFav = MutableStateFlow(repo.plannerFav)
    val plannerPlan = MutableStateFlow(repo.plannerPlan)
    fun toggleStar(sid: Long) { val f = plannerFav.value.toMutableSet(); if (!f.remove(sid)) f += sid; repo.plannerFav = f; plannerFav.value = f }
    fun inPlan(sid: Long, t: Long) = plannerPlan.value.any { it.sid == sid && it.t == t }
    fun togglePlan(s: SSeries, t: Long) {
        val now = System.currentTimeMillis()
        val p = plannerPlan.value.filter { it.t > now - 3 * 3_600_000L }.toMutableList()
        if (p.removeAll { it.sid == s.sid && it.t == t }.not()) p += PlannedRace(s.sid, t, s.name, Season.weekAt(s, t).track)
        p.sortBy { it.t }; repo.plannerPlan = p; plannerPlan.value = p
    }
    // the series page and the week the Planner opened
    var plannerSeries by mutableStateOf<SSeries?>(null)

    // Le Mans Ultimate: "This car / Whole class" (each driver's best of any car of this car's class here), kept while the app runs
    val boardWhole = MutableStateFlow(false)
    val boardCls = MutableStateFlow<String?>(null)
    fun loadBoard(c: Combo) {
        val lmu = game == "lmu"
        board.value = Loadable(); boardCls.value = if (lmu) repo.boardClass(c.trackId, c.carId) else null
        val whole = boardWhole.value
        load(board) {
            val known = if (lmu) repo.boardClass(c.trackId, c.carId) else null
            if (whole && known != null) repo.classBoard(c.trackId, known)
            else {
                val g = repo.leaderboard(c.trackId, c.carId)
                val cls = if (lmu) repo.boardClass(c.trackId, c.carId) else null
                boardCls.value = cls
                if (whole && cls != null) repo.classBoard(c.trackId, cls) else g
            }
        }
    }
    fun setBoardWhole(c: Combo, on: Boolean) { if (boardWhole.value == on) return; boardWhole.value = on; loadBoard(c) }
    // Community's recent records, and the track page (in development) of the track chosen
    val records = MutableStateFlow(Loadable<List<RecordItem>>())
    fun loadRecords() = load(records) { repo.records() }
    val trackPage = MutableStateFlow(Loadable<TrackPage>())
    var trackRef: Pair<Long, String>? = null
    fun openTrack(id: Long, name: String) { trackRef = id to name; trackPage.value = Loadable(); load(trackPage) { repo.trackPage(id) } }
    /** The Tracks tab's main card: the layout of the circuit you drove most (null while it loads or when it has none). */
    val heroLayout = MutableStateFlow<Pair<Long, Pair<List<Double>, List<Double>>?>?>(null)
    private var heroGame = ""
    fun loadHeroLayout(trackId: Long) {
        val g = game
        if (trackId <= 0 || (heroLayout.value?.first == trackId && heroGame == g)) return
        heroGame = g
        heroLayout.value = trackId to null
        viewModelScope.launch { heroLayout.value = trackId to withContext(Dispatchers.IO) { runCatching { repo.trackLayout(trackId, g) }.getOrNull() } }
    }
    fun loadReports() = load(reports) { repo.reports() }
    fun loadSetups() = load(setups) { repo.setups() }
    fun loadDevices() = load(devices) { Got(repo.devices()) }
    /** A driver's profile, from one of their laps (null: yours). */
    fun loadProfile(lapId: String?) { profileLap = lapId; profile.value = Loadable(); load(profile) { Got(repo.profile(lapId)) } }
    val leagues = MutableStateFlow(Loadable<List<League>>())
    val leagueLimit = MutableStateFlow(LeagueLimit())
    fun loadLeagues() = load(leagues) { val l = repo.leagues(); leagueLimit.value = repo.leagueLimit; Got(l) }
    fun saveLeague(id: String?, l: League, done: (String?) -> Unit) = viewModelScope.launch(Dispatchers.IO) {
        val e = runCatching { repo.saveLeague(id, l) }.exceptionOrNull()
        kotlinx.coroutines.withContext(Dispatchers.Main) { done(e?.let { errKey(it) }) }
        if (e == null) loadLeagues()
    }
    fun deleteLeague(id: String) = viewModelScope.launch(Dispatchers.IO) { runCatching { repo.deleteLeague(id) }; loadLeagues() }
    /** A post opened or one of its links pressed: the server counts it once per driver and day (never your own post). */
    fun hitLeague(id: String, kind: String) = viewModelScope.launch(Dispatchers.IO) { runCatching { repo.leagueHit(id, kind) } }
    /** Your post's last 14 days of views and clicks. */
    fun leagueDays(id: String, done: (List<LeagueDay>) -> Unit) = viewModelScope.launch(Dispatchers.IO) {
        val d = runCatching { repo.leagueDays(id) }.getOrDefault(emptyList())
        withContext(Dispatchers.Main) { done(d) }
    }
    fun setBadgeHidden(hidden: Boolean) = viewModelScope.launch(Dispatchers.IO) { runCatching { repo.setBadgeHidden(hidden) }; loadProfile(profileLap) }
    fun adminSupporter(id: String, on: Boolean) = viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminSupporter(id, on) }; loadAdmin("users") }

    fun revoke(id: String) {
        viewModelScope.launch(Dispatchers.IO) {
            runCatching { repo.revoke(id) }.onFailure { devices.value = devices.value.copy(error = errKey(it)) }
            loadDevices()
        }
    }

    // Account → Discord
    fun loadDiscord() = load(discord) { Got(repo.discord()) }
    fun discordShow(shown: Boolean) = viewModelScope.launch(Dispatchers.IO) {
        runCatching { repo.discordShow(shown) }.onSuccess { loadDiscord() }.onFailure { discord.value = discord.value.copy(error = errKey(it)) }
    }

    /** Analysis → Coach: the best valid lap of a session against the model's next level (else the record), once per session */
    fun coachFor(s: CloudSession, all: List<CloudLap>) {
        // your best lap (a friend's lap in DRINKS mode is never the account's), else the fastest lap of the session
        val best = all.filter { it.valid && it.time > 0 && it.drv.isEmpty() }.minByOrNull { it.time } ?: all.filter { it.valid && it.time > 0 }.minByOrNull { it.time }
        if (best == null) { coach.value = Loadable(); coachKey = ""; return }
        if (coachKey == s.id + "|" + best.id && (coach.value.data != null || coach.value.loading)) return
        coachKey = s.id + "|" + best.id
        analyse(s, best, all, RefKind.LEVEL, coach)
    }

    /** Opens a lap and the lap it is compared with: the driver's own best lap of the session, or the model's next level or record. */
    fun analyse(s: CloudSession, lap: CloudLap, all: List<CloudLap>, kind: RefKind, into: MutableStateFlow<Loadable<LapAnalysis>> = analysis) {
        into.value = Loadable(loading = true)
        load(into) {
            val tr = repo.lapTrace(lap.id)
            var ref: Trace? = null
            var label = ""
            var refTime: Double? = null
            var refSec: List<Double> = emptyList()
            // the car and track of this session among the ones the community knows, matched by name
            val gm = s.game
            val combos = runCatching { repo.combos(gm).data }.getOrNull() ?: emptyList()
            val c = combos.firstOrNull { it.track.equals(s.track, true) && it.car.equals(s.car, true) }
                ?: combos.firstOrNull { s.track.startsWith(it.track, true) && it.car.equals(s.car, true) }
            // the car card needs the car alone: what it does on other tracks, for when nobody known drove it here yet
            val card = (c ?: combos.firstOrNull { it.car.equals(s.car, true) })?.let { runCatching { repo.carCard(it.carId, gm) }.getOrNull() }
            var fastest = false
            var cards: List<CornerCard> = emptyList()
            // lap B's path as the web's analysis takes it: a model reference's own (the web's, lineXY and its origin when it has
            // none), else the trace's
            var modelPath = false
            var refPath: LapPath? = null
            // each driver against their own laps (DRINKS mode: a friend's lap against that friend's best)
            val ownBest = {
                val best = all.filter { it.valid && it.time > 0 && it.id != lap.id && it.drv == lap.drv }.minByOrNull { it.time }
                if (best != null) {
                    ref = runCatching { repo.lapTrace(best.id) }.getOrNull()
                    label = "L${best.n}"
                    refTime = best.time
                    refSec = best.sectors
                }
            }
            if (kind == RefKind.MY_BEST) ownBest()
            else {
                // the model's references, like the PC and the web: the next level, else the record
                val mr = c?.let { runCatching { repo.modelRefs(it.trackId, it.carId, lap.time, gm, tr?.cmp ?: 0) }.getOrNull() }
                val rec = mr?.rec; val lvl = mr?.lvl
                cards = mr?.corners ?: emptyList()
                val pick = if (kind == RefKind.LEVEL) lvl ?: rec else rec
                if (pick != null && pick.second < lap.time - 0.001) {
                    ref = pick.first
                    refTime = pick.second
                    modelPath = true
                    refPath = if (pick === lvl) mr?.lvlXY else mr?.recXY
                    label = if (pick === lvl) "▲ " + com.pitlanehq.android.ui.t("next_level") else "★ " + com.pitlanehq.android.ui.t("record")
                } else {
                    // nobody known is faster here (this lap is the record) or nobody known at all: like the web's coach,
                    // your own best lap of the session is lap B
                    fastest = pick != null
                    ownBest()
                }
            }
            // a rival's lap has no path (it comes from its place on track): the line is then measured against your
            // own best lap of the session, the fastest line known here
            val r0 = ref
            if (r0 != null && (r0.x == null || r0.y == null)) {
                val best = all.filter { it.valid && it.time > 0 && it.id != lap.id && it.drv == lap.drv }.minByOrNull { it.time }
                val bt = best?.let { runCatching { repo.lapTrace(it.id) }.getOrNull() }
                val bx = bt?.x; val by = bt?.y
                if (bx != null && by != null && kotlin.math.abs(bx.size - r0.rows.size) <= 6) {
                    fun fit(v: List<Double>) = List(r0.rows.size) { v[minOf(it, v.size - 1)] }
                    ref = r0.copy(x = fit(bx), y = fit(by), g = bt.g)
                }
            }
            // the official turn numbers of this track, when an admin has placed them on its map (else the corners are counted)
            val turns = c?.let { runCatching { repo.turns(it.trackId, gm) }.getOrNull() } ?: emptyList()
            val coach = runCatching { repo.coachInfo() }.getOrNull()
            val habits = runCatching { repo.coachHabits() }.getOrDefault(emptyList())
            // every map's road is the track's layout drawn by the community (the lap's own path only when there is none)
            val layout = if (c != null) runCatching { repo.trackLayout(c.trackId, gm) }.getOrNull() else null
            // the corner card also when lap B is your own lap: the model knows the corners whoever the reference is
            if (kind == RefKind.MY_BEST && c != null) cards = runCatching { repo.modelRefs(c.trackId, c.carId, lap.time, gm, tr?.cmp ?: 0).corners }.getOrDefault(emptyList())
            // the web's own analysis of the two laps, the same corners, tips, plan and sectors as the PC's
            // (the module counts a point every 5 m: other traces, the demo data's, go to LapMath). The coach also hands it the
            // session's laps, like the web's: how steady each corner is gives the plan its consistency steps.
            val rB = ref; val tB = refTime
            val js = if (tr != null && rB != null && tB != null && JsAnalysis.runs(tr) && JsAnalysis.runs(rB)) runCatching {
                val w = CoachWeights(coach?.w ?: emptyMap(), coach?.ask ?: emptyMap(), coach?.off ?: emptySet(), repo.coachMeWeights(), habits.map { Triple(it.kind, it.tracks, it.sessions) })
                val laps = if (into === this@PitlaneViewModel.coach) repo.sessionTraces(s.id).filter { it.first && JsAnalysis.runs(it.second) }.map { JsAnalysis.sessionLap(it.second, it.first) } else emptyList()
                repo.analysisJs.analyse(JsAnalysis.lap(tr, lap.time, lap.sectors), JsAnalysis.lap(rB, tB, refSec, if (modelPath) refPath else JsAnalysis.pathOf(rB)),
                    JsAnalysis.ctx("en", turns, w, cards), laps)
            }.getOrNull() else null
            Got(LapAnalysis(lap, tr, ref, label, refTime, refSec, card, turns, fastest = fastest, layout = layout, session = s, trackId = c?.trackId ?: 0, carId = c?.carId ?: 0, corners = cards, coach = coach, habits = habits, js = js))
        }
    }

    /** The thumbs the driver gave the coach's tips on this device, by session and corner ("sid:apexM" → 1 or -1). */
    val tipRatings = MutableStateFlow<Map<String, Int>>(emptyMap())
    /** A thumb on a tip (pressing the same one again takes it back): kept on the server with the account, so the coach learns. */
    fun rateTip(an: LapAnalysis, k: Corner, up: Int) {
        val s = an.session ?: return
        val key = s.id + ":" + k.apexM
        val now = if (tipRatings.value[key] == up) 0 else up
        tipRatings.value = tipRatings.value.toMutableMap().also { if (now == 0) it.remove(key) else it[key] = now }
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.rateTip(an.trackId, an.carId, s.id, s.started, k.n, k.apexM, k.tip?.removePrefix("tip_") ?: "", k.cls, now, s.game) } }
    }

    // the live map: the track's layout drawn by the community, and its official turns, once per track
    val liveTrack = MutableStateFlow<Triple<Long, Pair<List<Double>, List<Double>>?, List<Double>>?>(null)
    private var liveTrackGame = ""
    fun loadLiveTrack(trackId: Long) {
        // the layouts and turns are per game: the one your PC reads
        val g = liveState.value.source.ifEmpty { "iracing" }
        if (trackId <= 0 || (liveTrack.value?.first == trackId && liveTrackGame == g)) return
        liveTrackGame = g
        liveTrack.value = Triple(trackId, null, emptyList())
        viewModelScope.launch {
            val r = withContext(Dispatchers.IO) { Triple(trackId, runCatching { repo.trackLayout(trackId, g) }.getOrNull(), runCatching { repo.turns(trackId, g) }.getOrDefault(emptyList())) }
            liveTrack.value = r
        }
    }

    // Telemetry (and DRINKS) on screen: the PC streams only while somebody watches
    private var liveScreens = 0
    fun startLive() { liveScreens++; resumeLive() }
    // leaving Telemetry: back to presence only (the server's sync nudge keeps reaching the phone)
    fun stopLive() { if (liveScreens > 0) liveScreens--; resumeLive() }
    /**
     * The link to the account's live room as the screen needs it: Telemetry watches your PC (or a code), every
     * other screen keeps presence only, so another device's upload reaches this phone at once.
     */
    fun resumeLive() {
        if (!_account.value.signedIn) { live.stop(); return }
        if (liveScreens > 0) live.start() else if (!demo.value) live.startPresence() else live.stop()
    }
    fun onBackground() { minuteJob?.cancel(); minuteJob = null; supportJob?.cancel(); supportJob = null; live.stop(); sendUsageNow() }
    fun liveWatch(m: LiveMode, code: String = "") {
        if (m == LiveMode.OWN) track("act:connect") else if (m == LiveMode.CODE) track("act:watch_code")
        live.watch(m, code)
    }
    fun liveShare(on: Boolean, new: Boolean = false) { if (on) track("act:share_code"); live.share(on, new) }
    fun liveAskAgain() = live.askAgain()
    fun setDrinks(on: Boolean, guest: String, guestAuto: Boolean) { if (on) track("act:drinks"); live.setDrinks(on, guest, guestAuto) }
    // a new DRINKS name is checked first: names used by other people on Pitlane HQ are refused
    val drinksTaken = MutableStateFlow<String?>(null)
    fun setDrinksGuest(name: String, known: List<String>) {
        drinksTaken.value = null
        if (name.isBlank() || known.any { it.equals(name, true) }) { setDrinks(true, name, false); return }
        viewModelScope.launch(Dispatchers.IO) { if (repo.nameFree(name)) setDrinks(true, name, false) else drinksTaken.value = name }
    }
    // a DRINKS driver renamed: a new name is checked first like any other
    fun renameDrinksGuest(from: String, to: String, known: List<String>) {
        drinksTaken.value = null
        val n = to.trim().take(32)
        if (n.isBlank() || n == from) return
        if (!n.equals(from, true) && known.any { it.equals(n, true) }) { drinksTaken.value = n; return }
        viewModelScope.launch(Dispatchers.IO) { if (repo.nameFree(n)) live.renameDrinksGuest(from, n) else drinksTaken.value = n }
    }
    fun forgetDrinksGuest(name: String) = live.forgetDrinksGuest(name)
    // admin profile
    // the sections, the PC's: summary (the key numbers and the analytics), users, feedback, content (the shared items),
    // sessions, coach, server (the mail, the tools and the blocked sign-ins). [items] is the section's rows; [extra] the
    // summary's status, the server's status, the coach's answer.
    data class AdminState(val kind: String, val items: List<org.json.JSONObject>? = null, val error: String? = null,
                          val extra: org.json.JSONObject? = null, val days: Int = 14)
    val admin = MutableStateFlow(AdminState("summary"))
    fun loadAdmin(kind: String, days: Int = admin.value.days) {
        admin.value = AdminState(kind, days = days)
        viewModelScope.launch(Dispatchers.IO) {
            admin.value = runCatching {
                when (kind) {
                    // the analytics may not be there yet (an older server): the key numbers still show
                    "summary" -> AdminState(kind, listOfNotNull(runCatching { repo.adminAnalytics(days) }.getOrNull()), extra = repo.adminStatus(), days = days)
                    "users" -> {
                        val use = runCatching { repo.adminAnalytics(30) }.getOrNull()?.optJSONArray("users")
                        val byId = (0 until (use?.length() ?: 0)).mapNotNull { use!!.optJSONObject(it) }.associateBy { it.optString("id") }
                        AdminState(kind, repo.adminList("users").onEach { u -> byId[u.optString("id")]?.let { u.put("_use", it) } }, days = days)
                    }
                    "feedback" -> AdminState(kind, repo.adminFeedback(), days = days)
                    "content" -> AdminState(kind, repo.adminList("uploads"), days = days)
                    "coach" -> repo.adminCoach().let { c -> AdminState(kind, (0 until (c.optJSONArray("buckets")?.length() ?: 0)).mapNotNull { c.optJSONArray("buckets")!!.optJSONObject(it) }.sortedByDescending { it.optInt("n") }, extra = c, days = days) }
                    "server" -> AdminState(kind, repo.adminList("blocked"), extra = repo.adminStatus(), days = days)
                    else -> AdminState(kind, repo.adminList(kind), days = days)
                }
            }.getOrElse { AdminState(kind, error = it.message ?: "server_down", days = days) }
        }
    }
    fun adminCoachOff(kind: String, cls: String, off: Boolean) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminCoachOff(kind, cls, off) }; loadAdmin("coach") }
    }
    fun adminCoachConfidence(on: Boolean) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminCoachConfidence(on) }; loadAdmin("coach") }
    }
    fun adminSince(id: String, since: Long?) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminSince(id, since) }; loadAdmin("users") }
    }
    fun adminAccount(id: String, act: String, name: String? = null) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminAccount(id, act, name) }; loadAdmin("users") }
    }
    fun adminUnlock(key: String, value: String, reload: String) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminUnlock(key, value) }; loadAdmin(reload) }
    }
    fun adminTool(tool: String) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminTool(tool) }; loadAdmin("server") }
    }
    fun adminDeleteUser(id: String) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminDeleteUser(id) }; loadAdmin("users") }
    }
    fun adminDelete(kind: String, id: String) {
        viewModelScope.launch(Dispatchers.IO) { runCatching { repo.adminDelete(kind, id) }; loadAdmin("content") }
    }

    override fun onCleared() {
        live.stop()
        runCatching { cm?.unregisterNetworkCallback(netCallback) }
        super.onCleared()
    }
}
