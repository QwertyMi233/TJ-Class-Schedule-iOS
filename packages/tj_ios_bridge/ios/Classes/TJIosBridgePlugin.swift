import Flutter
import UIKit
import WidgetKit

public final class TJIosBridgePlugin: NSObject, FlutterPlugin {
    private let widgets: FlutterMethodChannel
    private let location = TJLocationBridge()
    private static weak var foreground: TJIosBridgePlugin?
    private static var pendingTask: String?

    private init(messenger: FlutterBinaryMessenger) {
        widgets = FlutterMethodChannel(name: "offline_course_schedule/widget", binaryMessenger: messenger)
        super.init()
        widgets.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
        let locationChannel = FlutterMethodChannel(name: "offline_course_schedule/location", binaryMessenger: messenger)
        locationChannel.setMethodCallHandler { [weak self] call, result in
            self?.location.handle(call, result: result)
        }
        let locationEvents = FlutterEventChannel(name: "offline_course_schedule/location_events", binaryMessenger: messenger)
        locationEvents.setStreamHandler(location)
        let platform = FlutterMethodChannel(name: "offline_course_schedule/platform", binaryMessenger: messenger)
        platform.setMethodCallHandler { call, result in
            guard call.method == "appSettings" else { result(FlutterMethodNotImplemented); return }
            guard let url = URL(string: UIApplication.openSettingsURLString) else { result(nil); return }
            UIApplication.shared.open(url, options: [:]) { _ in result(nil) }
        }
        let notifications = FlutterMethodChannel(name: "offline_course_schedule/ios_notifications", binaryMessenger: messenger)
        notifications.setMethodCallHandler { call, result in
            guard call.method == "replaceScope",
                  let args = call.arguments as? [String: Any],
                  let scope = args["scope"] as? String,
                  ["courses", "tasks"].contains(scope),
                  let requests = args["requests"] as? [[String: Any]] else {
                result(FlutterError(code: "invalid_request", message: "Invalid reminder scope", details: nil)); return
            }
            TJNotificationQueue.shared.replace(scope: scope, requests: requests, result: result)
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = TJIosBridgePlugin(messenger: registrar.messenger())
        registrar.addMethodCallDelegate(instance, channel: instance.widgets)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any] ?? [:]
        if call.method == "initialTask" {
            Self.foreground = self
            let value = Self.pendingTask
            Self.pendingTask = nil
            result(value)
            return
        }
        guard ["update", "updateTasks"].contains(call.method) else {
            result(FlutterMethodNotImplemented); return
        }
        guard let group = Bundle.main.object(forInfoDictionaryKey: "TJAppGroup") as? String,
              FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil,
              let defaults = UserDefaults(suiteName: group) else {
            result(FlutterError(code: "app_group_unavailable", message: "App and widget must use the same signed App Group", details: nil)); return
        }
        do {
            let key = call.method == "update" ? "schedule_widget_courses" : "task_widget_tasks"
            let rows = args[call.method == "update" ? "courses" : "tasks"] as? [[String: Any]] ?? []
            let data = try JSONSerialization.data(withJSONObject: rows)
            defaults.set(data, forKey: key)
            defaults.set(Date().timeIntervalSince1970, forKey: key + "_updated")
            if args.keys.contains("color") {
                if let color = args["color"] as? NSNumber { defaults.set(color, forKey: "widget_color") }
                else { defaults.removeObject(forKey: "widget_color") }
            }
            // Data is shared across app/extension and across Flutter engines.
            defaults.synchronize()
            WidgetCenter.shared.reloadTimelines(ofKind: call.method == "update" ? "NextCourseWidget" : "TaskDeadlineWidget")
            result(nil)
        } catch {
            result(FlutterError(code: "widget_write_failed", message: "Unable to update widget data", details: nil))
        }
    }

    /// Called by SceneDelegate for both warm and cold widget launches.
    public static func openWidgetURL(_ url: URL) {
        guard url.scheme == "tjschedule", url.host == "task" else { return }
        let task = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "id" })?.value ?? ""
        if let instance = foreground {
            instance.widgets.invokeMethod("openTask", arguments: task)
        } else {
            pendingTask = task
        }
    }
}
