import WidgetKit
import SwiftUI

private let courseKey = "schedule_widget_courses"
private let taskKey = "task_widget_tasks"

struct CourseEntry: TimelineEntry {
    let date: Date
    let courses: [CourseItem]
    let updated: Date?
    var next: CourseItem? { WidgetData.nextCourse(courses, at: date) }
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [TaskItem]
    let updated: Date?
    var next: TaskItem? { WidgetData.nextTask(tasks, at: date) }
    var overdue: Int { WidgetData.overdue(tasks, at: date) }
}

struct CourseProvider: TimelineProvider {
    func placeholder(in context: Context) -> CourseEntry {
        CourseEntry(date: Date(), courses: [], updated: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (CourseEntry) -> Void) {
        completion(CourseEntry(date: Date(), courses: WidgetData.load(courseKey), updated: WidgetData.updated(courseKey)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<CourseEntry>) -> Void) {
        let now = Date()
        let items: [CourseItem] = WidgetData.load(courseKey)
        let moments = WidgetData.moments(items.flatMap { [$0.start, $0.start.addingTimeInterval(-1800), $0.start.addingTimeInterval(-600)] }, now: now)
        let entries = moments.map { CourseEntry(date: $0, courses: items, updated: WidgetData.updated(courseKey)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

struct TaskProvider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(date: Date(), tasks: [], updated: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(TaskEntry(date: Date(), tasks: WidgetData.load(taskKey), updated: WidgetData.updated(taskKey)))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let now = Date()
        let items: [TaskItem] = WidgetData.load(taskKey)
        let moments = WidgetData.moments(items.flatMap { [$0.due, $0.due.addingTimeInterval(-86400)] }, now: now)
        let entries = moments.map { TaskEntry(date: $0, tasks: items, updated: WidgetData.updated(taskKey)) }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(6 * 3600))))
    }
}

private struct WidgetPalette {
    let background: Color
    let foreground: Color
    init(urgent: Bool = false) {
        if urgent {
            background = Color(red: 1, green: 0.90, blue: 0.89)
            foreground = .black
        } else if let number = WidgetData.defaults?.object(forKey: "widget_color") as? NSNumber {
            let raw = number.uint32Value
            let r = Double((raw >> 16) & 255) / 255
            let g = Double((raw >> 8) & 255) / 255
            let b = Double(raw & 255) / 255
            background = Color(red: r, green: g, blue: b)
            foreground = 0.2126 * r + 0.7152 * g + 0.0722 * b < 0.5 ? .white : .black
        } else {
            background = Color(uiColor: .secondarySystemBackground)
            foreground = .primary
        }
    }
}

private struct Countdown: View {
    let target: Date
    let now: Date
    var body: some View {
        // System-driven timer text avoids per-second timeline reloads.
        Text(timerInterval: min(now, target)...max(now, target), countsDown: true)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(Text("剩余时间"))
    }
}

struct CourseWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CourseEntry
    private var palette: WidgetPalette {
        WidgetPalette(urgent: entry.next.map { $0.start.timeIntervalSince(entry.date) <= 600 } ?? false)
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let item = entry.next {
                    Text("\(item.start, format: .dateTime.hour().minute()) \(item.name)")
                } else { Text("暂无后续课程") }
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "graduationcap")
                    if let item = entry.next { Countdown(target: item.start, now: entry.date).font(.caption2) }
                    else { Text("无课").font(.caption2) }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.next?.name ?? "暂无后续课程").font(.headline).lineLimit(1)
                    if let item = entry.next {
                        Text("\(item.start, format: .dateTime.hour().minute()) · \(item.location)").font(.caption).lineLimit(1)
                        Countdown(target: item.start, now: entry.date).font(.caption)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Label(entry.next?.isMemo == true ? "下一项安排" : "下一节课", systemImage: "graduationcap")
                        .font(.caption).opacity(0.75)
                    if let item = entry.next {
                        Text(item.name).font(.headline).lineLimit(2)
                        if !item.location.isEmpty { Text(item.location).font(.caption).lineLimit(1) }
                        Text(item.start, format: .dateTime.month().day().weekday().hour().minute()).font(.caption2).lineLimit(1)
                        Spacer(minLength: 0)
                        Countdown(target: item.start, now: entry.date).font(.title2.bold())
                        if family != .systemSmall, !item.teacher.isEmpty { Text(item.teacher).font(.caption).lineLimit(1) }
                        if family == .systemLarge {
                            Divider()
                            ForEach(Array(entry.courses.filter { $0.start > item.start }.sorted { $0.start < $1.start }.prefix(3).enumerated()), id: \.offset) { _, course in
                                HStack {
                                    Text(course.name).lineLimit(1)
                                    Spacer()
                                    Text(course.start, format: .dateTime.hour().minute())
                                }.font(.caption)
                            }
                        }
                    } else {
                        Text(entry.updated == nil ? "请先打开 App 同步课表" : "暂无后续课程").font(.headline)
                        Text("打开 App 查看或更新安排").font(.caption)
                        Spacer(minLength: 0)
                    }
                    if family != .systemSmall, let updated = entry.updated {
                        Text("更新于 \(updated, format: .dateTime.month().day().hour().minute())").font(.caption2).opacity(0.65)
                    }
                }
                .foregroundStyle(palette.foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(URL(string: "tjschedule://home"))
    }
}

struct TaskWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TaskEntry
    private var palette: WidgetPalette {
        WidgetPalette(urgent: entry.next.map { $0.due.timeIntervalSince(entry.date) <= 86400 } ?? false)
    }
    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text(entry.next.map { "作业：\($0.title)" } ?? "已逾期 \(entry.overdue) 项")
            case .accessoryCircular:
                VStack(spacing: 2) {
                    Image(systemName: "checklist")
                    if let item = entry.next { Countdown(target: item.due, now: entry.date).font(.caption2) }
                    else { Text("\(entry.overdue) 逾期").font(.caption2) }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.next?.title ?? "暂无待截止作业").font(.headline).lineLimit(1)
                    if let item = entry.next { Countdown(target: item.due, now: entry.date).font(.caption) }
                    Text("已逾期 \(entry.overdue) 项").font(.caption2)
                }
            default:
                VStack(alignment: .leading, spacing: 5) {
                    Label("作业倒计时", systemImage: "checklist").font(.caption).opacity(0.75)
                    Text(entry.next?.title ?? "暂无待截止作业").font(.headline).lineLimit(2)
                    if let item = entry.next {
                        Text(item.course).font(.caption).lineLimit(1)
                        Text("截止 \(item.due, format: .dateTime.month().day().hour().minute())").font(.caption2).lineLimit(1)
                        Spacer(minLength: 0)
                        Countdown(target: item.due, now: entry.date).font(.title2.bold())
                    } else { Spacer(minLength: 0) }
                    Text("已逾期 \(entry.overdue) 项").font(.caption)
                    if family == .systemLarge {
                        Divider()
                        ForEach(Array(entry.tasks.filter { $0.due > entry.date }.sorted { $0.due < $1.due }.dropFirst().prefix(3).enumerated()), id: \.offset) { _, task in
                            Text(task.title).font(.caption).lineLimit(1)
                        }
                    }
                    if family != .systemSmall, let updated = entry.updated {
                        Text("更新于 \(updated, format: .dateTime.month().day().hour().minute())").font(.caption2).opacity(0.65)
                    }
                }
                .foregroundStyle(palette.foreground)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(entry.next?.url ?? URL(string: "tjschedule://task"))
    }
}

struct NextCourseWidget: Widget {
    let kind = "NextCourseWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CourseProvider()) { CourseWidgetView(entry: $0) }
            .configurationDisplayName("下一节课")
            .description("下一节课或备忘录的时间、地点和倒计时。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct TaskDeadlineWidget: Widget {
    let kind = "TaskDeadlineWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TaskProvider()) { TaskWidgetView(entry: $0) }
            .configurationDisplayName("作业倒计时")
            .description("最近的未完成作业截止时间与逾期数量。")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct TJWidgetsBundle: WidgetBundle {
    var body: some Widget { NextCourseWidget(); TaskDeadlineWidget() }
}
