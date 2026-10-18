package icu.tjschedule.canvas_session

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import org.json.JSONObject
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal class CanvasVault(context: Context) {
    private val prefs = context.getSharedPreferences("canvas_session_private", Context.MODE_PRIVATE)
    companion object { private val guard = Any(); private const val ALIAS = "canvas_session_v1" }
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(ALIAS, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
    }
    fun read(): JSONObject = synchronized(guard) {
        val text = prefs.getString("state", null) ?: return@synchronized JSONObject()
        val bytes = Base64.decode(text, Base64.NO_WRAP)
        require(bytes.size > 12)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
        JSONObject(String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)), Charsets.UTF_8))
    }
    fun update(change: (JSONObject) -> Unit) = synchronized(guard) {
        val value = read(); change(value)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        check(prefs.edit().putString("state", Base64.encodeToString(cipher.iv + cipher.doFinal(value.toString().toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)).commit())
    }
    fun clear() = synchronized(guard) { check(prefs.edit().clear().commit()) }
}
