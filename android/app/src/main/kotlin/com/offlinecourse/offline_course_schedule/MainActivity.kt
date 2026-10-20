package com.offlinecourse.offline_course_schedule

import android.content.Intent
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray

class MainActivity : LocationActivity() {
    private var widgetChannel: MethodChannel? = null
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.getBooleanExtra("open_tasks", false)) {
            widgetChannel?.invokeMethod("openTask", intent.getStringExtra("task_id") ?: "")
            intent.removeExtra("open_tasks")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "offline_course_schedule/widget",
        )
        widgetChannel = channel
        channel.setMethodCallHandler { call, result ->
            if (call.method == "initialTask") {
                result.success(if (intent.getBooleanExtra("open_tasks", false)) intent.getStringExtra("task_id") ?: "" else null)
                intent.removeExtra("open_tasks")
                return@setMethodCallHandler
            }
            if (call.method == "updateTasks") {
                val tasks = call.argument<List<Map<String, Any?>>>("tasks") ?: emptyList()
                getSharedPreferences(NextCourseWidget.PREFS_NAME, MODE_PRIVATE).edit()
                    .putString(TaskDeadlineWidget.TASKS_KEY, JSONArray(tasks).toString()).apply()
                getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                    .putString("flutter.task_widget_tasks", JSONArray(tasks).toString()).apply()
                TaskDeadlineWidget.updateAll(this)
                result.success(null)
                return@setMethodCallHandler
            }
            if (call.method != "update") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val courses = call.argument<List<Map<String, Any?>>>("courses") ?: emptyList()
            // ARGB 超出 Int 范围时会以 int64 传入，先按 Number 读取再转 Int；null 恢复默认色。
            val color = (call.argument<Any?>("color") as? Number)?.toInt()
            // 刷新频率由 Flutter 侧决定；为 null 时交给原生侧按默认（省电）处理。
            val refreshMode = call.argument<String>("refreshMode")
            val editor = getSharedPreferences(NextCourseWidget.PREFS_NAME, MODE_PRIVATE)
                .edit()
                .putString(NextCourseWidget.COURSES_KEY, JSONArray(courses).toString())
            // 首屏先更新课程；设置未读完时沿用小组件已保存的外观。
            if (call.hasArgument("refreshMode")) {
                if (refreshMode == null) {
                    editor.remove(NextCourseWidget.REFRESH_MODE_KEY)
                } else {
                    editor.putString(NextCourseWidget.REFRESH_MODE_KEY, refreshMode)
                }
            }
            if (call.hasArgument("color")) {
                if (color == null) {
                    editor.remove(NextCourseWidget.COLOR_KEY)
                } else {
                    editor.putInt(NextCourseWidget.COLOR_KEY, color)
                }
            }
            editor.apply()
            getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE).edit()
                .putString("flutter.schedule_widget_courses", JSONArray(courses).toString()).apply()
            NextCourseWidget.updateAll(this)
            result.success(null)
        }
    }
}
