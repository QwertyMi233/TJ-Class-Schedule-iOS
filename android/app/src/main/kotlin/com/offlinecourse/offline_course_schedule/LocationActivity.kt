package com.offlinecourse.offline_course_schedule

import android.Manifest
import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.hardware.GeomagneticField
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.net.Uri
import android.os.Bundle
import android.os.SystemClock
import android.provider.Settings
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

open class LocationActivity : FlutterActivity(), SensorEventListener, LocationListener {
    private val locations by lazy { getSystemService(LOCATION_SERVICE) as LocationManager }
    private val sensors by lazy { getSystemService(SENSOR_SERVICE) as SensorManager }
    private var sink: EventChannel.EventSink? = null
    private var wanted = false
    private var foreground = false
    private var running = false
    private var asking = false
    private var best: Location? = null
    private var rotation: Sensor? = null
    private var accel: FloatArray? = null
    private var magnetic: FloatArray? = null
    private var magneticAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
    private var lastHeading = 0L
    private val headingFilter = CircularHeadingFilter()

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        EventChannel(engine.dartExecutor.binaryMessenger, "offline_course_schedule/location_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    sink = events
                    if (wanted && foreground) begin(false)
                }
                override fun onCancel(arguments: Any?) {
                    sink = null
                    wanted = false
                    releaseHardware()
                }
            })
        MethodChannel(engine.dartExecutor.binaryMessenger, "offline_course_schedule/location").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    wanted = true
                    begin(call.argument<Boolean>("requestPermission") == true)
                    result.success(null)
                }
                "stop" -> { wanted = false; releaseHardware(); result.success(null) }
                "appSettings", "locationSettings" -> {
                    try {
                        val intent = if (call.method == "locationSettings") Intent(Settings.ACTION_LOCATION_SOURCE_SETTINGS)
                            else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        startActivity(intent)
                        result.success(null)
                    } catch (_: Exception) { result.error("settings", "无法打开系统设置", null) }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun allowed(permission: String) = checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED
    private fun status(value: String) { sink?.success(mapOf("type" to "status", "status" to value)) }

    @SuppressLint("MissingPermission")
    private fun begin(request: Boolean) {
        if (!wanted || !foreground || asking) return
        releaseHardware()
        if (!allowed(Manifest.permission.ACCESS_COARSE_LOCATION) && !allowed(Manifest.permission.ACCESS_FINE_LOCATION)) {
            if (request) {
                asking = true
                requestPermissions(arrayOf(Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION), 41)
            } else {
                val asked = getPreferences(MODE_PRIVATE).getBoolean("asked", false)
                status(if (asked && !shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION)) "deniedForever" else "denied")
            }
            return
        }
        try {
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER).filter {
                locations.allProviders.contains(it) && locations.isProviderEnabled(it) &&
                    (it != LocationManager.GPS_PROVIDER || allowed(Manifest.permission.ACCESS_FINE_LOCATION))
            }
            if (providers.isEmpty()) { status("disabled"); return }
            status("waiting")
            running = true
            // 不读 lastKnownLocation，保存和导航只接受本次会话中的新鲜定位。
            providers.forEach { locations.requestLocationUpdates(it, 1000L, 0f, this) }
            rotation = sensors.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
                ?: sensors.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)
            if (rotation != null) {
                sensors.registerListener(this, rotation, SensorManager.SENSOR_DELAY_GAME)
            } else {
                val a = sensors.getDefaultSensor(Sensor.TYPE_ACCELEROMETER)
                val m = sensors.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
                if (a != null && m != null) {
                    sensors.registerListener(this, a, SensorManager.SENSOR_DELAY_GAME)
                    sensors.registerListener(this, m, SensorManager.SENSOR_DELAY_GAME)
                } else { sink?.success(mapOf("type" to "heading", "heading" to null, "reliable" to false)) }
            }
        } catch (_: SecurityException) { releaseHardware(); status("denied") }
        catch (_: Exception) { releaseHardware(); status("error") }
    }

    private fun releaseHardware() {
        locations.removeUpdates(this)
        sensors.unregisterListener(this)
        running = false
        best = null
        accel = null
        magnetic = null
        magneticAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE
        lastHeading = 0
        headingFilter.reset()
    }

    override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray) {
        super.onRequestPermissionsResult(code, permissions, results)
        if (code != 41 || !asking) return
        asking = false
        getPreferences(MODE_PRIVATE).edit().putBoolean("asked", true).apply()
        if (wanted && foreground) begin(false)
    }
    override fun onResume() {
        super.onResume()
        foreground = true
        if (wanted) begin(false)
    }
    override fun onPause() {
        foreground = false
        releaseHardware()
        super.onPause()
    }
    override fun onDestroy() { wanted = false; releaseHardware(); sink = null; super.onDestroy() }

    override fun onLocationChanged(location: Location) {
        if (!running || !foreground || !wanted || !location.hasAccuracy() ||
            !location.latitude.isFinite() || !location.longitude.isFinite() ||
            !location.accuracy.isFinite() || location.accuracy < 0) return
        val age = (SystemClock.elapsedRealtimeNanos() - location.elapsedRealtimeNanos) / 1000000L
        if (age < 0 || age > 15000) return
        val previous = best
        // 短时间内不让粗略的网络定位覆盖更精确的 GPS；其失效后仍接受新定位。
        if (previous != null && location.elapsedRealtimeNanos <= previous.elapsedRealtimeNanos) return
        if (previous != null && location.accuracy > previous.accuracy &&
            (SystemClock.elapsedRealtimeNanos() - previous.elapsedRealtimeNanos) / 1000000L < 3000) return
        best = Location(location)
        sink?.success(mapOf("type" to "fix", "lat" to location.latitude,
            "lon" to location.longitude, "accuracy" to location.accuracy.toDouble(), "ageMs" to age))
    }
    override fun onProviderDisabled(provider: String) { if (wanted && foreground) begin(false) }
    override fun onProviderEnabled(provider: String) { if (wanted && foreground) begin(false) }
    @Deprecated("兼容 Android 8 的 LocationListener")
    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD) magneticAccuracy = accuracy
    }
    override fun onSensorChanged(event: SensorEvent) {
        if (!running || !foreground || !wanted) return
        val matrix = FloatArray(9)
        var reliable = false
        if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR || event.sensor.type == Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) {
            SensorManager.getRotationMatrixFromVector(matrix, event.values)
            reliable = event.accuracy >= SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM
        } else {
            when (event.sensor.type) {
                Sensor.TYPE_ACCELEROMETER -> accel = event.values.copyOf()
                Sensor.TYPE_MAGNETIC_FIELD -> { magnetic = event.values.copyOf(); magneticAccuracy = event.accuracy }
            }
            val a = accel ?: return
            val m = magnetic ?: return
            if (!SensorManager.getRotationMatrix(matrix, null, a, m)) return
            reliable = magneticAccuracy >= SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM
        }
        val now = SystemClock.elapsedRealtime()
        if (now - lastHeading < 33) return
        lastHeading = now
        // 课表允许横屏，按当前屏幕方向转换设备坐标，避免箭头偏转 90°。
        @Suppress("DEPRECATION")
        val screenRotation = windowManager.defaultDisplay.rotation
        val axes = when (screenRotation) {
            Surface.ROTATION_90 -> SensorManager.AXIS_Y to SensorManager.AXIS_MINUS_X
            Surface.ROTATION_180 -> SensorManager.AXIS_MINUS_X to SensorManager.AXIS_MINUS_Y
            Surface.ROTATION_270 -> SensorManager.AXIS_MINUS_Y to SensorManager.AXIS_X
            else -> SensorManager.AXIS_X to SensorManager.AXIS_Y
        }
        val screenMatrix = FloatArray(9)
        if (!SensorManager.remapCoordinateSystem(matrix, axes.first, axes.second, screenMatrix)) return
        val projected = HeadingMath.fromMatrix(screenMatrix)
        reliable = reliable && projected != null
        val location = best
        val declination = if (location == null) 0.0 else GeomagneticField(
            location.latitude.toFloat(), location.longitude.toFloat(), location.altitude.toFloat(), System.currentTimeMillis()).declination.toDouble()
        val heading = if (reliable) headingFilter.update(HeadingMath.normalize(projected!! + declination), now) else null
        if (!reliable) headingFilter.reset()
        sink?.success(mapOf("type" to "heading", "heading" to heading, "reliable" to reliable))
    }
}
