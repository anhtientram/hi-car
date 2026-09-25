package com.hicar.ora.limited

import android.app.ActivityManager
import android.app.Application
import android.os.Build

/** Native diagnostics must exist even when Flutter never starts. */
class HiCarApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        HiCarDiagnosticLog.init(this)
        HiCarDiagnosticLog.markBootSession()
        val previous = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { thread, error ->
            try {
                HiCarDiagnosticLog.e("HiCar", "UNCAUGHT thread=${thread.name} ${error.stackTraceToString()}")
                HiCarDiagnosticLog.flush()
            } finally {
                previous?.uncaughtException(thread, error)
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                val storage = createDeviceProtectedStorageContext()
                val prefs = storage.getSharedPreferences("HiCarExitInfo", MODE_PRIVATE)
                val since = prefs.getLong("last_exit", 0L)
                val manager = getSystemService(ACTIVITY_SERVICE) as ActivityManager
                val exits = manager.getHistoricalProcessExitReasons(packageName, 0, 5)
                    .filter { it.timestamp > since }
                exits.sortedBy { it.timestamp }.forEach {
                    HiCarDiagnosticLog.w("HiCar", "PREVIOUS_PROCESS_EXIT reason=${it.reason} status=${it.status} importance=${it.importance} pid=${it.pid} time=${it.timestamp} description=${it.description}")
                }
                exits.maxOfOrNull { it.timestamp }?.let { prefs.edit().putLong("last_exit", it).apply() }
            } catch (e: Exception) {
                HiCarDiagnosticLog.w("HiCar", "ExitInfo unavailable: ${e.message}")
            }
        }
    }
}
