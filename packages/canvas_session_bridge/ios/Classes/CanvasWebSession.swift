import Foundation
import WebKit
import UIKit

final class CanvasWebSession: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private let vault: CanvasVault
    private var config: [String: Any]
    private let mode: String
    private let complete: (String?, [String: Any]?) -> Void
    private let nonce = UUID().uuidString
    private var web: WKWebView?
    private var timeout: DispatchWorkItem?
    private var closed = false
    private var started = false

    init(vault: CanvasVault, config: [String: Any], mode: String,
         complete: @escaping (String?, [String: Any]?) -> Void) {
        self.vault = vault; self.config = config; self.mode = mode; self.complete = complete
        super.init()
    }

    private func trusted(_ url: URL?) -> Bool {
        guard let url = url else { return false }
        return url.scheme == "https" && url.host == "canvas.tongji.edu.cn" && (url.port == nil || url.port == 443)
    }

    func start() {
        let deadline = DispatchWorkItem { [weak self] in self?.finish("login_or_web_timeout") }
        timeout = deadline
        DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: deadline)
        let settings = WKWebViewConfiguration()
        settings.websiteDataStore = .default()
        settings.preferences.javaScriptCanOpenWindowsAutomatically = false
        let controller = WKUserContentController()
        controller.add(self, name: "CanvasLab")
        controller.addUserScript(WKUserScript(source: "window.CanvasLab = {postMessage: function(s) { window.webkit.messageHandlers.CanvasLab.postMessage(s); }};",
                                              injectionTime: .atDocumentStart, forMainFrameOnly: true))
        settings.userContentController = controller
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: settings)
        view.navigationDelegate = self
        view.uiDelegate = self
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        view.alpha = 0.01
        // Keep the private work view attached while a foreground session runs.
        let window = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow)
        window?.rootViewController?.view.addSubview(view)
        web = view
        view.load(URLRequest(url: URL(string: "https://canvas.tongji.edu.cn/profile/settings")!))
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.request.url?.scheme == "https" { decisionHandler(.allow) }
        else { decisionHandler(.cancel); finish("insecure_navigation_blocked") }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, !started, trusted(webView.url), webView.url?.path == "/profile/settings" else { return }
        started = true
        do {
            let containing = Bundle(for: CanvasSessionPlugin.self)
            guard let resourceURL = containing.url(forResource: "canvas_session_bridge_resources", withExtension: "bundle"),
                  let bundle = Bundle(url: resourceURL),
                  let scriptURL = bundle.url(forResource: "canvas_rotation", withExtension: "js") else { throw CanvasFailure("web_setup_failed") }
            let script = try String(contentsOf: scriptURL, encoding: .utf8)
            config["nonce"] = nonce
            let data = try JSONSerialization.data(withJSONObject: config, options: [.fragmentsAllowed])
            guard let json = String(data: data, encoding: .utf8) else { throw CanvasFailure("web_setup_failed") }
            let start = mode == "list" ? "CanvasRotation.startList" : "CanvasRotation.start"
            webView.evaluateJavaScript(script + "\n" + start + "(" + json + ");") { [weak self] _, error in
                if error != nil { self?.finish("web_setup_failed") }
            }
        } catch { finish("web_setup_failed") }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let origin = message.frameInfo.securityOrigin
        guard !closed, message.frameInfo.isMainFrame, trusted(web?.url),
              origin.protocol == "https", origin.host == "canvas.tongji.edu.cn", (origin.port == 0 || origin.port == 443),
              let text = message.body as? String, text.utf8.count <= 65536,
              let data = text.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              value["nonce"] as? String == nonce else { return }
        do {
            switch value["kind"] as? String {
            case "candidate":
                guard let record = value["record"] as? [String: Any], canvasMatches(record, config),
                      let token = record["token"] as? String, validToken(token) else { throw CanvasFailure("secure_save_or_bridge_failed") }
                try vault.update { $0["pending"] = record }
                web?.evaluateJavaScript("window.__canvasLabAck('candidate',true)", completionHandler: nil)
            case "verified":
                try vault.update { state in
                    let pending = state["pending"] as? [String: Any]
                    var record = canvasMatches(pending, config) && pending?["quarantined"] as? Bool != true ? pending! : config
                    if record["token"] == nil { record["token"] = config["currentToken"] }
                    guard let token = record["token"] as? String, validToken(token), canvasMatches(record, config) else { throw CanvasFailure("secure_save_or_bridge_failed") }
                    for key in ["currentToken", "nonce", "credentialsOnly"] { record.removeValue(forKey: key) }
                    record["enabled"] = true; record["verified"] = true
                    state["active"] = record; state["lastError"] = ""; state.removeValue(forKey: "pending")
                }
                web?.evaluateJavaScript("window.__canvasLabAck('verified',true)", completionHandler: nil)
            case "done":
                guard let value = value["result"] as? [String: Any], let status = value["status"] as? String else { throw CanvasFailure("secure_save_or_bridge_failed") }
                guard status == "ok" else { finish(status); return }
                if mode == "list" {
                    guard let account = value["accountId"] as? String,
                          let tokens = value["tokens"] as? [[String: Any]],
                          tokens.allSatisfy({ $0["id"] is String && $0["purpose"] is String }) else { throw CanvasFailure("invalid_list") }
                    finish(nil, result: ["accountId": account, "tokens": tokens.map { ["id": $0["id"]!, "purpose": $0["purpose"]!] }])
                } else {
                    let state = try vault.read()
                    guard let active = state["active"] as? [String: Any], canvasMatches(active, config), active["enabled"] as? Bool == true,
                          let token = active["token"] as? String, validToken(token) else { throw CanvasFailure("secure_save_or_bridge_failed") }
                    finish(nil, result: ["accountId": active["accountId"] as? String ?? "", "token": token])
                }
            default: break
            }
        } catch let error as CanvasFailure { finish(error.code) }
        catch { finish("secure_save_or_bridge_failed") }
    }

    private func validToken(_ token: String) -> Bool {
        token.range(of: "^[A-Za-z0-9._~-]{30,2048}$", options: .regularExpression) != nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish("web_network_error") }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish("web_network_error") }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { finish("web_network_error") }
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        completionHandler(); finish("confirmation_requires_action")
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        completionHandler(false); finish("confirmation_requires_action")
    }
    func cancel() { finish("cancelled") }

    private func finish(_ code: String?, result: [String: Any]? = nil) {
        guard !closed else { return }
        closed = true
        timeout?.cancel(); timeout = nil
        web?.configuration.userContentController.removeScriptMessageHandler(forName: "CanvasLab")
        web?.stopLoading(); web?.navigationDelegate = nil; web?.uiDelegate = nil
        web?.removeFromSuperview(); web = nil
        if let code = code, code != "cancelled" {
            try? vault.update { state in
                state["lastError"] = code
                if ["rotation_identity_or_scope_changed", "wrong_test_token", "account_changed", "bearer_account_changed"].contains(code) {
                    if var active = state["active"] as? [String: Any], canvasMatches(active, config) {
                        active["enabled"] = false; state["active"] = active
                    }
                    if var pending = state["pending"] as? [String: Any], canvasMatches(pending, config) {
                        pending["quarantined"] = true; state["pending"] = pending
                    }
                }
            }
        }
        complete(code, result)
    }
}
