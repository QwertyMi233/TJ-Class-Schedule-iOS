import Foundation
import Flutter
import UserNotifications

struct TJReminder: Codable {
    let id: Int
    let timeMillis: Double
    let title: String
    let body: String
    let payload: String
    let sound: Bool
    var date: Date { Date(timeIntervalSince1970: timeMillis / 1000) }

    init?(dictionary: [String: Any]) {
        guard let id = dictionary["id"] as? NSNumber,
              let millis = dictionary["timeMillis"] as? NSNumber,
              millis.doubleValue.isFinite,
              let title = dictionary["title"] as? String,
              let body = dictionary["body"] as? String,
              let payload = dictionary["payload"] as? String else { return nil }
        self.id = id.intValue
        timeMillis = millis.doubleValue
        self.title = title
        self.body = body
        self.payload = payload
        sound = dictionary["sound"] as? Bool ?? false
    }
}

/// One queue shared by every foreground/background Flutter engine in the process.
/// Callbacks are serialized through drain(), including asynchronous UN operations.
final class TJNotificationQueue {
    static let shared = TJNotificationQueue()
    private let center = UNUserNotificationCenter.current()
    private let key = "tj.ios.notification.scopes.v1"
    private var jobs: [(String, [TJReminder], FlutterResult)] = []
    private var running = false

    func replace(scope: String, requests: [[String: Any]], result: @escaping FlutterResult) {
        let parsed = requests.compactMap(TJReminder.init(dictionary:))
        guard parsed.count == requests.count, parsed.count <= 10000 else {
            result(FlutterError(code: "invalid_reminder", message: "Invalid reminder data", details: nil)); return
        }
        DispatchQueue.main.async {
            self.jobs.append((scope, parsed, result))
            self.drain()
        }
    }

    private func drain() {
        guard !running, !jobs.isEmpty else { return }
        running = true
        let (scope, requests, result) = jobs.removeFirst()
        var scopes = (UserDefaults.standard.data(forKey: key))
            .flatMap { try? JSONDecoder().decode([String: [TJReminder]].self, from: $0) } ?? [:]
        scopes[scope] = requests
        let now = Date()
        scopes = scopes.mapValues { $0.filter { $0.date > now } }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(scopes), forKey: key)
        } catch {
            finish(result, FlutterError(code: "notification_store_failed", message: "Cannot save reminder queue", details: nil)); return
        }
        let selected = Self.select(scopes: scopes, now: now)
        center.getNotificationSettings { settings in
            self.center.getPendingNotificationRequests { existing in
                let owned = existing.filter { $0.identifier.hasPrefix("tj.ios.") }.map(\.identifier)
                self.center.removePendingNotificationRequests(withIdentifiers: owned)
                guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                    DispatchQueue.main.async { self.finish(result, 0) }; return
                }
                let group = DispatchGroup()
                let errorLock = NSLock()
                var failed = false
                for (kind, plan) in selected {
                    let content = UNMutableNotificationContent()
                    content.title = plan.title
                    content.body = plan.body
                    content.threadIdentifier = kind
                    content.sound = plan.sound ? .default : nil
                    // Contract of flutter_local_notifications 22.x. This lets the
                    // existing Dart response handler receive cold and warm taps.
                    content.userInfo = ["NotificationId": plan.id, "payload": plan.payload,
                                        "presentAlert": true, "presentSound": plan.sound,
                                        "presentBadge": false, "presentBanner": true, "presentList": true]
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, plan.date.timeIntervalSinceNow), repeats: false)
                    let request = UNNotificationRequest(identifier: "tj.ios.\(kind).\(plan.id)", content: content, trigger: trigger)
                    group.enter()
                    self.center.add(request) { error in
                        if error != nil { errorLock.lock(); failed = true; errorLock.unlock() }
                        group.leave()
                    }
                }
                group.notify(queue: .main) {
                    if failed {
                        self.finish(result, FlutterError(code: "notification_schedule_failed", message: "Some system reminders could not be scheduled", details: nil))
                    } else {
                        self.finish(result, selected.filter { $0.0 == scope }.count)
                    }
                }
            }
        }
    }

    static func select(scopes: [String: [TJReminder]], now: Date) -> [(String, TJReminder)] {
        scopes.flatMap { scope, plans in plans.map { (scope, $0) } }
            .filter { $0.1.date > now }
            .sorted {
                if $0.1.timeMillis != $1.1.timeMillis { return $0.1.timeMillis < $1.1.timeMillis }
                if $0.0 != $1.0 { return $0.0 < $1.0 }
                return $0.1.id < $1.1.id
            }
            .prefix(60).map { $0 }
    }

    private func finish(_ result: FlutterResult, _ value: Any?) {
        running = false
        result(value)
        drain()
    }
}
