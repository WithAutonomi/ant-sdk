package com.autonomi.examples

import kotlinx.coroutines.runBlocking
import org.junit.jupiter.api.Assumptions.assumeTrue
import java.io.ByteArrayOutputStream
import java.io.PrintStream
import kotlin.test.Test
import kotlin.test.assertTrue

/**
 * The pointers example pays for every write, so without an owner it must stop
 * before it touches a daemon (none runs here), with a one-line note.
 */
class Example08PointersTest {

    @Test
    fun skipsWithoutAnOwner() = runBlocking {
        assumeTrue(System.getenv("ANTD_POINTER_OWNER").isNullOrBlank(), "ANTD_POINTER_OWNER is set")
        val out = ByteArrayOutputStream()
        val saved = System.out
        System.setOut(PrintStream(out, true))
        try {
            example08Pointers()
        } finally {
            System.setOut(saved)
        }
        assertTrue(out.toString().contains("Skipped: set ANTD_POINTER_OWNER"), out.toString())
    }
}
