package com.brewlog.app.domain

/** The journal's filter chips: Filter or Espresso, brews still to review, one bean, one recipe (same as iOS). */
data class JournalFilter(
    val kind: Kind = Kind.ALL,
    val toReview: Boolean = false,
    /** A bean's display name ("Name · Roaster"); null = any. */
    val bean: String? = null,
    val recipe: String? = null,
) {
    enum class Kind(val title: String) { ALL("All"), FILTER("Filter"), ESPRESSO("Espresso") }

    val isActive: Boolean get() = kind != Kind.ALL || toReview || bean != null || recipe != null

    fun matches(isEspresso: Boolean, isReviewed: Boolean, bean: String?, recipe: String): Boolean {
        if (kind == Kind.FILTER && isEspresso) return false
        if (kind == Kind.ESPRESSO && !isEspresso) return false
        if (toReview && isReviewed) return false
        if (this.bean != null && this.bean != bean) return false
        if (this.recipe != null && this.recipe != recipe) return false
        return true
    }

    companion object {
        /** The distinct non-empty names, most frequent first (ties alphabetical), for the bean and recipe menus. */
        fun options(names: List<String?>): List<String> =
            names.filterNotNull().filter { it.isNotEmpty() }.groupingBy { it }.eachCount()
                .entries.sortedWith(compareByDescending<Map.Entry<String, Int>> { it.value }.thenBy { it.key })
                .map { it.key }
    }
}
