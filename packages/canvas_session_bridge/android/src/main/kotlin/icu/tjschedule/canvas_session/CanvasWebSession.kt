package icu.tjschedule.canvas_session

import android.annotation.SuppressLint
import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.*
import org.json.JSONObject
import java.util.UUID

internal class CanvasWebSession(private val context: Context, private val vault: CanvasVault,
    private val config: JSONObject, private val mode: String,
    private val complete: (String?, Map<String, Any?>?) -> Unit) {
    private val handler = Handler(Looper.getMainLooper())
    private val nonce = UUID.randomUUID().toString()
    private var view: WebView? = null
    private var closed = false
    private var started = false
    private val timeout = Runnable { finish("login_or_web_timeout") }
    private fun trusted(): Boolean {
        val uri = Uri.parse(view?.url ?: "")
        return uri.scheme == "https" && uri.host == "canvas.tongji.edu.cn" && (uri.port == -1 || uri.port == 443)
    }
    @SuppressLint("SetJavaScriptEnabled", "JavascriptInterface")
    fun start() {
        handler.postDelayed(timeout, 120_000)
        try {
            val web = WebView(context); view = web
            web.settings.javaScriptEnabled = true; web.settings.domStorageEnabled = true
            web.settings.allowFileAccess = false; web.settings.allowContentAccess = false
            web.settings.mixedContentMode = WebSettings.MIXED_CONTENT_NEVER_ALLOW
            web.addJavascriptInterface(object {
                @JavascriptInterface fun postMessage(text: String) {
                    if (text.length > 65536) return
                    handler.post {
                        if (closed || !trusted()) return@post
                        try {
                            val message = JSONObject(text)
                            if (message.optString("nonce") != nonce) return@post
                            when (message.optString("kind")) {
                                "candidate" -> {
                                    val record = message.getJSONObject("record")
                                    require(matches(record, config))
                                    require(record.getString("token").matches(Regex("[A-Za-z0-9._~-]{30,2048}")))
                                    vault.update { it.put("pending", record) }
                                    web.evaluateJavascript("window.__canvasLabAck('candidate',true)", null)
                                }
                                "verified" -> {
                                    vault.update { state ->
                                        val pending = state.optJSONObject("pending")
                                        val record = if (matches(pending, config) && pending?.optBoolean("quarantined") != true) JSONObject(pending.toString()) else
                                            JSONObject(config.toString()).put("token", config.getString("currentToken"))
                                        record.remove("currentToken"); record.remove("nonce"); record.remove("credentialsOnly")
                                        record.put("enabled", true).put("verified", true)
                                        state.put("active", record).put("lastError", "").remove("pending")
                                    }
                                    web.evaluateJavascript("window.__canvasLabAck('verified',true)", null)
                                }
                                "done" -> {
                                    val result = message.getJSONObject("result")
                                    val status = result.optString("status")
                                    if (status != "ok") { finish(status); return@post }
                                    if (mode == "list") {
                                        val tokens = result.getJSONArray("tokens")
                                        val rows = (0 until tokens.length()).map { i ->
                                            val token = tokens.getJSONObject(i)
                                            mapOf("id" to token.getString("id"), "purpose" to token.getString("purpose"))
                                        }
                                        finish(null, mapOf("accountId" to result.getString("accountId"), "tokens" to rows))
                                    } else {
                                        val active = vault.read().getJSONObject("active")
                                        require(matches(active, config) && active.optBoolean("enabled"))
                                        finish(null, mapOf("accountId" to active.getString("accountId"), "token" to active.getString("token")))
                                    }
                                }
                            }
                        } catch (_: Exception) { finish("secure_save_or_bridge_failed") }
                    }
                }
            }, "CanvasLab")
            web.webViewClient = object : WebViewClient() {
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean {
                    if (request.url.scheme != "https") { finish("insecure_navigation_blocked"); return true }; return false
                }
                override fun onPageFinished(view: WebView, url: String) {
                    if (closed || started || !trusted() || Uri.parse(url).path != "/profile/settings") return
                    try {
                        started = true; CookieManager.getInstance().flush()
                        config.put("nonce", nonce)
                        val source = context.assets.open("canvas_rotation.js").bufferedReader().use { it.readText() }
                        val start = if (mode == "list") "CanvasRotation.startList" else "CanvasRotation.start"
                        view.evaluateJavascript(source + "\n" + start + "(" + config.toString() + ");", null)
                    } catch (_: Exception) { finish("web_setup_failed") }
                }
                override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: android.net.http.SslError) {
                    handler.cancel(); finish("tls_error")
                }
                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (request.isForMainFrame) finish("web_network_error")
                }
            }
            web.webChromeClient = object : WebChromeClient() {
                override fun onJsConfirm(view: WebView, url: String, message: String, result: JsResult): Boolean {
                    result.cancel(); finish("confirmation_requires_action"); return true
                }
                override fun onJsAlert(view: WebView, url: String, message: String, result: JsResult): Boolean {
                    result.cancel(); finish("confirmation_requires_action"); return true
                }
            }
            web.loadUrl("https://canvas.tongji.edu.cn/profile/settings")
        } catch (_: Exception) { finish("web_setup_failed") }
    }
    fun cancel() = finish("cancelled")
    private fun finish(error: String?, result: Map<String, Any?>? = null) {
        if (closed) return
        closed = true; handler.removeCallbacks(timeout)
        view?.apply { removeJavascriptInterface("CanvasLab"); stopLoading(); destroy() }; view = null
        if (error != null && error != "cancelled") try {
            vault.update { state ->
                state.put("lastError", error)
                if (error in listOf("rotation_identity_or_scope_changed", "wrong_test_token", "account_changed", "bearer_account_changed")) {
                    if (matches(state.optJSONObject("active"), config)) state.optJSONObject("active")?.put("enabled", false)
                    if (matches(state.optJSONObject("pending"), config)) state.optJSONObject("pending")?.put("quarantined", true)
                }
            }
        } catch (_: Exception) { }
        complete(error, result)
    }
}
