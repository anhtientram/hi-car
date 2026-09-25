package com.hicar.ora.limited

/** Pure policy: one job owns all retries; old callbacks never own a newer attempt. */
class PlaybackJob(
    val id: String,
    val mode: String,
    val path: String,
    val type: String,
    val automatic: Boolean,
    val bootSession: Long = -1L,
    val target: String = ""
) {
    var state = "waiting_focus"
    var attempt = 0
        private set
    var positionMs = 0
    var durationMs = 0
    var retries = 0
    var cancelled = false
        private set

    fun beginAttempt(): Int { attempt++; state = "preparing"; return attempt }
    fun owns(callbackAttempt: Int) = !cancelled &&
        state !in setOf("completed", "failed") && attempt == callbackAttempt
    fun cancel() { cancelled = true; state = "cancelled" }

    fun valid(modeNow: String, autoEnabled: Boolean, authenticated: Boolean, targetNow: String) =
        !cancelled && mode == modeNow && authenticated &&
            (!automatic || autoEnabled) &&
            (mode != "phone_bluetooth" || !automatic || target.equals(targetNow, true))

    /** Route/focus waiting has no budget. Only actual failed player instances consume retries. */
    fun retryDelay(what: Int, extra: Int): Long? {
        if (cancelled || !recoverable(what, extra) || retries >= 2) return null
        retries++
        state = "retrying"
        return if (retries == 1) 2500L else 7500L
    }

    companion object {
        fun recoverable(what: Int, extra: Int) =
            what == 100 || (what == 1 && extra in setOf(-32, -38, -110))
    }
}
