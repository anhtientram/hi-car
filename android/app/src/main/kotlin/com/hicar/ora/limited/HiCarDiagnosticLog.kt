package com.hicar.ora.limited

import android.content.Context
import android.os.Build
import android.os.Process
import android.util.Log
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.Executors

/**
 * In-app diagnostic log with adb/logcat-style lines (HiCar tags only).
 *
 * Mục tiêu: là CÔNG CỤ TRUY VẾT XUNG ĐỘT đáng tin cậy ở bản RELEASE.
 * - Ghi song song ra logcat (Log.d/w/e) + file persist.
 * - File nằm trong device-protected storage → sống sót qua boot/Direct Boot (đọc được trước khi
 *   user unlock), phục vụ debug case Android Box tắt xe qua đêm.
 * - I/O đẩy sang 1 thread nền riêng để KHÔNG chặn main thread / luồng boot (box chậm).
 * - File trên disk được trim định kỳ để không phình vô hạn.
 */
object HiCarDiagnosticLog {

    private val ALLOWED_TAGS = setOf(
        "HiCarBoot",
        "HiCarService",
        "HiCarAudio",
        "HiCarAA",
        "HiCarBT",
        "HiCarSync",
        "HiCarPlugin",
        "HiCar",
        "OverlayBridge"
    )

    // Số dòng giữ trong RAM (preview nhanh) và trần file trên disk.
    private const val MAX_LINES = 200
    private const val MAX_DISK_LINES = 1000
    private const val FILE_NAME = "hicar_diagnostic.log"

    private val buffer = CopyOnWriteArrayList<String>()
    private val timeFormat = SimpleDateFormat("MM-dd HH:mm:ss.SSS", Locale.US)

    // Mọi thao tác I/O (append/trim/load/clear) chạy tuần tự trên 1 thread nền duy nhất
    // để vừa thread-safe vừa không chặn caller (đặc biệt luồng boot trên box yếu).
    private val ioExecutor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "HiCarDiagLog").apply { isDaemon = true }
    }

    @Volatile private var storageContext: Context? = null
    @Volatile private var diskLineCount = 0

    fun init(context: Context) {
        if (storageContext != null) return
        synchronized(this) {
            if (storageContext != null) return
            val ctx = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                context.applicationContext.createDeviceProtectedStorageContext()
            } else {
                context.applicationContext
            }
            storageContext = ctx
            loadFromDisk(ctx)
        }
    }

    fun markBootSession() {
        appendRaw("----- session ${timeFormat.format(Date())} (pid=${Process.myPid()}) -----")
    }

    fun d(tag: String, message: String) = write("D", tag, message)

    fun w(tag: String, message: String) = write("W", tag, message)

    fun e(tag: String, message: String) = write("E", tag, message)

    fun hasErrorLines(context: Context? = null): Boolean =
        getFilteredErrorLines(context).isNotEmpty()

    fun getFullLog(): String {
        if (buffer.isEmpty()) return ""
        return buffer.joinToString("\n")
    }

    /** E/W lines plus a few surrounding D lines for context. */
    fun getErrorLog(context: Context? = null): String {
        val lines = getFilteredErrorLines(context)
        if (lines.isEmpty()) return ""
        val include = BooleanArray(lines.size)
        for (i in lines.indices) {
            if (isErrorLine(lines[i])) {
                for (j in maxOf(0, i - 2)..minOf(lines.lastIndex, i + 2)) {
                    include[j] = true
                }
            }
        }
        return lines.indices.filter { include[it] }.joinToString("\n") { lines[it] }
    }

    private fun getFilteredErrorLines(context: Context?): List<String> {
        if (buffer.isEmpty()) return emptyList()
        val lines = buffer.toList()
        if (context == null || !BootSessionManager.shouldSuppressBootWarnings(context)) {
            return lines
        }
        return lines.filterNot { isStaleBoxBootWarning(it) }
    }

    /** Cảnh báo poll/best-effort boot — oan sau khi box đã phát được. */
    private fun isStaleBoxBootWarning(line: String): Boolean {
        if (!line.contains(" W HiCarService")) return false
        return line.contains("Boot watch: timeout") ||
            line.contains("phát best-effort (alarm retry") ||
            line.contains("Box boot greeting phát best-effort") ||
            line.contains("Box boot best-effort (session=")
    }

    fun clear() {
        buffer.clear()
        val ctx = storageContext ?: return
        ioExecutor.execute {
            try {
                File(ctx.filesDir, FILE_NAME).delete()
                diskLineCount = 0
            } catch (_: Exception) {
            }
        }
    }

    private fun write(level: String, tag: String, message: String) {
        if (tag !in ALLOWED_TAGS) return
        when (level) {
            "D" -> Log.d(tag, message)
            "W" -> Log.w(tag, message)
            "E" -> Log.e(tag, message)
        }
        appendRaw(formatLine(level, tag, message))
    }

    private fun appendRaw(line: String) {
        // CopyOnWriteArrayList an toàn cho add/removeAt giữa các thread.
        buffer.add(line)
        while (buffer.size > MAX_LINES) {
            try {
                buffer.removeAt(0)
            } catch (_: IndexOutOfBoundsException) {
                break
            }
        }
        persistLine(line)
    }

    private fun formatLine(level: String, tag: String, message: String): String {
        val ts = timeFormat.format(Date())
        val pid = Process.myPid()
        val tid = Process.myTid()
        return "$ts  $pid  $tid $level $tag: $message"
    }

    private fun isErrorLine(line: String): Boolean {
        return line.contains(" E HiCar") || line.contains(" W HiCar")
    }

    private fun loadFromDisk(context: Context) {
        try {
            val file = File(context.filesDir, FILE_NAME)
            if (!file.exists()) return
            val lines = file.readLines()
            buffer.clear()
            lines.takeLast(MAX_LINES).forEach { buffer.add(it) }
            diskLineCount = lines.size
        } catch (_: Exception) {
        }
    }

    private fun persistLine(line: String) {
        val ctx = storageContext ?: return
        ioExecutor.execute {
            try {
                val file = File(ctx.filesDir, FILE_NAME)
                file.appendText("$line\n")
                diskLineCount++
                if (diskLineCount > MAX_DISK_LINES) {
                    trimDiskFile(file)
                }
            } catch (_: Exception) {
            }
        }
    }

    /** Rút gọn file trên disk về MAX_LINES dòng gần nhất (gọi trên ioExecutor). */
    private fun trimDiskFile(file: File) {
        try {
            val kept = file.readLines().takeLast(MAX_LINES)
            file.writeText(kept.joinToString("\n", postfix = "\n"))
            diskLineCount = kept.size
        } catch (_: Exception) {
        }
    }
}
