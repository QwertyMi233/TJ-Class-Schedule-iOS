package com.offlinecourse.offline_course_schedule

import kotlin.math.atan2
import kotlin.math.exp
import kotlin.math.hypot

/** Android 的旋转矩阵把设备坐标映射到东、北、上。 */
object HeadingMath {
    fun fromMatrix(matrix: FloatArray): Double? {
        if (matrix.size != 9 || matrix.any { !it.isFinite() }) return null
        // 平放使用顶部 +Y；竖握使用背面 -Z，渐变避免改变握姿时跳向。
        val blend = ((matrix[7].toDouble() - .4) / .5).coerceIn(0.0, 1.0)
        val east = (1 - blend) * matrix[1] - blend * matrix[2]
        val north = (1 - blend) * matrix[4] - blend * matrix[5]
        if (hypot(east, north) < .25 || matrix[7] < -.8) return null
        return normalize(Math.toDegrees(atan2(east, north)))
    }
    fun normalize(angle: Double) = (angle % 360 + 360) % 360
}

class CircularHeadingFilter {
    private var previous: Double? = null
    private var previousTime = 0L
    fun reset() { previous = null; previousTime = 0 }
    fun update(heading: Double, now: Long): Double {
        val old = previous
        val result = if (old == null) HeadingMath.normalize(heading) else {
            val delta = (heading - old + 540) % 360 - 180
            val seconds = ((now - previousTime) / 1000.0).coerceIn(0.0, .2)
            HeadingMath.normalize(old + delta * (1 - exp(-seconds / .08)))
        }
        previous = result
        previousTime = now
        return result
    }
}
