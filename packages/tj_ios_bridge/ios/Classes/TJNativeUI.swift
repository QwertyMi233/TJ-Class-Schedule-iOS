import Flutter
import UIKit

/// Real UIKit controls, composited over Flutter. iOS owns material, menus,
/// hit testing, accessibility and reduced-transparency/motion behavior.
final class TJNativeUIFactory: NSObject, FlutterPlatformViewFactory {
    private let messenger: FlutterBinaryMessenger
    init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
    func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
    func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
        TJNativeUIView(frame: frame, id: viewId, messenger: messenger, configuration: args as? [String: Any] ?? [:])
    }
}

final class TJNativeUIView: NSObject, FlutterPlatformView {
    private let root: UIView
    private let channel: FlutterMethodChannel
    private var configuration: [String: Any]

    init(frame: CGRect, id: Int64, messenger: FlutterBinaryMessenger, configuration: [String: Any]) {
        root = UIView(frame: frame)
        channel = FlutterMethodChannel(name: "offline_course_schedule/native_ui/\(id)", binaryMessenger: messenger)
        self.configuration = configuration
        super.init()
        root.backgroundColor = .clear
        channel.setMethodCallHandler { [weak self] call, result in
            guard call.method == "update", let config = call.arguments as? [String: Any] else {
                result(FlutterMethodNotImplemented); return
            }
            self?.configuration = config
            self?.render()
            result(nil)
        }
        render()
    }

    func view() -> UIView { root }
    private func send(_ id: String) { channel.invokeMethod("action", arguments: id) }
    private func image(_ row: [String: Any]) -> UIImage? {
        (row["symbol"] as? String).flatMap { UIImage(systemName: $0) }
    }
    private func menu(_ rows: [[String: Any]]) -> UIMenu {
        UIMenu(children: rows.map { row in
            let action = UIAction(title: row["title"] as? String ?? "", image: image(row),
                                  attributes: row["enabled"] as? Bool == false ? .disabled : []) { [weak self] _ in
                self?.send(row["id"] as? String ?? "")
            }
            if row["destructive"] as? Bool == true { action.attributes.insert(.destructive) }
            return action
        })
    }
    private func render() {
        root.subviews.forEach { $0.removeFromSuperview() }
        root.overrideUserInterfaceStyle = configuration["dark"] as? Bool == true ? .dark : .light
        if let value = configuration["tint"] as? NSNumber {
            let rgb = value.uint32Value
            root.tintColor = UIColor(red: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                                     blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
        switch configuration["kind"] as? String {
        case "navigation":
            let bar = UINavigationBar()
            let item = UINavigationItem(title: configuration["title"] as? String ?? "")
            if configuration["back"] as? Bool == true {
                let back = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), primaryAction: UIAction { [weak self] _ in self?.send("back") })
                back.accessibilityLabel = "返回"
                item.leftBarButtonItem = back
            }
            let actions = configuration["actions"] as? [[String: Any]] ?? []
            item.rightBarButtonItems = actions.reversed().map { row in
                let action = UIAction { [weak self] _ in self?.send(row["id"] as? String ?? "") }
                let children = row["menu"] as? [[String: Any]]
                let button = UIBarButtonItem(title: row["symbol"] == nil ? row["title"] as? String : nil,
                                              image: image(row), primaryAction: children == nil ? action : nil,
                                              menu: children.map(menu))
                button.accessibilityLabel = row["title"] as? String
                button.isEnabled = row["enabled"] as? Bool != false
                return button
            }
            bar.setItems([item], animated: false)
            add(bar)
        case "segmented":
            let control = UISegmentedControl(items: configuration["titles"] as? [String] ?? [])
            control.selectedSegmentIndex = configuration["selected"] as? Int ?? 0
            control.addAction(UIAction { [weak self, weak control] _ in
                if let control = control { self?.send(String(control.selectedSegmentIndex)) }
            }, for: .valueChanged)
            add(control, inset: 4)
        default:
            let button = UIButton(type: .system)
            var style: UIButton.Configuration
            if #available(iOS 26.0, *) {
                style = configuration["prominent"] as? Bool == true ? .prominentGlass() : .glass()
            } else {
                style = configuration["prominent"] as? Bool == true ? .filled() : .tinted()
            }
            style.title = configuration["title"] as? String
            style.image = image(configuration)
            style.imagePadding = 8
            style.cornerStyle = .capsule
            style.contentInsets = NSDirectionalEdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16)
            button.configuration = style
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.lineBreakMode = .byWordWrapping
            button.accessibilityLabel = configuration["label"] as? String ?? configuration["title"] as? String
            button.isEnabled = configuration["enabled"] as? Bool != false
            if let rows = configuration["menu"] as? [[String: Any]] {
                button.menu = menu(rows)
                button.showsMenuAsPrimaryAction = true
            } else {
                button.addAction(UIAction { [weak self] _ in self?.send("tap") }, for: .touchUpInside)
            }
            add(button, inset: 2)
        }
    }
    private func add(_ view: UIView, inset: CGFloat = 0) {
        view.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            view.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            view.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset)
        ])
    }
}
