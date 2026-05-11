import Foundation
import UIKit

// ─── CrashReport ──────────────────────────────────────────────────────────────
struct TVCrashReport: Codable {
    let id: String
    let crashType: String
    let name: String
    let reason: String
    let stackTrace: String
    let screen: String
    let appVersion: String
    let deviceInfo: String
    let timestamp: Date

    init(crashType: String, name: String, reason: String, stackTrace: String, screen: String) {
        self.id = UUID().uuidString
        self.crashType = crashType
        self.name = name
        self.reason = reason
        self.stackTrace = stackTrace
        self.screen = screen
        self.appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
        self.deviceInfo = "\(UIDevice.current.model) — iOS \(UIDevice.current.systemVersion)"
        self.timestamp = Date()
    }
}

// ─── CrashTracker ─────────────────────────────────────────────────────────────
class CrashTracker: NSObject {
    static let shared = CrashTracker()
    private var anrTimer: DispatchSourceTimer?
    private var mainThreadPing = true
    private override init() { super.init() }

    func start() {
        setupExceptionHandler()
        setupSignalHandlers()
        startANRDetection()
        sendSavedCrashes()  // send any crashes from previous session
        print("⚡ Crash reporting active")
    }

    // ── Exception Handler ─────────────────────────────────────────────────────
    private func setupExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            let report = TVCrashReport(
                crashType: "exception",
                name: exception.name.rawValue,
                reason: exception.reason ?? "Unknown",
                stackTrace: exception.callStackSymbols.prefix(20).joined(separator: "\n"),
                screen: TraceView.shared.currentScreen
            )
            CrashTracker.shared.saveToDisk(report)
            TraceView.shared.send(report.toDashboardDict())
            Thread.sleep(forTimeInterval: 0.5)
        }
    }

    // ── Signal Handlers ───────────────────────────────────────────────────────
    private func setupSignalHandlers() {
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS]
        signals.forEach { sig in
            signal(sig) { code in
                let names = [SIGABRT:"SIGABRT", SIGILL:"SIGILL", SIGSEGV:"SIGSEGV", SIGFPE:"SIGFPE", SIGBUS:"SIGBUS"]
                let report = TVCrashReport(
                    crashType: "signal",
                    name: names[code] ?? "SIG\(code)",
                    reason: "Fatal signal received",
                    stackTrace: Thread.callStackSymbols.prefix(15).joined(separator: "\n"),
                    screen: TraceView.shared.currentScreen
                )
                CrashTracker.shared.saveToDisk(report)
                TraceView.shared.send(report.toDashboardDict())
                Thread.sleep(forTimeInterval: 0.5)
                signal(code, SIG_DFL)
                raise(code)
            }
        }
    }

    // ── Persist to disk ───────────────────────────────────────────────────────
    private var crashesDir: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("TraceViewCrashes")
    }

    func saveToDisk(_ report: TVCrashReport) {
        guard let dir = crashesDir else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(report.id).json")
        if let data = try? JSONEncoder().encode(report) {
            try? data.write(to: file)
        }
    }

    // Send saved crashes from previous session on next launch
    private func sendSavedCrashes() {
        guard let dir = crashesDir,
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        else { return }

        for file in files where file.pathExtension == "json" {
            guard let data = try? Data(contentsOf: file),
                  let report = try? JSONDecoder().decode(TVCrashReport.self, from: data)
            else { continue }

            var dict = report.toDashboardDict()
            dict["fromPreviousSession"] = true
            TraceView.shared.send(dict)
            try? FileManager.default.removeItem(at: file)  // delete after sending
        }
    }

    // ── ANR Detection ─────────────────────────────────────────────────────────
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

// ── Dashboard dict helper ─────────────────────────────────────────────────────
extension TVCrashReport {
    func toDashboardDict() -> [String: Any] {
        [
            "type": "crash",
            "crashType": crashType,
            "name": name,
            "reason": reason,
            "stackTrace": stackTrace,
            "screen": screen,
            "appVersion": appVersion,
            "deviceInfo": deviceInfo,
            "timestamp": ISO8601DateFormatter().string(from: timestamp)
        ]
    }
}
