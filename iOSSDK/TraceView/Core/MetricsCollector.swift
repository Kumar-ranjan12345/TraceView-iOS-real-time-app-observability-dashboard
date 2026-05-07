import UIKit

// ─── MetricsCollector ─────────────────────────────────────────────────────────
// Sends memory, CPU, FPS, battery, thermal, disk every second.

class MetricsCollector: NSObject {
    static let shared = MetricsCollector()

    private var timer: Timer?
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0
    private(set) var currentFPS: Double = 60

    private override init() { super.init() }

    func start() {
        startTimer()
        startFPSTracking()
        setupMemoryWarning()
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sendMetrics()
        }
    }

    private func sendMetrics() {
        let mem = SystemInfo.memoryInfo()
        let disk = SystemInfo.diskInfo()
        let device = UIDevice.current

        TraceView.shared.send([
            "type": "metrics",
            "appMemory": mem.appUsed,
            "totalRAM": mem.total,
            "usedRAM": mem.used,
            "freeRAM": mem.free,
            "cpu": SystemInfo.cpuUsage(),
            "fps": currentFPS,
            "threadCount": SystemInfo.threadCount(),
            "batteryLevel": Int(device.batteryLevel * 100),
            "batteryState": SystemInfo.batteryStateString(device.batteryState),
            "thermalState": SystemInfo.thermalStateString(ProcessInfo.processInfo.thermalState),
            "diskTotal": disk.total,
            "diskFree": disk.free,
            "diskUsed": disk.used,
            "appName": Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
            "appBuild": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "",
            "bundleID": Bundle.main.bundleIdentifier ?? "",
            "iosVersion": device.systemVersion,
            "deviceModel": device.model,
            "deviceName": device.name,
            "isSimulator": ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] != nil,
            "networkType": SystemInfo.networkType()
        ])
    }

    private func startFPSTracking() {
        DispatchQueue.main.async {
            self.displayLink = CADisplayLink(target: self, selector: #selector(self.tick))
            self.displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp; return }
        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            frameCount = 0
            lastTimestamp = link.timestamp
        }
    }

    private func setupMemoryWarning() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            let mem = SystemInfo.memoryInfo()
            TraceView.shared.send([
                "type": "memoryWarning",
                "appMemory": mem.appUsed,
                "freeRAM": mem.free,
                "screen": TraceView.shared.currentScreen
            ])
        }
    }
}
