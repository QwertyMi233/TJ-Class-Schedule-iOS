package com.offlinecourse.offline_course_schedule

import org.junit.Assert.*
import org.junit.Test
import kotlin.math.cos
import kotlin.math.sin

class HeadingMathTest {
    private fun matrix(heading: Double, pitch: Double): FloatArray {
        val h = Math.toRadians(heading); val p = Math.toRadians(pitch)
        return floatArrayOf(cos(h).toFloat(), (sin(h)*cos(p)).toFloat(), (-sin(h)*sin(p)).toFloat(),
            -sin(h).toFloat(), (cos(h)*cos(p)).toFloat(), (-cos(h)*sin(p)).toFloat(),
            0f, sin(p).toFloat(), cos(p).toFloat())
    }
    @Test fun headingIsStableAcrossNormalGripAngles() {
        for (heading in listOf(0.0, 90.0, 180.0, 270.0, 359.0)) {
            for (pitch in 0..90 step 5) assertEquals(heading, HeadingMath.fromMatrix(matrix(heading, pitch.toDouble()))!!, .0001)
        }
    }
    @Test fun ambiguousAndInvalidPosesAreRejected() {
        assertNull(HeadingMath.fromMatrix(matrix(0.0, -90.0)))
        assertNull(HeadingMath.fromMatrix(FloatArray(9)))
        assertNull(HeadingMath.fromMatrix(FloatArray(9) { Float.NaN }))
    }
    @Test fun smoothingCrossesNorthByShortestPath() {
        val filter = CircularHeadingFilter()
        assertEquals(359.0, filter.update(359.0, 1000), .001)
        val next = filter.update(1.0, 1033)
        assertTrue(next > 359 || next < 1)
        assertEquals(90.0, filter.apply { reset() }.update(90.0, 1040), .001)
    }
    @Test fun smoothingConvergesWithoutAccumulatingDrift() {
        val filter = CircularHeadingFilter()
        filter.update(0.0, 1000)
        var result = 0.0
        for (tick in 1..40) result = filter.update(90.0, 1000 + 33L*tick)
        assertEquals(90.0, result, .001)
    }
}
