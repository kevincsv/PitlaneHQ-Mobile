package com.pitlanehq.android.model

/** Live telemetry from PitlaneHQ.exe, relayed end-to-end encrypted through the Pitlane HQ server. */
data class LiveState(
    val link: LinkState = LinkState.OFF,
    val pcOnline: Boolean = false,
    val simConnected: Boolean = false,
    val values: Map<String, Any?> = emptyMap(),
    val drinks: Drinks? = null,
    val message: String? = null,
    val mode: LiveMode = LiveMode.IDLE,   // what this screen watches
    val code: String = "",                // the code of the driver you watch (CODE)
    val myCode: String = "",              // your share code, as your PC says (OWN)
    // Connect asks your PC first: "" (not asked), "wait" (your PC shows Accept / Decline) or "ok"
    val ask: String = "",
    val askAt: Long = 0L,
    val declinedAt: Long = 0L,            // when your PC declined this phone
    val arrays: Map<String, List<Double>> = emptyMap(), // the per-car values (CarIdx…)
    val session: LiveSession? = null,     // the session YAML the PC sends: drivers, track
    val ownDelta: Double? = null,         // DRINKS mode: the current lap against this driver's own best (LiveLaps)
    val ownBest: Double? = null,
    val rec: LiveRec? = null,            // the laps this phone saw (Full and Compare laps)
    val recVer: Int = 0,
    val source: String = ""               // the sim your PC is reading ("iracing", "lmu"), from its status
) {
    fun num(name: String): Double? = when (val v = values[name]) { is Number -> v.toDouble(); is Boolean -> if (v) 1.0 else 0.0; else -> null }
}

/** IDLE: only whether your PC is online (it sends nothing); OWN: you watch your PC; CODE: you watch someone's share code. */
enum class LiveMode { IDLE, OWN, CODE }

/** DRINKS mode on the PC (admins only): friends drive and their laps go to the community under their name. */
data class Drinks(val admin: Boolean, val on: Boolean, val guest: String, val guestAuto: Boolean, val guests: List<String>, val driver: String)

enum class LinkState { OFF, CONNECTING, OPEN }

/** The variables the phone asks the PC for. */
val LIVE_VARS = listOf(
    "Speed", "RPM", "Gear", "FuelLevel", "Lap", "LapCurrentLapTime", "LapLastLapTime", "LapBestLapTime",
    "LapDeltaToBestLap", "LapDeltaToBestLap_OK", "Throttle", "Brake", "PlayerCarPosition", "PlayerCarClassPosition", "PlayerCarIdx",
    "LapCompleted", "LapDist", "LapDistPct", "OnPitRoad", "IsOnTrack", "SessionNum", "SessionLapsRemainEx", "SessionTimeRemain",
    "PlayerCarMyIncidentCount", "FuelUsePerLap",
    // the other cars: the standings, the relative and the map
    "CarIdxLapDistPct", "CarIdxPosition", "CarIdxClassPosition", "CarIdxLap", "CarIdxF2Time", "CarIdxEstTime",
    "CarIdxLastLapTime", "CarIdxBestLapTime", "CarIdxOnPitRoad"
) + listOf("LF", "RF", "LR", "RR").flatMap { c -> listOf("tempCL", "tempCM", "tempCR", "wearL", "wearM", "wearR", "coldPressure").map { c + it } }

/** One of your own sessions uploaded by the PC (GET /api/sessions). */
data class CloudSession(
    val id: String,
    val started: Long,
    val track: String,
    val trackConfig: String,
    val car: String,
    val kind: String,
    val laps: Int,
    val best: Double?,
    val cat: String? = null,   // the discipline: oval, sports_car, formula_car, dirt_oval, dirt_road
    val lic: String? = null,   // your license class in it: R, D, C, B, A, P
    val drvs: List<String> = emptyList(),  // the friends who drove laps of it in DRINKS mode
    val ai: Boolean = false,   // a session against iRacing's AI
    val game: String = "iracing"  // the sim it was driven in: iracing or lmu (Le Mans Ultimate)
)

data class CloudLap(val id: String, val n: Int, val time: Double, val valid: Boolean, val sectors: List<Double>, val inc: Int = 0, val drv: String = "")  // drv: a friend's lap (DRINKS mode)

/** A lap trace: one row every [bin] metres: speed m/s, throttle 0-1, brake 0-1, gear, steering rad, lap time s. */
/** One incident of a lap: where (m), its points and what it was ("off", "loss", "light" contact or "contact"). */
data class Incident(val d: Double, val pts: Int, val kind: String)

data class Trace(val bin: Double, val rows: List<DoubleArray>, val x: List<Double>? = null, val y: List<Double>? = null, val inc: List<Double> = emptyList(), val incK: List<String> = emptyList(),
                 val g: List<Double>? = null  // the origin [lat, lon] of x=0, y=0 when the path comes from the game's position (exact); null by dead reckoning
) {
    /** The incidents of the lap, from the trace's [d, pts, d, pts…] and their kinds (older laps: by the points). */
    val incidents: List<Incident> get() = (0 until inc.size / 2).map { i ->
        val pts = inc[2 * i + 1].toInt()
        Incident(inc[2 * i], pts, incK.getOrNull(i) ?: when { pts >= 4 -> "contact"; pts == 2 -> "loss"; else -> "off" })
    }
    /** The shape of the track: where the car was at every row (Pitlane HQ 0.5 and later record it). */
    val hasShape get() = x != null && y != null && x.size == rows.size && x.size > 10
    val speedKph get() = rows.map { it[0] * 3.6 }
    val throttle get() = rows.map { it.getOrElse(1) { 0.0 } }
    val brake get() = rows.map { it.getOrElse(2) { 0.0 } }
    val time get() = rows.map { it.getOrElse(5) { 0.0 } }
}

/** Your best lap per track and car (GET /api/bests). */
data class PersonalBest(
    val track: String, val trackConfig: String, val car: String, val best: Double, val laps: Int, val last: Long,
    val bestLapId: String?, val bestSessionId: String?, val game: String = "iracing"
)

/** A track and car the community has laps for (GET /community/combos). */
data class Combo(val trackId: Long, val track: String, val carId: Long, val car: String, val laps: Int, val best: Double?, val cat: String? = null)

/** A record of the leaderboards: the fastest lap of a car and track, and the lap it beat (the second fastest), for
 *  Community's "Recent records" and the track page. */
data class RecordItem(val id: String, val trackId: Long, val track: String, val carId: Long, val car: String, val cat: String?, val time: Double, val created: Long,
    val alias: String, val n: Int, val hasTrace: Boolean, val mine: Boolean, val prof: Boolean, val sup: Boolean, val prevTime: Double?, val prevAlias: String?) {
    val combo get() = Combo(trackId, track, carId, car, n, time, cat)
}

/** A track's page (in development): its layout and official turns, how many drivers and laps it has, the record of every car on it. */
data class TrackPage(val trackId: Long, val track: String, val drivers: Int, val laps: Int, val layout: Pair<List<Double>, List<Double>>?, val turns: List<Double>, val cars: List<RecordItem>)

/** `mine`: the signed-in driver's own lap, also when it was shared anonymously (only they see that). */
data class CommunityLap(val id: String, val alias: String, val time: Double, val created: Long, val hasTrace: Boolean, val sectors: List<Double>, val mine: Boolean = false,
    val lic: String? = null, val prof: Boolean = false, val sup: Boolean = false, val field: Boolean = false)

/** A driver's profile: their nickname (never their iRacing name), license classes, recent races and laps on the leaderboards. */
data class DriverProfile(val name: String, val since: Long, val mine: Boolean, val admin: Boolean, val anonymous: Boolean, val supporter: Boolean, val supporterHidden: Boolean,
    val lics: Map<String, String>, val races: List<ProfileRace>, val laps: List<ProfileLap>, val days: Map<String, Int> = emptyMap(),
    val discordId: String = "", val discordHandle: String = "")
data class ProfileRace(val whenMs: Long, val track: String, val car: String, val cat: String?, val lic: String?, val official: Boolean, val start: Int, val finish: Int, val field: Int,
    val inc: Int, val best: Double?, val irChange: Int, val dnf: Boolean)
data class ProfileLap(val track: String, val car: String, val time: Double, val created: Long, val cat: String?, val lic: String?, val anon: Boolean,
    val trackId: Long = 0, val carId: Long = 0, val pos: Int = 0, val of: Int = 0)

/** A league posted on the hub: the days it races (0 Monday … 6 Sunday), the usual start in its time zone, one or
 *  several disciplines (mixed), an optional Discord invite and website, whether it is looking for drivers; the views
 *  and clicks only for its creator (−1 for everyone else). */
/** How many leagues you may post: 3, or 10 as a supporter (Patreon or by hand). */
data class LeagueLimit(val limit: Int = 3, val supporter: Boolean = false, val free: Int = 3, val supporterLimit: Int = 10)
data class League(val id: String, val name: String, val about: String, val cat: String?, val discord: String, val web: String, val schedule: String, val cars: String, val lang: String, val mine: Boolean = false, val by: String = "",
    val cats: List<String> = emptyList(), val days: List<Int> = emptyList(), val time: String = "", val tz: String = "", val open: Boolean = true, val views: Int = -1, val clicks: Int = -1,
    val created: Long = 0, val updated: Long = 0)

/** One day of a league post's views and clicks, for its creator's chart. */
data class LeagueDay(val day: String, val views: Int, val clicks: Int)

/** The disciplines of a league: the new list, or the one discipline older posts carry. */
fun leagueDiscs(x: League): List<String> = if (x.cats.isNotEmpty()) x.cats else listOfNotNull(x.cat)

/** The next race of a league: the first of its days at its time, in its zone, from an hour ago on (a race under way
 *  counts); null without a schedule. */
fun leagueNext(x: League, now: java.time.ZonedDateTime = java.time.ZonedDateTime.now()): java.time.ZonedDateTime? {
    if (x.days.isEmpty() || !Regex("^([01]\\d|2[0-3]):[0-5]\\d$").matches(x.time)) return null
    val zone = runCatching { java.time.ZoneId.of(x.tz.ifBlank { "UTC" }) }.getOrDefault(java.time.ZoneId.of("UTC"))
    val t = java.time.LocalTime.parse(x.time)
    val today = now.withZoneSameInstant(zone).toLocalDate()
    val limit = now.toInstant().toEpochMilli() - 3600_000
    return (0..7).asSequence().map { today.plusDays(it.toLong()) }.filter { it.dayOfWeek.value - 1 in x.days }
        .map { java.time.ZonedDateTime.of(it, t, zone) }.firstOrNull { it.toInstant().toEpochMilli() >= limit }
}

data class SharedReport(val id: String, val alias: String, val track: String, val car: String, val created: Long, val finish: Int, val field: Int, val best: Double?, val mine: Boolean = false)

data class SharedSetup(val id: String, val alias: String, val name: String, val car: String, val track: String, val notes: String, val downloads: Int, val created: Long)

data class Device(val id: String, val device: String, val lastSeen: Long, val current: Boolean)

/** Your Discord account linked to this one (`oauth`: the server can link it with Discord's sign-in). */
data class DiscordLink(val linked: Boolean, val id: String, val handle: String, val shown: Boolean, val oauth: Boolean)

/** Your Steam account linked to this one (Account → Steam): its persona name and whether your profile shows it. */
data class SteamLink(val linked: Boolean, val id: String, val persona: String, val shown: Boolean)

/** The sims the phones show, one at a time (Home, Analysis, Community): iRacing and Le Mans Ultimate (in beta). */
val GAMES = listOf("iracing", "lmu")

/** A race the PC recorded (races.json in the account sync). */
data class Race(
    val id: String, val whenMs: Long, val track: String, val car: String, val official: Boolean,
    val start: Int, val finish: Int, val field: Int, val inc: Int, val best: Double?, val fieldBest: Double?,
    val avg: Double?, val consistency: Double?, val pits: Int, val fuelUsed: Double?,
    val ir: Int, val irChange: Int, val sof: Int, val dnf: Boolean,
    val laps: List<RaceLap>, val results: List<RaceResult>,
    val cat: String? = null,  // the discipline as iRacing names it (Oval, Road, DirtOval…); raceDisc tells which of ours
    val drinks: List<String> = emptyList(),  // DRINKS mode: who drove it when a friend drove any lap (the PC's report)
    val ai: Boolean = false,  // a race against iRacing's AI drivers (an offline race)
    val game: String = "iracing"  // the sim: Le Mans Ultimate (lmu) has no iRating and counts contacts, not incidents
) {
    /** DRINKS mode: who drove the race, with their laps and best lap, in the order they first drove ([] when you alone) */
    fun drivers(): List<Triple<String, Int, Double?>> {
        if (laps.none { it.drv.isNotEmpty() }) return emptyList()
        val own = drinks.firstOrNull { n -> laps.none { it.drv.equals(n, true) } } ?: "Me"
        val out = LinkedHashMap<String, Pair<String, MutableList<RaceLap>>>()
        laps.forEach { l -> val n = l.drv.ifEmpty { own }; out.getOrPut(n.lowercase()) { n to mutableListOf() }.second.add(l) }
        return out.values.map { (n, ls) -> Triple(n, ls.size, ls.filter { it.time > 0 && !it.cut && !it.pit }.minOfOrNull { it.time }) }
    }
    /** no iRating at all: a race against the AI, or one in another sim (Le Mans Ultimate has none) */
    val noIr: Boolean get() = ai || game != "iracing"
    /** Le Mans Ultimate counts contacts, not iRacing's incident points */
    val contacts: Boolean get() = game == "lmu"
    /** who drove a lap: the friend's name, or yours */
    fun driverOf(l: RaceLap): String = l.drv.ifEmpty { drinks.firstOrNull { n -> laps.none { it.drv.equals(n, true) } } ?: "Me" }
}

/** The discipline of a race as the PC tells it (discipline in journal.go, raceDisc in the web): iRacing says "Road"
 *  for sports and formula cars alike, so the car name tells which. */
fun raceDisc(cat: String?, car: String): String {
    val c = (cat ?: "").lowercase().replace(Regex("[ _-]"), "")
    mapOf("oval" to "oval", "dirtoval" to "dirt_oval", "dirtroad" to "dirt_road", "formulacar" to "formula_car", "sportscar" to "sports_car")[c]?.let { return it }
    if (c.isNotEmpty() && c != "road") return c
    if (car.isEmpty()) return ""
    if (Regex("p217|lmp|\\bgtp\\b|\\bdpi?\\b|prototype|hypercar", RegexOption.IGNORE_CASE).containsMatchIn(car)) return "sports_car"
    val formula = Regex("formula|\\bf[1-4]\\b|super ?formula|dallara|indy|\\bir-?\\d+|skip barber|ff1600|pro mazda|\\busf\\b|lotus (18|49|79)|williams fw|mercedes-amg w1|tatuus|\\bvee\\b|\\bfr ?[23]\\.", RegexOption.IGNORE_CASE)
    return if (formula.containsMatchIn(car)) "formula_car" else "sports_car"
}

/** One lap of a race; [cut]: the car left the track, the lap is not valid. */
data class RaceLap(val n: Int, val time: Double, val pos: Int, val inc: Int, val pit: Boolean, val cut: Boolean = false, val drv: String = "")

/** One driver of a race; [k]: their opaque key (the PC's driverKey), what your driver notes find them by. */
data class RaceResult(val pos: Int, val name: String, val ir: Int, val best: Double?, val inc: Int, val laps: Int, val k: String = "", val me: Boolean = false, val ai: Boolean = false)

/** Your note on another driver (drivers.json in the account): one tag (danger, careful, clean, friend) and a note. */
data class DriverNote(val name: String, val tag: String, val note: String)

/** Your notes on a track (notes.json in the account, the same the PC and the web write): a general note and one per
 *  corner (its number, where its braking zone starts and what you wrote). */
data class TrackNote(val trackId: Long, val track: String, val general: String, val corners: List<CornerNote>, val updated: String)
data class CornerNote(val n: Int, val dist: Double, val name: String, val note: String)

/** What a screen shows: [stale] is saved data shown while the server cannot be reached. */
data class Loadable<T>(val loading: Boolean = false, val data: T? = null, val error: String? = null, val stale: Boolean = false)

fun lapTime(s: Double?): String {
    if (s == null || s.isNaN() || s <= 0) return "—"
    val m = (s / 60).toInt()
    val r = s - m * 60
    return if (m > 0) "%d:%06.3f".format(m, r) else "%.3f".format(r)
}

fun signed(n: Int) = if (n > 0) "+$n" else "$n"
