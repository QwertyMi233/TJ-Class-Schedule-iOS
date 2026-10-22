import Foundation
import XCTest

final class RunnerTests: XCTestCase {
    func testWidgetAdvancesAtCourseStartAndHandlesMemo() throws {
        let data = Data("""
        [{"name":"微积分","teacher":"张老师","location":"A101","startMillis":200000,"isMemo":false},
         {"name":"组会","teacher":"","location":"图书馆","startMillis":300000,"isMemo":true}]
        """.utf8)
        let items = try JSONDecoder().decode([CourseItem].self, from: data)
        XCTAssertEqual(WidgetData.nextCourse(items, at: Date(timeIntervalSince1970: 199))?.name, "微积分")
        XCTAssertEqual(WidgetData.nextCourse(items, at: Date(timeIntervalSince1970: 200))?.name, "组会")
        XCTAssertTrue(WidgetData.nextCourse(items, at: Date(timeIntervalSince1970: 200))?.isMemo == true)
        XCTAssertNil(WidgetData.nextCourse(items, at: Date(timeIntervalSince1970: 300)))
    }

    func testTaskDeadlineEqualityAndDeepLinkEncoding() throws {
        let data = Data("""
        [{"id":"canvas:中文 /?&","title":"物理作业","course":"物理","dueMillis":200000},
         {"id":"next","title":"数学作业","course":"数学","dueMillis":300000}]
        """.utf8)
        let items = try JSONDecoder().decode([TaskItem].self, from: data)
        let now = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(WidgetData.overdue(items, at: now), 1)
        XCTAssertEqual(WidgetData.nextTask(items, at: now)?.id, "next")
        let query = URLComponents(url: items[0].url, resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first?.value, "canvas:中文 /?&")
    }

    func testReminderBudgetMergesScopesAndKeepsEarliestSixty() {
        let now = Date(timeIntervalSince1970: 100)
        func plan(_ id: Int, _ seconds: Double) -> TJReminder {
            TJReminder(dictionary: ["id": id, "timeMillis": seconds * 1000,
                "title": "提醒", "body": "地点", "payload": "task:\(id)", "sound": false])!
        }
        let courses = (0..<50).map { plan($0, Double(200 + $0 * 2)) }
        let tasks = (0..<50).map { plan(1000 + $0, Double(201 + $0 * 2)) }
        let result = TJNotificationQueue.select(scopes: ["courses": courses, "tasks": tasks + [plan(9999, 99)]], now: now)
        XCTAssertEqual(result.count, 60)
        XCTAssertEqual(result.filter { $0.0 == "courses" }.count, 30)
        XCTAssertEqual(result.filter { $0.0 == "tasks" }.count, 30)
        XCTAssertEqual(result.last?.1.timeMillis, 259000)
        XCTAssertFalse(result.contains { $0.1.id == 9999 })
        XCTAssertEqual(TJNotificationQueue.select(scopes: ["courses": [], "tasks": tasks], now: now).count, 50)
    }

    func testTimelineMomentsSortDeduplicateAndIgnoreExpiredDates() {
        let now = Date(timeIntervalSince1970: 100)
        let future = Date(timeIntervalSince1970: 200)
        XCTAssertEqual(WidgetData.moments([future, now, future, Date(timeIntervalSince1970: 50)], now: now), [now, future])
    }
}
