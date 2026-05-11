import UIKit
import Foundation

// ─── TraceView ────────────────────────────────────────────────────────────────
// Entry point. Drop the entire TraceView/ folder into your Xcode project.
// Call TraceView.shared.start() in AppDelegate.didFinishLaunching
//
// Usage:
//   TraceView.shared.start()
//   TraceView.shared.trackEvent("Button tapped", type: "tap")
//   TraceView.shared.trackError("Login failed")
//   TraceView.shared.customActions = [.init(title: "Clear Cache") { ... }]

public class TraceView: NSObject {
    public static let shared = TraceView()

    // ── Configuration ─────────────────────────────────────────────────────────
    // SDK tries each URL in order until one connects.
    public var candidateURLs: [String] = [
        "ws://localhost:4000?type=ios",           // USB cable (Xcode debug)
        "ws://YOUR_MAC_IP:4000?type=ios",         // Same WiFi — replace with Mac IP
        "wss://YOUR_NGROK_URL?type=ios"           // Any network — replace with ngrok URL
    ]

    // ── Custom Debug Actions ──────────────────────────────────────────────────
    public var customActions: [TraceViewAction] = [] {
        didSet { sendCustomActions() }
    }

    public struct TraceViewAction {
        public let title: String
        public let action: () -> Void
        public init(title: String, action: @escaping () -> Void) {
            self.title = title
            self.action = action
        }
    }

    public func runCustomAction(title: String) {
        customActions.first(where: { $0.title == title })?.action()
    }

    private func sendCustomActions() {
        send(["type": "customActions", "actions": customActions.map { $0.title }])
    }

    // ── Internal state ────────────────────────────────────────────────────────
    var currentScreen = ""
    private override init() { super.init() }

    // ── Start ─────────────────────────────────────────────────────────────────
    public func start() {
        signal(SIGPIPE, SIG_IGN)
        let launchStart = Date()

        WebSocketManager.shared.connect(urls: candidateURLs)
        MetricsCollector.shared.start()
        ScreenTracker.shared.start()
        CrashTracker.shared.start()
        TapTracker.shared.start()
        LeakDetector.shared.start()
        DebugInspector.shared.start()
        AppLifecycleTracker.shared.start()
        NetworkTracker.register()
        UIDevice.current.isBatteryMonitoringEnabled = true

        DispatchQueue.main.async {
            let launchMs = Int(Date().timeIntervalSince(launchStart) * 1000)
            self.send([
                "type": "launch",
                "launchMs": launchMs,
                "networkType": SystemInfo.networkType()
            ])
            DebugInspector.shared.sendAll()
            print("⚡ TraceView started — launch: \(launchMs)ms")
        }
    }

    // ── Manual tracking ───────────────────────────────────────────────────────
    public func trackEvent(_ name: String, type: String = "event") {
        send(["type": "event", "eventType": type, "name": name])
    }

    public func trackError(_ error: String) {
        send(["type": "event", "eventType": "error", "name": error])
    }

    // Call from AppDelegate.didRegisterForRemoteNotificationsWithDeviceToken
    public func setAPNSToken(_ deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        AppLifecycleTracker.shared.setAPNSToken(token)
    }

    public func trackWebSocketSent(url: String, message: String) {
        send(["type": "websocket", "direction": "sent", "url": url, "message": String(message.prefix(500))])
    }

    public func trackWebSocketReceived(url: String, message: String) {
        send(["type": "websocket", "direction": "received", "url": url, "message": String(message.prefix(500))])
    }

    public func trackWebSocketConnected(url: String) {
        send(["type": "websocket", "direction": "connected", "url": url, "message": "Connected"])
    }

    public func trackWebSocketDisconnected(url: String, reason: String) {
        send(["type": "websocket", "direction": "disconnected", "url": url, "message": reason])
    }

    // ── Internal send ─────────────────────────────────────────────────────────
    func send(_ dict: [String: Any]) {
        WebSocketManager.shared.send(dict)
    }
}
