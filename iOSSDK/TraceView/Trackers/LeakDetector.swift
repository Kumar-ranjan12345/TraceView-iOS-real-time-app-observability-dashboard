import Foundation

// ─── LeakDetector ─────────────────────────────────────────────────────────────
// Detects ViewControllers retained in memory after being dismissed.

class LeakDetector: NSObject {
    static let shared = LeakDetector()
    private var dismissedAt = [String: Date]()
    private override init() { super.init() }

    func start() {
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func trackDismissed(name: String) {
        dismissedAt[name] = Date()
    }

    private func check() {
        let now = Date()
        for (name, time) in dismissedAt {
            let elapsed = now.timeIntervalSince(time)
            if elapsed > 3.0 {
                let mem = SystemInfo.memoryInfo()
                TraceView.shared.send([
                    "type": "leak",
                    "vcName": name,
                    "retainedFor": Int(elapsed),
                    "memoryAtLeak": mem.appUsed,
                    "screen": TraceView.shared.currentScreen,
                    "suggestion": leakSuggestion(for: name)
                ])
                dismissedAt.removeValue(forKey: name)
                print("🔴 Potential leak: \(name) retained \(Int(elapsed))s after dismiss")
            }
        }
    }

    private func leakSuggestion(for name: String) -> String {
        if name.lowercased().contains("sheet") || name.lowercased().contains("bottom") {
            return "Check for strong delegate references or closures capturing self"
        }
        if name.lowercased().contains("preview") || name.lowercased().contains("photo") {
            return "Check for retained image data or strong closure captures"
        }
        if name.lowercased().contains("qr") || name.lowercased().contains("result") {
            return "Check for timer or observer not removed in deinit"
        }
        return "Check for retain cycles: delegates, closures, NotificationCenter observers"
    }
}
