package icu.tjschedule.canvas_session

import android.content.Context
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class CanvasSessionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel
    private var ownedSession: CanvasWebSession? = null
    companion object { private var current: CanvasWebSession? = null }
    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "offline_course_schedule/canvas_session")
        channel.setMethodCallHandler(this)
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        ownedSession?.cancel()
        channel.setMethodCallHandler(null)
    }
    override fun onMethodCall(call: MethodCall, reply: MethodChannel.Result) {
        val vault = CanvasVault(context)
        try {
            when (call.method) {
                "status" -> {
                    val state = vault.read(); val active = state.optJSONObject("active")
                    reply.success(mapOf("enabled" to (active?.optBoolean("enabled") == true),
                        "accountId" to active?.optString("accountId"), "purpose" to active?.optString("purpose"),
                        "expiresAt" to active?.optString("expiresAt"), "lastError" to state.optString("lastError"),
                        "batteryOptimizationIgnored" to context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName)))
                }
                "clear", "disable" -> {
                    current?.cancel()
                    if (call.method == "clear") vault.clear()
                    else vault.update { it.optJSONObject("active")?.put("enabled", false) }
                    reply.success(null)
                }
                "list", "configure", "prepare" -> {
                    if (current != null) { reply.error("busy", "连接维护正在进行", null); return }
                    val state = vault.read()
                    val config = if (call.method == "configure") {
                        JSONObject().put("accountId", call.argument<String>("accountId"))
                            .put("tokenId", call.argument<String>("tokenId")).put("purpose", call.argument<String>("purpose"))
                    } else if (call.method == "prepare") {
                        val active = state.optJSONObject("active")
                        if (active?.optBoolean("enabled") != true || active.optString("accountId") != call.argument<String>("accountId")) {
                            reply.success(null); return
                        }
                        JSONObject(active.toString())
                    } else JSONObject()
                    if (call.method != "list") {
                        require(config.getString("accountId").matches(Regex("[0-9]+")))
                        require(config.getString("tokenId").matches(Regex("[0-9]+")))
                        require(config.getString("purpose").isNotBlank() && config.getString("purpose").length <= 200)
                        val pending = state.optJSONObject("pending")
                        val active = state.optJSONObject("active")
                        val saved = when {
                            matches(pending, config) && pending?.optBoolean("quarantined") != true -> pending
                            matches(active, config) -> active
                            else -> null
                        }
                        config.put("currentToken", saved?.optString("token") ?: "").put("credentialsOnly", true)
                    }
                    var session: CanvasWebSession? = null
                    session = CanvasWebSession(context, vault, config, call.method) { code, result ->
                        if (current === session) current = null
                        if (ownedSession === session) ownedSession = null
                        if (code == null) reply.success(result) else reply.error(code, "Canvas连接维护未完成", null)
                    }
                    current = session; ownedSession = session
                    session.start()
                }
                else -> reply.notImplemented()
            }
        } catch (_: Exception) { reply.error("secure_or_config_failed", "本机安全存储或连接设置未完成", null) }
    }
}

internal fun matches(record: JSONObject?, config: JSONObject): Boolean = record != null &&
    listOf("tokenId", "accountId", "purpose").all { record.optString(it) == config.optString(it) }
