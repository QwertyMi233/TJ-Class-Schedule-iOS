import Foundation

/// A file snapshot gives the app and extension one atomic, uncached source.
/// Re-signers sometimes rename App Groups without changing Info.plist. Only
/// groups authorized by iOS and shared by both provisioned targets are used.
enum TJWidgetStore {
    static var configuredGroup: String? { Bundle.main.object(forInfoDictionaryKey: "TJAppGroup") as? String }

    static func profileGroups(_ bundle: Bundle) -> Set<String> {
        guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let root = try? PropertyListSerialization.propertyList(from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any],
              let entitlements = root["Entitlements"] as? [String: Any] else { return [] }
        return Set(entitlements["com.apple.security.application-groups"] as? [String] ?? [])
    }

    static var sharedProfileGroups: Set<String> {
        let own = profileGroups(.main)
        if Bundle.main.bundleURL.pathExtension == "appex" {
            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            guard let app = Bundle(url: appURL) else { return own }
            let groups = profileGroups(app)
            return groups.isEmpty ? own : own.intersection(groups)
        }
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { return own }
        let widgets = urls.compactMap(Bundle.init(url:)).filter {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension"
        }
        let extensionGroups = widgets.reduce(into: Set<String>()) { $0.formUnion(profileGroups($1)) }
        return extensionGroups.isEmpty ? own : own.intersection(extensionGroups)
    }

    static var group: String? {
        let provisioned = sharedProfileGroups
        if let configured = configuredGroup,
           (!bothProfilesDeclareGroups || provisioned.contains(configured)),
           FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: configured) != nil { return configured }
        let available = provisioned.sorted().filter {
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) != nil
        }
        // Never guess between unrelated authorized containers.
        return available.count == 1 ? available[0] : nil
    }

    static var bothProfilesDeclareGroups: Bool {
        guard !profileGroups(.main).isEmpty else { return false }
        if Bundle.main.bundleURL.pathExtension == "appex" {
            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            return Bundle(url: appURL).map { !profileGroups($0).isEmpty } ?? false
        }
        guard let plugins = Bundle.main.builtInPlugInsURL,
              let urls = try? FileManager.default.contentsOfDirectory(at: plugins, includingPropertiesForKeys: nil) else { return false }
        return urls.compactMap(Bundle.init(url:)).contains {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String == "com.apple.widgetkit-extension" && !profileGroups($0).isEmpty
        }
    }

    static var directory: URL? {
        guard let group = group else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("TJWidgetSnapshots", isDirectory: true)
    }

    static func write(_ key: String, rows: [[String: Any]], color: Any? = nil, updateColor: Bool = false) throws {
        guard let directory = directory else { throw NSError(domain: "TJWidgetStore", code: 1) }
        try writeSnapshot(key, rows: rows, directory: directory)
        if updateColor {
            let appearance: [String: Any] = ["color": (color as? NSNumber).map { $0 as Any } ?? NSNull()]
            try JSONSerialization.data(withJSONObject: appearance).write(to: directory.appendingPathComponent("appearance.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    static func writeSnapshot(_ key: String, rows: [[String: Any]], directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot: [String: Any] = ["version": 1, "updated": Date().timeIntervalSince1970, "items": rows]
        try JSONSerialization.data(withJSONObject: snapshot).write(to: directory.appendingPathComponent(key + ".json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func snapshot(_ key: String) -> [String: Any]? {
        guard let directory = directory else { return nil }
        return readSnapshot(key, directory: directory)
    }

    static func readSnapshot(_ key: String, directory: URL) -> [String: Any]? {
        let file = directory.appendingPathComponent(key + ".json")
        guard
              let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    static func diagnostics() -> [String: Any] {
        let courses = snapshot("schedule_widget_courses")
        let tasks = snapshot("task_widget_tasks")
        return ["configuredGroup": configuredGroup ?? "", "resolvedGroup": group ?? "",
                "containerAvailable": directory != nil,
                "courseCount": (courses?["items"] as? [Any])?.count ?? 0,
                "taskCount": (tasks?["items"] as? [Any])?.count ?? 0,
                "coursesUpdated": courses?["updated"] ?? 0, "tasksUpdated": tasks?["updated"] ?? 0]
    }
}
