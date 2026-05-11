import Foundation

// ─── CrashTracker ─────────────────────────────────────────────────────────────
// Catches uncaught exceptions, signal crashes, and ANRs.

class CrashTracker: NSObject {
    static let shared = CrashTracker()
    private var anrTimer: DispatchSourceTimer?
    private var mainThreadPing = true
    private override init() { super.init() }

    func start() {
        setupExceptionHandler()
        setupSignalHandlers()
        startANRDetection()
        print("⚡ Crash reporting active")
    }

    private func setupExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            TraceView.shared.send([
                "type": "crash",
                "crashType": "exception",
                "name": exception.name.rawValue,
                "reason": exception.reason ?? "Unknown",
                "stackTrace": exception.callStackSymbols.prefix(20).joined(separator: "\n")
            ])
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    private func setupSignalHandlers() {
        [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS].forEach { sig in
            signal(sig) { code in
                let names = [SIGABRT:"SIGABRT", SIGILL:"SIGILL", SIGSEGV:"SIGSEGV", SIGFPE:"SIGFPE", SIGBUS:"SIGBUS"]
                TraceView.shared.send([
                    "type": "crash",
                    "crashType": "signal",
                    "name": names[code] ?? "SIG\(code)",
                    "reason": "Fatal signal received",
                    "stackTrace": ""
                ])
                Thread.sleep(forTimeInterval: 0.5)
                signal(code, SIG_DFL)
                raise(code)
            }
        }
    }

    private func startANRDetection() {
        let threshold: TimeInterval = 2.0
        let interval: TimeInterval = 0.5

        Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.mainThreadPing = false
            DispatchQueue.main.async { self?.mainThreadPing = true }
        }

        let monitor = DispatchSource.makeTimerSource(queue: .global(qos: .background))
        monitor.schedule(deadline: .now() + threshold, repeating: interval)
        monitor.setEventHandler { [weak self] in
            guard let self = self, !self.mainThreadPing else { return }
            var stack = ""
            DispatchQueue.main.sync { stack = Thread.callStackSymbols.prefix(15).joined(separator: "\n") }
            TraceView.shared.send([
                "type": "anr",
                "duration": Int(threshold * 1000),
                "screen": TraceView.shared.currentScreen,
                "stackTrace": stack
            ])
            print("⚡ ANR detected on: \(TraceView.shared.currentScreen)")
        }
        monitor.resume()
        anrTimer = monitor
        print("⚡ ANR detection active (threshold: \(Int(threshold * 1000))ms)")
    }
}
