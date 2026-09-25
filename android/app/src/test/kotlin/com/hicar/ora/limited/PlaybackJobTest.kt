package com.hicar.ora.limited

import org.junit.Assert.*
import org.junit.Test

class PlaybackJobTest {
    private val modes = listOf("phone_bluetooth", "phone_android_auto", "android_screen_mode", "android_box_mode")
    private fun job(mode: String = "android_screen_mode", auto: Boolean = true) =
        PlaybackJob("test", mode, "/test.mp3", "greeting", auto, target = "AA:BB:CC:DD:EE:FF")

    @Test fun everyAndroidModeRecoversBothReportedNativeErrors() {
        for (mode in modes) {
            for ((what, extra) in listOf(100 to 2, 1 to -32, 1 to -38, 1 to -110)) {
                val job = job(mode)
                job.beginAttempt()
                job.positionMs = 5000
                assertEquals(2500L, job.retryDelay(what, extra))
                assertEquals("retrying", job.state)
                assertEquals(5000, job.positionMs)
                job.beginAttempt()
                assertEquals(7500L, job.retryDelay(what, extra))
                job.beginAttempt()
                assertNull(job.retryDelay(what, extra))
            }
        }
    }

    @Test fun waitingForRouteDoesNotConsumeErrorBudgetEvenOvernight() {
        for (mode in modes) {
            val job = job(mode)
            repeat(34560) { // 24 h of 2.5 s readiness checks
                job.state = if (it % 2 == 0) "waiting_focus" else "waiting_route"
                assertTrue(job.valid(mode, true, true, job.target))
            }
            assertEquals(0, job.retries)
            assertEquals(2500L, job.retryDelay(100, 2))
        }
    }

    @Test fun previousAttemptCannotFinishOrMutateReplacement() {
        val job = job()
        val old = job.beginAttempt()
        job.retryDelay(100, 2)
        val current = job.beginAttempt()
        assertFalse(job.owns(old))
        assertTrue(job.owns(current))
        job.state = "completed"
        assertFalse(job.owns(current))
    }

    @Test fun stopInvalidatesQueuedCallbacksAndRetry() {
        val job = job()
        val attempt = job.beginAttempt()
        job.cancel()
        assertFalse(job.owns(attempt))
        assertNull(job.retryDelay(100, 2))
    }

    @Test fun modeLogoutAndAutoOffCancelEveryAutomaticMode() {
        for (mode in modes) {
            val job = job(mode)
            assertFalse(job.valid("another_mode", true, true, job.target))
            assertFalse(job.valid(mode, true, false, job.target))
            assertFalse(job.valid(mode, false, true, job.target))
            assertTrue(job.valid(mode, true, true, job.target))
        }
    }

    @Test fun manualPlayStillAllowedWithAutoDisabled() {
        for (mode in modes) assertTrue(job(mode, false).valid(mode, false, true, ""))
    }

    @Test fun bluetoothTargetCannotBeSubstitutedByAnotherDevice() {
        val job = job("phone_bluetooth")
        assertFalse(job.valid(job.mode, true, true, "other-headset"))
        assertTrue(job.valid(job.mode, true, true, job.target.lowercase()))
    }

    @Test fun corruptUnsupportedFileIsNotRetriedAsDeadAudioServer() {
        assertNull(job().retryDelay(1, -1004))
        assertNull(job().retryDelay(1, -1010))
    }
}
