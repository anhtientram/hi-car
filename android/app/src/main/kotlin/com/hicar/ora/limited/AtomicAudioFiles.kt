package com.hicar.ora.limited

import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.security.MessageDigest

/** POSIX same-directory rename keeps the old inode alive for an already-playing decoder. */
object AtomicAudioFiles {
    private fun digest(file: File): ByteArray = file.inputStream().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val bytes = ByteArray(8192)
        while (true) {
            val n = input.read(bytes)
            if (n < 0) break
            digest.update(bytes, 0, n)
        }
        digest.digest()
    }

    @Synchronized fun replace(source: File, destination: File): Boolean {
        if (!AudioFileValidator.isUsable(source)) throw IOException("FILE_INVALID source=${source.path}")
        if (source.canonicalPath == destination.canonicalPath) return false
        val expected = digest(source)
        if (AudioFileValidator.isUsable(destination) && expected.contentEquals(digest(destination))) return false
        destination.parentFile?.mkdirs()
        val stage = File.createTempFile(destination.name, ".part", destination.parentFile)
        try {
            source.inputStream().use { input ->
                FileOutputStream(stage).use { output -> input.copyTo(output); output.fd.sync() }
            }
            if (!AudioFileValidator.isUsable(stage) || !expected.contentEquals(digest(stage))) {
                throw IOException("FILE_INVALID copied content changed")
            }
            // Never delete destination first: failure must retain last-known-good audio.
            if (!stage.renameTo(destination)) throw IOException("Atomic rename failed: ${destination.path}")
            return true
        } finally {
            stage.delete()
        }
    }
}
