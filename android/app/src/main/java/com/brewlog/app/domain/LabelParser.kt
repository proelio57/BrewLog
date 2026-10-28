package com.brewlog.app.domain

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit

/**
 * Reads bean details from the text on a coffee bag (recognized on the device with ML Kit, see LabelScanner).
 * English and German labels; everything found is only a suggestion the user reviews. Port of LabelParser.swift.
 */
object LabelParser {
    /** One recognized line. [height] and [top] are relative to the photo (0…1, top = 0). */
    data class Line(val text: String, val height: Double = 0.0, val top: Double = 0.0)

    data class Result(
        val name: String? = null,
        val roaster: String? = null,
        val origin: String? = null,
        val varietal: String? = null,
        val process: ProcessMethod? = null,
        val roastLevel: RoastLevel? = null,
        /** Epoch millis (noon of the day). */
        val roastDate: Long? = null,
        val bagWeight: Double? = null,
        val tastingNotes: String? = null,
    ) {
        val isEmpty: Boolean get() = this == Result()

        /** Names of the fields found, for "Found: origin, process, roast date". */
        val foundFields: List<String>
            get() = listOfNotNull(
                name?.let { "name" }, roaster?.let { "roaster" }, origin?.let { "origin" }, varietal?.let { "varietal" },
                process?.let { "process" }, roastLevel?.let { "roast level" }, roastDate?.let { "roast date" },
                bagWeight?.let { "bag weight" }, tastingNotes?.let { "tasting notes" },
            )
    }

    fun parse(input: List<Line>, now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): Result {
        val all = input.map { it.copy(text = it.text.trim()) }.filter { it.text.isNotEmpty() }.take(200)
        val used = mutableSetOf<Int>()
        var origin: String? = null
        var roaster: String? = null
        var name: String? = null
        var notes: String? = null

        // Origin: a known producing country, with the region when the line is short ("Guji, Ethiopia").
        for ((index, line) in all.withIndex()) {
            val country = country(line.text) ?: continue
            origin = if (line.text.length <= 40 && line.text.length > country.length) clean(line.text) else country
            used += index
            break
        }

        val joined = all.joinToString("\n") { it.text }
        for ((index, line) in all.withIndex()) {
            val found = tastingNotes(line.text, all.getOrNull(index + 1)?.text) ?: continue
            notes = found
            used += index
            break
        }

        // Roaster: a line that says so ("… Coffee Roasters", "Kaffeerösterei …").
        for ((index, line) in all.withIndex()) {
            if (index in used || !isRoasterLine(line.text)) continue
            roaster = clean(line.text)
            used += index
            break
        }

        // Name: the biggest remaining text that reads like a name (not a number, date, weight or keyword line).
        val candidates = all.withIndex().filter { it.index !in used && looksLikeName(it.value.text) }.sortedByDescending { it.value.height }
        candidates.firstOrNull()?.let { best ->
            name = clean(best.value.text)
            used += best.index
            // No roaster line: big text at the very top is usually the roaster's logo.
            if (roaster == null) {
                val top = candidates.drop(1).filter { it.value.top < best.value.top }.minByOrNull { it.value.top }
                if (top != null && top.value.height >= best.value.height * 0.5) roaster = clean(top.value.text)
            }
        }
        return Result(
            name = name, roaster = roaster, origin = origin, varietal = varietals(joined), process = process(joined),
            roastLevel = roastLevel(joined), roastDate = roastDate(all.map { it.text }, now, zone),
            bagWeight = bagWeight(joined), tastingNotes = notes,
        )
    }

    // MARK: Fields

    /** Producing countries (English, German, Spanish) → English name. */
    val countries: List<Pair<String, List<String>>> = listOf(
        "Ethiopia" to listOf("ethiopia", "äthiopien", "aethiopien", "etiopia"),
        "Kenya" to listOf("kenya", "kenia"),
        "Colombia" to listOf("colombia", "kolumbien"),
        "Brazil" to listOf("brazil", "brasil", "brasilien"),
        "Guatemala" to listOf("guatemala"),
        "Costa Rica" to listOf("costa rica"),
        "Panama" to listOf("panama", "panamá"),
        "Honduras" to listOf("honduras"),
        "El Salvador" to listOf("el salvador"),
        "Nicaragua" to listOf("nicaragua"),
        "Peru" to listOf("peru", "perú"),
        "Bolivia" to listOf("bolivia", "bolivien"),
        "Ecuador" to listOf("ecuador"),
        "Mexico" to listOf("mexico", "méxico", "mexiko"),
        "Rwanda" to listOf("rwanda", "ruanda"),
        "Burundi" to listOf("burundi"),
        "Uganda" to listOf("uganda"),
        "Tanzania" to listOf("tanzania", "tansania"),
        "DR Congo" to listOf("congo", "kongo"),
        "Malawi" to listOf("malawi"),
        "Zambia" to listOf("zambia", "sambia"),
        "Yemen" to listOf("yemen", "jemen"),
        "Indonesia" to listOf("indonesia", "indonesien", "sumatra", "java", "sulawesi", "bali", "flores"),
        "Papua New Guinea" to listOf("papua new guinea", "papua-neuguinea", "papua neuguinea"),
        "India" to listOf("india", "indien"),
        "China" to listOf("china", "yunnan"),
        "Vietnam" to listOf("vietnam"),
        "Thailand" to listOf("thailand"),
        "Myanmar" to listOf("myanmar"),
        "Jamaica" to listOf("jamaica", "jamaika"),
        "Hawaii" to listOf("hawaii", "kona"),
        "Taiwan" to listOf("taiwan"),
        "Dominican Republic" to listOf("dominican republic", "dominikanische republik"),
    )

    fun country(text: String): String? {
        val lower = text.lowercase()
        return countries.firstOrNull { (_, words) -> words.any { containsWord(lower, it) } }?.first
    }

    fun process(text: String): ProcessMethod? {
        val lower = text.lowercase()
        val rules = listOf(
            ProcessMethod.ANAEROBIC to listOf("anaerobic", "anaerob", "carbonic maceration", "kohlensäuremazeration"),
            ProcessMethod.HONEY to listOf("honey", "pulped natural", "red honey", "yellow honey", "black honey"),
            ProcessMethod.NATURAL to listOf("natural", "natur", "naturel", "dry process", "trocken aufbereitet", "sun-dried", "sun dried"),
            ProcessMethod.WASHED to listOf("washed", "gewaschen", "lavado", "wet process", "nass aufbereitet", "nassaufbereitet"),
        )
        return rules.firstOrNull { (_, words) -> words.any { containsWord(lower, it) } }?.first
    }

    val knownVarietals = listOf(
        "Geisha", "Gesha", "Pink Bourbon", "Red Bourbon", "Yellow Bourbon", "Bourbon", "SL28", "SL34", "Typica",
        "Caturra", "Catuai", "Catuaí", "Pacamara", "Maragogype", "Heirloom", "74110", "74112", "74158", "Castillo",
        "Sidra", "Wush Wush", "Mundo Novo", "Villa Sarchi", "Ruiru 11", "Batian", "Java", "Laurina", "Eugenioides",
        "Catimor", "Sarchimor", "Marsellesa", "Parainema", "Obata", "Tabi", "Colombia",
    )

    /** All varietals named, e.g. "Caturra, Castillo". Longer names win over their parts ("Pink Bourbon"). */
    fun varietals(text: String): String? {
        var lower = text.lowercase()
        val found = mutableListOf<String>()
        // Colombia and Java are also places: only count them after a "varietal" label.
        val ambiguous = setOf("Colombia", "Java")
        val varietyLine = text.split("\n", "\r").firstOrNull {
            val l = it.lowercase()
            l.contains("variet") || l.contains("sorte") || l.contains("cultivar")
        }?.lowercase()
        for (name in knownVarietals.sortedByDescending { it.length }) {
            val key = name.lowercase()
            if (name in ambiguous) {
                if (varietyLine == null || !containsWord(varietyLine, key)) continue
            } else if (!containsWord(lower, key)) {
                continue
            }
            val display = when (name) {
                "Gesha" -> "Geisha"
                "Catuaí" -> "Catuai"
                else -> name
            }
            if (display !in found) found += display
            lower = lower.replace(key, " ")
        }
        return if (found.isEmpty()) null else found.take(4).joinToString(", ")
    }

    fun roastLevel(text: String): RoastLevel? {
        val lower = text.lowercase()
        val rules = listOf(
            RoastLevel.MEDIUM_LIGHT to listOf("medium-light", "medium light", "light-medium", "light medium", "hell-mittel", "mittelhell"),
            RoastLevel.MEDIUM_DARK to listOf("medium-dark", "medium dark", "mitteldunkel", "mittel-dunkel"),
            RoastLevel.LIGHT to listOf("light roast", "filter roast", "nordic", "hell geröstet", "helle röstung", "filterröstung"),
            RoastLevel.DARK to listOf("dark roast", "dunkel geröstet", "dunkle röstung", "french roast", "italian roast"),
            RoastLevel.MEDIUM to listOf("medium roast", "mittlere röstung", "mittel geröstet"),
        )
        return rules.firstOrNull { (_, words) -> words.any { lower.contains(it) } }?.first
    }

    private val weightPattern = Regex("""(?<![\d.,])(\d{1,4}(?:[.,]\d{1,3})?)\s*(kg|g|gr|gramm|grams)\b""", RegexOption.IGNORE_CASE)

    /** The bag weight in grams, e.g. "250 g", "250g", "1 kg", "0,5 kg". */
    fun bagWeight(text: String): Double? {
        for (match in weightPattern.findAll(text)) {
            val number = match.groupValues[1].replace(',', '.').toDoubleOrNull() ?: continue
            val grams = if (match.groupValues[2].lowercase() == "kg") number * 1000 else number
            if (grams in 100.0..5000.0) return grams
        }
        return null
    }

    /** The roast date: preferably from a line that says "roasted", never from a best-before line. */
    fun roastDate(lines: List<String>, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Long? {
        val roastWords = listOf("roast", "röst", "geröstet", "roasted")
        val expiryWords = listOf("best before", "mhd", "mindestens haltbar", "haltbar bis", "exp", "bbe", "use by")
        var fallback: Long? = null
        for ((index, line) in lines.withIndex()) {
            val lower = line.lowercase()
            if (expiryWords.any { lower.contains(it) }) continue
            val isRoastLine = roastWords.any { lower.contains(it) }
            // The date can be on the line after the label ("Roast date" / "12.10.2026").
            val candidates = mutableListOf(line)
            if (isRoastLine && index + 1 < lines.size) candidates += lines[index + 1]
            for (text in candidates) {
                val date = date(text, now, zone) ?: continue
                if (isRoastLine) return date
                if (fallback == null) fallback = date
            }
        }
        return fallback
    }

    private val months = mapOf(
        "jan" to 1, "januar" to 1, "january" to 1, "jän" to 1, "feb" to 2, "februar" to 2, "february" to 2, "mar" to 3, "mär" to 3,
        "märz" to 3, "march" to 3, "maerz" to 3, "apr" to 4, "april" to 4, "may" to 5, "mai" to 5, "jun" to 6, "juni" to 6, "june" to 6,
        "jul" to 7, "juli" to 7, "july" to 7, "aug" to 8, "august" to 8, "sep" to 9, "sept" to 9, "september" to 9, "oct" to 10,
        "okt" to 10, "october" to 10, "oktober" to 10, "nov" to 11, "november" to 11, "dec" to 12, "dez" to 12, "december" to 12,
        "dezember" to 12,
    )

    private val isoDate = Regex("""(\d{4})-(\d{1,2})-(\d{1,2})""")
    private val numericDate = Regex("""(?<!\d)(\d{1,2})[./](\d{1,2})[./](\d{2,4})(?!\d)""")
    private val dayMonthName = Regex("""(?<!\d)(\d{1,2})\.?\s+([a-zäé]{3,9})\.?\s+(\d{4})""")
    private val monthNameDay = Regex("""([a-zäé]{3,9})\.?\s+(\d{1,2}),?\s+(\d{4})""")

    /** A plausible roast date in the text (epoch millis, noon): not in the future and at most a year old. */
    fun date(text: String, now: Instant, zone: ZoneId = ZoneId.systemDefault()): Long? {
        val lower = text.lowercase()
        val found = mutableListOf<Triple<Int, Int, Int>>() // day, month, year
        isoDate.findAll(lower).forEach { m ->
            val (y, mo, d) = m.destructured
            found += Triple(d.toInt(), mo.toInt(), y.toInt())
        }
        numericDate.findAll(lower).forEach { m ->
            val (d, mo, y) = m.destructured
            var year = y.toInt()
            if (year < 100) year += 2000
            found += Triple(d.toInt(), mo.toInt(), year)
        }
        dayMonthName.findAll(lower).forEach { m ->
            val (d, name, y) = m.destructured
            months[name]?.let { found += Triple(d.toInt(), it, y.toInt()) }
        }
        monthNameDay.findAll(lower).forEach { m ->
            val (name, d, y) = m.destructured
            months[name]?.let { found += Triple(d.toInt(), it, y.toInt()) }
        }
        val oldest = now.minus(365, ChronoUnit.DAYS)
        val latest = now.plus(1, ChronoUnit.DAYS)
        for ((day, month, year) in found) {
            if (month !in 1..12 || day !in 1..31) continue
            val local = runCatching { LocalDate.of(year, month, day) }.getOrNull() ?: continue
            val instant = local.atTime(12, 0).atZone(zone).toInstant()
            if (instant < oldest || instant > latest) continue
            return minOf(instant, now).toEpochMilli()
        }
        return null
    }

    /** "Tasting notes: peach, jasmine" or a label line followed by the notes. */
    fun tastingNotes(line: String, next: String?): String? {
        val labels = listOf("tasting notes", "cupping notes", "flavour notes", "flavor notes", "notes", "aromen", "aroma",
            "geschmack", "geschmacksnoten", "noten", "we taste", "wir schmecken", "taste")
        val lower = line.lowercase()
        val label = labels.firstOrNull { lower.startsWith(it) } ?: return null
        var rest = line.drop(label.length).trim(' ', ':', '–', '-', '|')
        if (rest.isEmpty() && next != null) rest = next
        rest = clean(rest)
        return if (rest.length >= 3) rest.take(InputLimits.MAX_SHORT_TEXT) else null
    }

    fun isRoasterLine(text: String): Boolean {
        val lower = text.lowercase()
        return listOf("roasters", "roastery", "roasting co", "rösterei", "roesterei", "kaffeerösterei", "coffee roasting",
            "torrefaction", "tostadores").any { lower.contains(it) }
    }

    fun looksLikeName(text: String): Boolean {
        val letters = text.count { it.isLetter() }
        if (letters < 3 || text.length > 50) return false
        // Mostly letters, not a date, weight or a details line.
        if (text.count { it.isDigit() } > letters / 2) return false
        val lower = text.lowercase()
        val details = listOf("process", "aufbereitung", "variet", "sorte", "altitude", "höhe", "masl", "m.ü.", "roast",
            "röst", "net", "netto", "best before", "mhd", "www.", "http", "@", ".com", ".de",
            "notes", "aromen", "geschmack", "producer", "farm:", "region:", "origin:", "herkunft:")
        return details.none { lower.contains(it) } && bagWeight(text) == null
    }

    // MARK: Helpers

    private fun containsWord(text: String, word: String): Boolean {
        var from = 0
        while (true) {
            val start = text.indexOf(word, from)
            if (start < 0) return false
            val end = start + word.length
            val before = text.getOrNull(start - 1)
            val after = text.getOrNull(end)
            if (before?.isLetter() != true && after?.isLetter() != true) return true
            from = end
        }
    }

    private fun clean(text: String) = text.trim(' ', ':', '–', '-', '|', '•', '·', ',').sanitized(InputLimits.MAX_NAME_LENGTH)
}
