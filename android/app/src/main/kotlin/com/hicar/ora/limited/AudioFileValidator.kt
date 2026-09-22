package com.hicar.ora.limited

import java.io.File
import java.io.FileInputStream

/** Minimal, codec-agnostic validation shared by boot, overlay and native playback. */
object AudioFileValidator {
    private const val MIN_BYTES = 128L

    fun isUsable(file: File): Boolean {
        if (!file.exists() || file.length() < MIN_BYTES) return false
        return try {
            FileInputStream(file).use { input ->
                val header = ByteArray(12)
                val read = input.read(header)
                if (read < 4) return false
                val ascii = String(header, Charsets.US_ASCII)
                val isId3 = ascii.startsWith("ID3")
                val isRiff = ascii.startsWith("RIFF") && ascii.contains("WAVE")
                val isFlac = ascii.startsWith("fLaC")
                val isOgg = ascii.startsWith("OggS")
                val isMp4 = ascii.substring(4, minOf(read, 12)).contains("ftyp")
                val first = header[0].toInt() and 0xFF
                val second = header[1].toInt() and 0xFF
                val isMp3Frame = first == 0xFF && (second and 0xE0) == 0xE0
                isId3 || isRiff || isFlac || isOgg || isMp4 || isMp3Frame
            }
        } catch (_: Exception) {
            false
        }
    }
}
