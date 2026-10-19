package ca.jettatelemetry.app.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DerivedSignalsTest {
    @Test fun gaugeBoostSubtractsLiveBarometricPressure() {
        assertEquals(2.0, DerivedSignals.gaugeBoostKpa(100.0, 98.0)!!, 0.001)
        assertEquals(-8.0, DerivedSignals.gaugeBoostKpa(90.0, 98.0)!!, 0.001)
    }

    @Test fun gaugeBoostRequiresBothInputs() {
        assertNull(DerivedSignals.gaugeBoostKpa(100.0, null))
        assertNull(DerivedSignals.gaugeBoostKpa(null, 98.0))
    }
}

