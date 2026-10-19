package ca.jettatelemetry.app.obd

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class JettaDiagnosticDiscoveryTest {
    @Test
    fun discoveryPackIsUniqueAndReadOnly() {
        val probes = JettaDiagnosticDiscovery.probes

        assertTrue(probes.isNotEmpty())
        assertEquals(probes.size, probes.map { it.id }.distinct().size)
        assertEquals(probes.size, probes.map { it.did }.distinct().size)
        assertTrue(probes.all { it.command.startsWith("22") })
        assertEquals("7E0", JettaDiagnosticDiscovery.REQUEST_HEADER)
        assertEquals("7E8", JettaDiagnosticDiscovery.RESPONSE_HEADER)
    }
}
