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
                TraceView.shared.send([
                    "type": "leak",
                    "vcName": name,
                    "retainedFor": Int(elapsed)
                ])
                dismissedAt.removeValue(forKey: name)
                print("🔴 Potential leak: \(name) retained \(Int(elapsed))s after dismiss")
            }
        }
    }
}
