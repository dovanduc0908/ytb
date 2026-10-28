package com.duchaik.ytb

import android.content.Context

/** Finite videos at or beyond 95%, shared by foreground and background playback. */
object WatchedCompletion {
    private const val PREFS = "watched-completion"
    private const val KEY = "ids"
    fun ids(context: Context): Set<String> = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        .getStringSet(KEY, emptySet())?.toSet() ?: emptySet()
    @Synchronized fun add(context: Context, id: String): Boolean {
        if (!Regex("^[A-Za-z0-9_-]{11}$").matches(id)) return false
        val all = ids(context).toMutableSet()
        if (!all.add(id)) return false
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putStringSet(KEY, all).apply()
        return true
    }
    @Synchronized fun clear(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
    }
}
