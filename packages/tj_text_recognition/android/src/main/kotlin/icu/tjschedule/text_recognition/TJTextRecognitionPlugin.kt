package icu.tjschedule.text_recognition

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class TJTextRecognitionPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
    private lateinit var context: Context
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "offline_course_schedule/text_recognition")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "recognizeFile") { result.notImplemented(); return }
        val path = call.argument<String>("path")
        if (path.isNullOrEmpty()) { result.error("invalid_image", "无法读取图片", null); return }
        try {
            val image = InputImage.fromFilePath(context, Uri.fromFile(File(path)))
            val recognizer = TextRecognition.getClient(ChineseTextRecognizerOptions.Builder().build())
            recognizer.process(image)
                .addOnSuccessListener { result.success(it.text) }
                .addOnFailureListener { result.error("recognition_failed", "图片文字识别失败", null) }
                .addOnCompleteListener { recognizer.close() }
        } catch (_: Exception) {
            result.error("invalid_image", "无法读取图片", null)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
