import Foundation

struct CourseItem: Decodable {
    let name: String
    let teacher: String
    let location: String
    let startMillis: Double
    let isMemo: Bool?
    var start: Date { Date(timeIntervalSince1970: startMillis / 1000) }
}

struct TaskItem: Decodable {
    let id: String
    let title: String
    let course: String
    let dueMillis: Double
    var due: Date { Date(timeIntervalSince1970: dueMillis / 1000) }
    var url: URL {
        var value = URLComponents()
        value.scheme = "tjschedule"
        value.host = "task"
        value.queryItems = [URLQueryItem(name: "id", value: id)]
        return value.url ?? URL(string: "tjschedule://task")!
    }
}

enum WidgetData {
    static var defaults: UserDefaults? {
        guard let group = TJWidgetStore.group else { return nil }
        return UserDefaults(suiteName: group)
    }

    static func load<T: Decodable>(_ key: String) -> [T] {
        if let snapshot = TJWidgetStore.snapshot(key), let rows = snapshot["items"],
           let data = try? JSONSerialization.data(withJSONObject: rows) {
            return (try? JSONDecoder().decode([T].self, from: data)) ?? []
        }
        guard let data = defaults?.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([T].self, from: data)) ?? []
    }

    static func updated(_ key: String) -> Date? {
        if let value = TJWidgetStore.snapshot(key)?["updated"] as? Double { return Date(timeIntervalSince1970: value) }
        let seconds = defaults?.double(forKey: key + "_updated") ?? 0
        return seconds > 0 ? Date(timeIntervalSince1970: seconds) : nil
    }

    static var setupMessage: String {
        TJWidgetStore.directory == nil ? "签名未启用小组件共享，请在 App 检查" : "请打开 App 同步课表与作业"
    }

    static var color: NSNumber? {
        if let appearance = TJWidgetStore.snapshot("appearance") { return appearance["color"] as? NSNumber }
        return defaults?.object(forKey: "widget_color") as? NSNumber
    }

    static func nextCourse(_ items: [CourseItem], at date: Date) -> CourseItem? {
        items.filter { $0.startMillis.isFinite && $0.start > date }.min { $0.start < $1.start }
    }

    static func nextTask(_ items: [TaskItem], at date: Date) -> TaskItem? {
        items.filter { $0.dueMillis.isFinite && $0.due > date }.min { $0.due < $1.due }
    }

    static func overdue(_ items: [TaskItem], at date: Date) -> Int {
        items.filter { $0.dueMillis.isFinite && $0.due <= date }.count
    }

    static func moments(_ dates: [Date], now: Date) -> [Date] {
        let upcoming = Set(dates.filter { $0 > now && $0.timeIntervalSince(now) < 14 * 86400 })
        return [now] + Array(upcoming.sorted().prefix(150))
    }
}
