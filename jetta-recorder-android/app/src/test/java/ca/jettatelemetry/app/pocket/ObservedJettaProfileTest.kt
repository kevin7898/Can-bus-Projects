package ca.jettatelemetry.app.pocket

import org.junit.Assert.*
import org.junit.Test

class ObservedJettaProfileTest {
    private fun value(pid: String, reply: String, id: String) = ObservedJettaProfile.decode(pid, reply).single { it.id == id }.value
    @Test fun `recorded speed and fuel rate replies decode without copying transmission data`() {
        assertEquals(78.0, value("0D", "7E803410D4E\r7E903410D00", "speed"), 0.001)
        assertEquals(7.35, value("5E", "7E804415E0093", "fuel_rate"), 0.001)
        assertEquals(1830.0, value("0C", "7E804410C1C98", "rpm"), 0.001)
        assertEquals(79.0, value("05", "7E803410577", "coolant"), 0.001)
    }
    @Test fun `extended boost requires complete ISO TP and ignores padding`() {
        val reply = "7E8100C417003145313\r7E821B6000000000000"
        assertEquals(0x13B6 / 32.0, value("70", reply, "boost_absolute"), 0.001)
        assertEquals(0x1453 / 32.0, value("70", reply, "boost_commanded_absolute"), 0.001)
    }
    @Test fun `incomplete out of order and other ECU multi frame replies are rejected`() {
        assertTrue(ObservedJettaProfile.decode("70", "7E8100C417003145313").isEmpty())
        assertTrue(ObservedJettaProfile.decode("70", "7E8100C417003145313\r7E822B6000000000000").isEmpty())
        assertTrue(ObservedJettaProfile.decode("70", "7E9100C417003145313\r7E921B6000000000000").isEmpty())
        assertTrue(ObservedJettaProfile.decode("05", "NO DATA\r?").isEmpty())
    }
    @Test fun `DPF standard trigger is distinct from soot percent and respects support flags`() {
        val values = ObservedJettaProfile.decode("8B", "7E81009418B5F03FF00\r7E82100001900000000")
        assertEquals(100.0, values.single { it.id == "dpf_regen_trigger" }.value, 0.001)
        assertEquals(1.0, values.single { it.id == "dpf_regen_active" }.value, 0.001)
        assertEquals(25.0, values.single { it.id == "dpf_average_regen_distance" }.value, 0.001)
        assertFalse(values.any { "soot" in it.id })
        assertFalse(values.any { it.id == "dpf_average_regen_time" })
    }
    @Test fun `DPF pressure supports negative signed values`() {
        assertEquals(-0.01, value("7A", "7E81009417A01FFFF00\r7E82100000000000000", "dpf_delta_pressure"), 0.001)
        assertEquals(2.2, value("7A", "7E81009417A0100DC00\r7E82100000000000000", "dpf_delta_pressure"), 0.001)
    }
    @Test fun `exhaust temperature sensors retain their separate identities`() {
        val values = ObservedJettaProfile.decode("78", "7E8100B41780F17AC10\r7E8214C0EBE0C660000")
        assertEquals(4, values.size)
        assertEquals(566.0, values.single { it.id == "egt_1" }.value, 0.001)
        assertEquals(277.4, values.single { it.id == "egt_4" }.value, 0.001)
    }
    @Test fun `unsupported legacy MAP and unverified manufacturer reads are absent from poll plan`() {
        assertFalse(ObservedJettaProfile.polls.any { it.pid == "0B" })
        assertTrue(ObservedJettaProfile.polls.all { it.pid.matches(Regex("[0-9A-F]{2}")) })
    }
}
