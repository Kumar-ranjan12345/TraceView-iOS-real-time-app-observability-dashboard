import UIKit

// ─── AppLifecycleTracker ──────────────────────────────────────────────────────
// Tracks app foreground/background, APNS token, and main thread violations.

class AppLifecycleTracker: NSObject {
    static let shared = AppLifecycleTracker()
    private override init() { super.init() }

    func start() {
        setupLifecycleObservers()
        setupThreadChecker()
    }

    // ── App Lifecycle ─────────────────────────────────────────────────────────
    private func setupLifecycleObservers() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            TraceView.shared.send(["type": "lifecycle", "event": "foreground"])
        }
        nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { _ in
            TraceView.shared.send(["type": "lifecycle", "event": "background"])
        }
        nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            TraceView.shared.send(["type": "lifecycle", "event": "terminate"])
        }
        nc.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main) { _ in
            TraceView.shared.send(["type": "lifecycle", "event": "memoryWarning"])
        }
    }

    // ── APNS Token ────────────────────────────────────────────────────────────
    func setAPNSToken(_ token: String) {
        TraceView.shared.send(["type": "apns", "token": token])
    }

    // ── Thread Checker ────────────────────────────────────────────────────────
    // Detects UIKit calls on background threads
    private func setupThreadChecker() {
        // Swizzle UIView.setNeedsLayout to detect background thread UI calls
        let original = class_getInstanceMethod(UIView.self, #selector(UIView.setNeedsLayout))
        let swizzled = class_getInstanceMethod(UIView.self, #selector(UIView.tv_setNeedsLayout))
        if let o = original, let s = swizzled {
            method_exchangeImplementations(o, s)
        }
    }

    func reportThreadViolation(method: String) {
        let stack = Thread.callStackSymbols.prefix(8).joined(separator: "\n")
        TraceView.shared.send([
            "type": "threadViolation",
            "method": method,
            "screen": TraceView.shared.currentScreen,
            "stackTrace": stack
        ])
        print("⚠️ Main thread violation: \(method) called on background thread")
    }
}

// ── UIView thread check swizzle ───────────────────────────────────────────────
extension UIView {
    @objc func tv_setNeedsLayout() {
        tv_setNeedsLayout()
        if !Thread.isMainThread {
            AppLifecycleTracker.shared.reportThreadViolation(method: "UIView.setNeedsLayout")
        }
    }
}
