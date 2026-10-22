import Flutter
import UIKit

public final class CanvasSessionPlugin: NSObject, FlutterPlugin {
    private let vault = CanvasVault()
    private var owned: CanvasWebSession?
    private static var current: CanvasWebSession?

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "offline_course_schedule/canvas_session", binaryMessenger: registrar.messenger())
        let instance = CanvasSessionPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        owned?.cancel()
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        do {
            let args = call.arguments as? [String: Any] ?? [:]
            let state = try vault.read()
            switch call.method {
            case "status":
                let active = state["active"] as? [String: Any] ?? [:]
                var status: [String: Any] = ["enabled": active["enabled"] as? Bool ?? false,
                                            "lastError": state["lastError"] as? String ?? ""]
                for key in ["accountId", "purpose", "expiresAt"] { status[key] = active[key] }
                // No Android battery exemption flag is exposed on iOS.
                result(status)
            case "disable", "clear":
                Self.current?.cancel()
                if call.method == "clear" { try vault.clear() }
                else {
                    try vault.update { value in
                        if var active = value["active"] as? [String: Any] {
                            active["enabled"] = false; value["active"] = active
                        }
                    }
                }
                result(nil)
            case "list", "configure", "prepare":
                guard Self.current == nil else { throw CanvasFailure("busy") }
                var config: [String: Any] = [:]
                if call.method == "configure" {
                    for key in ["accountId", "tokenId", "purpose"] { config[key] = args[key] }
                } else if call.method == "prepare" {
                    guard let active = state["active"] as? [String: Any],
                          active["enabled"] as? Bool == true,
                          active["accountId"] as? String == args["accountId"] as? String else { result(nil); return }
                    config = active
                }
                if call.method != "list" {
                    guard let account = config["accountId"] as? String, account.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                          let tokenId = config["tokenId"] as? String, tokenId.range(of: "^[0-9]+$", options: .regularExpression) != nil,
                          let purpose = config["purpose"] as? String, !purpose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                          purpose.count <= 200 else { throw CanvasFailure("secure_or_config_failed") }
                    let pending = state["pending"] as? [String: Any]
                    let active = state["active"] as? [String: Any]
                    let saved = canvasMatches(pending, config) && pending?["quarantined"] as? Bool != true
                        ? pending : (canvasMatches(active, config) ? active : nil)
                    config["currentToken"] = saved?["token"] as? String ?? ""
                    config["credentialsOnly"] = true
                }
                // WKWebView token rotation requires foreground execution on iOS.
                // During BGTask refresh reuse the last verified token; failed API
                // authentication is recovered by the normal foreground flow.
                if call.method == "prepare", UIApplication.shared.applicationState == .background {
                    guard let token = config["currentToken"] as? String, !token.isEmpty,
                          config["verified"] as? Bool == true else {
                        throw CanvasFailure("login_required")
                    }
                    result(["accountId": config["accountId"] as? String ?? "", "token": token])
                    return
                }
                let session = CanvasWebSession(vault: vault, config: config, mode: call.method) { [weak self] code, value in
                    Self.current = nil
                    self?.owned = nil
                    if let code = code { result(FlutterError(code: code, message: "Canvas 连接维护未完成", details: nil)) }
                    else { result(value) }
                }
                owned = session
                Self.current = session
                session.start()
            default:
                result(FlutterMethodNotImplemented)
            }
        } catch let error as CanvasFailure {
            result(FlutterError(code: error.code, message: "Canvas 连接维护未完成", details: nil))
        } catch {
            result(FlutterError(code: "secure_or_config_failed", message: "本机安全存储或连接设置未完成", details: nil))
        }
    }
}
