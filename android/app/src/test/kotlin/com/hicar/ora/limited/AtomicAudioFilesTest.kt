package com.hicar.ora.limited

import java.io.File
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AtomicAudioFilesTest {
    @get:Rule val folder = TemporaryFolder()
    private fun audio(name: String, value: Byte): File = folder.newFile(name).apply {
        writeBytes(ByteArray(256) { value }.also { it[0] = 73; it[1] = 68; it[2] = 51 })
    }

    @Test fun sameSizeChangedAudioReallyUpdates() {
        val old = audio("boot.mp3", 1)
        val new = audio("new.mp3", 2)
        assertTrue(AtomicAudioFiles.replace(new, old))
        assertArrayEquals(new.readBytes(), old.readBytes())
        assertFalse(AtomicAudioFiles.replace(new, old))
    }

    @Test fun invalidDownloadCannotEraseLastGoodAudio() {
        val good = audio("boot.mp3", 1)
        val expected = good.readBytes()
        val bad = folder.newFile("bad.mp3").apply { writeText("<html>Server error</html>") }
        try { AtomicAudioFiles.replace(bad, good); fail("Expected rejection") }
        catch (_: java.io.IOException) {}
        assertArrayEquals(expected, good.readBytes())
        assertFalse(folder.root.listFiles()!!.any { it.name.endsWith(".part") })
    }

    @Test fun activeDecoderFileDescriptorKeepsOldBytesDuringSync() {
        val target = audio("boot.mp3", 1)
        val expected = target.readBytes()
        val new = audio("new.mp3", 2)
        target.inputStream().use { decoder ->
            AtomicAudioFiles.replace(new, target)
            assertArrayEquals(expected, decoder.readBytes())
        }
        assertArrayEquals(new.readBytes(), target.readBytes())
    }

    @Test fun copyingAFileOntoItselfDoesNotDestroyIt() {
        val source = audio("source.mp3", 3)
        assertFalse(AtomicAudioFiles.replace(source, source))
        assertTrue(AudioFileValidator.isUsable(source))
    }
}
