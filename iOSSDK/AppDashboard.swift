import UIKit
import Foundation

// ─── AppDashboard ─────────────────────────────────────────────────────────────
// Drop into any iOS project. Call AppDashboard.shared.start() in AppDelegate.
// Tracks: memory, CPU, screen transitions, all API calls automatically.

class AppDashboard: NSObject {
    static let shared = AppDashboard()

    private var ws: URLSessionWebSocketTask?
    private var timer: Timer?
    private var currentScreen = ""
    private var screenAppearTime: Date?
    private var screenLoadStartTime: Date?
    
    // FPS tracking
    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0
    private var currentFPS: Double = 60
    // ── Configuration ─────────────────────────────────────────────────────────
    // SDK tries each URL in order until one connects.
    // Configure based on your setup:
    //   - localhost:4000     → USB tunnel (Xcode debug)
    //   - 192.168.x.x:4000  → Same WiFi network
    //   - wss://xxx.ngrok.io → Any network (ngrok tunnel)
    private let candidateURLs: [String] = [
        "ws://localhost:4000?type=ios",
        "ws://172.20.10.9:4000?type=ios",
        "wss://delegator-levitator-unelected.ngrok-free.dev?type=ios"
    ]

    private var currentURLIndex = 0

    private override init() { super.init() }

    func start() {
        connect()
        startMetricsTimer()
        startFPSTracking()
        startANRDetection()
        setupCrashReporting()
        swizzleViewControllers()
        URLProtocol.registerClass(DashboardURLProtocol.self)
        UIDevice.current.isBatteryMonitoringEnabled = true
        print("⚡ TraceView started")
    }

    // ── WebSocket ─────────────────────────────────────────────────────────────
    private func connect() {
        tryConnect(index: 0)
    }

    private func tryConnect(index: Int) {
        guard index < candidateURLs.count else {
            print("📊 All URLs failed — retrying in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.tryConnect(index: 0) }
            return
        }

        let urlString = candidateURLs[index]
        guard let url = URL(string: urlString) else {
            tryConnect(index: index + 1)
            return
        }

        print("📊 Trying \(urlString)...")
        let task = URLSession(configuration: .default).webSocketTask(with: url)
        task.resume()

        // Ping after 1.5s to verify connection
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            task.sendPing { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    print("📊 ❌ \(urlString) failed: \(error.localizedDescription)")
                    task.cancel()
                    self.tryConnect(index: index + 1)
                } else {
                    print("📊 ✅ Connected via: \(urlString)")
                    self.ws = task
                    self.currentURLIndex = index
                    self.receive()
                }
            }
        }
    }

    private func receive() {
        ws?.receive { [weak self] result in
            if case .failure = result {
                print("📊 Connection lost — reconnecting...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.connect() }
            } else { self?.receive() }
        }
    }

    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        ws?.send(.string(str)) { _ in }
    }

    // ── Metrics Timer ─────────────────────────────────────────────────────────
    private func startMetricsTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let mem = self.memoryInfo()
            let disk = self.diskInfo()
            let device = UIDevice.current
            self.send([
                "type": "metrics",
                // Memory
                "appMemory": mem.appUsed,
                "totalRAM": mem.total,
                "usedRAM": mem.used,
                "freeRAM": mem.free,
                // CPU & FPS
                "cpu": self.cpuUsage(),
                "fps": self.currentFPS,
                "threadCount": self.threadCount(),
                // Battery
                "batteryLevel": Int(device.batteryLevel * 100),
                "batteryState": self.batteryStateString(device.batteryState),
                // Thermal
                "thermalState": self.thermalStateString(ProcessInfo.processInfo.thermalState),
                // Disk
                "diskTotal": disk.total,
                "diskFree": disk.free,
                "diskUsed": disk.used,
                // App info
                "appName": Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "App",
                "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
                "iosVersion": device.systemVersion,
                "deviceModel": device.model
            ])
        }
    }

    // ── FPS Tracking ──────────────────────────────────────────────────────────
    private func startFPSTracking() {
        DispatchQueue.main.async {
            self.displayLink = CADisplayLink(target: self, selector: #selector(self.displayLinkTick))
            self.displayLink?.add(to: .main, forMode: .common)
        }
    }

    @objc private func displayLinkTick(_ link: CADisplayLink) {
        if lastTimestamp == 0 { lastTimestamp = link.timestamp; return }
        frameCount += 1
        let elapsed = link.timestamp - lastTimestamp
        if elapsed >= 1.0 {
            currentFPS = Double(frameCount) / elapsed
            print("📊 FPS: \(String(format: "%.1f", currentFPS))")
            frameCount = 0
            lastTimestamp = link.timestamp
        }
    }

    // ── Crash Reporting ───────────────────────────────────────────────────────
    private func setupCrashReporting() {
        // Uncaught exceptions
        NSSetUncaughtExceptionHandler { exception in
            let name = exception.name.rawValue
            let reason = exception.reason ?? "Unknown"
            let symbols = exception.callStackSymbols.prefix(10).joined(separator: "\n")
            AppDashboard.shared.send([
                "type": "crash",
                "crashType": "exception",
                "name": name,
                "reason": reason,
                "stackTrace": symbols
            ])
            // Small delay to let WebSocket send before app dies
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Signal-based crashes (SIGSEGV, SIGABRT etc.)
        let signals = [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGPIPE]
        signals.forEach { sig in
            signal(sig) { signalCode in
                let sigName: String
                switch signalCode {
                case SIGABRT:  sigName = "SIGABRT"
                case SIGILL:   sigName = "SIGILL"
                case SIGSEGV:  sigName = "SIGSEGV"
                case SIGFPE:   sigName = "SIGFPE"
                case SIGBUS:   sigName = "SIGBUS"
                case SIGPIPE:  sigName = "SIGPIPE"
                default:       sigName = "SIG\(signalCode)"
                }
                AppDashboard.shared.send([
                    "type": "crash",
                    "crashType": "signal",
                    "name": sigName,
                    "reason": "Fatal signal received",
                    "stackTrace": ""
                ])
                Thread.sleep(forTimeInterval: 0.5)
                signal(signalCode, SIG_DFL)
                raise(signalCode)
            }
        }
        print("⚡ Crash reporting active")
    }

    // ── ANR Detection (App Not Responding) ────────────────────────────────────
    // Detects main thread hangs > 2 seconds
    private var anrTimer: DispatchSourceTimer?
    private var mainThreadPing = true

    private func startANRDetection() {
        let threshold: TimeInterval = 2.0
        let checkInterval: TimeInterval = 0.5

        // Ping main thread every 0.5s
        Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.mainThreadPing = false
            DispatchQueue.main.async {
                self?.mainThreadPing = true
            }
        }

        // Background thread checks if main thread responded
        let monitor = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .background))
        monitor.schedule(deadline: .now() + threshold, repeating: checkInterval)
        monitor.setEventHandler { [weak self] in
            guard let self = self else { return }
            if !self.mainThreadPing {
                self.send([
                    "type": "anr",
                    "duration": Int(threshold * 1000),
                    "screen": self.currentScreen
                ])
                print("⚡ ANR detected on screen: \(self.currentScreen)")
            }
        }
        monitor.resume()
        anrTimer = monitor
        print("⚡ ANR detection active (threshold: \(Int(threshold * 1000))ms)")
    }
    private func threadCount() -> Int {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS else { return 0 }
        if let list = threadList {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: list)),
                          vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        }
        return Int(threadCount)
    }

    // ── Disk Info ─────────────────────────────────────────────────────────────
    struct DiskInfo { let total, free, used: Double }

    private func diskInfo() -> DiskInfo {
        let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        let total = (attrs?[.systemSize] as? NSNumber)?.doubleValue ?? 0
        let free  = (attrs?[.systemFreeSize] as? NSNumber)?.doubleValue ?? 0
        return DiskInfo(total: total/1_073_741_824, free: free/1_073_741_824, used: (total-free)/1_073_741_824)
    }

    // ── Battery ───────────────────────────────────────────────────────────────
    private func batteryStateString(_ state: UIDevice.BatteryState) -> String {
        switch state {
        case .charging:    return "charging"
        case .full:        return "full"
        case .unplugged:   return "unplugged"
        default:           return "unknown"
        }
    }

    // ── Thermal ───────────────────────────────────────────────────────────────
    private func thermalStateString(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        default:        return "unknown"
        }
    }

    // ── Screen Tracking ───────────────────────────────────────────────────────
    func trackScreenLoadStart(_ name: String) {
        screenLoadStartTime = Date()
    }

    func trackScreenAppear(_ name: String) {
        trackScreenAppearWithTransition(name, transitionMs: nil)
    }

    func trackScreenAppearWithTransition(_ name: String, transitionMs: Int?) {
        let now = Date()
        let dwellMs: Int? = screenAppearTime.map { Int(now.timeIntervalSince($0) * 1000) }
        screenAppearTime = now
        currentScreen = name
        send([
            "type": "screen",
            "name": name,
            "transitionMs": transitionMs as Any,
            "dwellMs": dwellMs as Any
        ])
    }

    // ── API Call Tracking (called by DashboardURLProtocol) ────────────────────
    func trackAPICall(url: String, method: String, statusCode: Int, duration: Int, size: Int, action: String = "") {
        send([
            "type": "network",
            "url": url,
            "method": method,
            "status": statusCode,
            "duration": duration,
            "size": size,
            "action": action   // gRPC action name from proto
        ])
    }

    // ── Manual tracking ───────────────────────────────────────────────────────
    func trackEvent(_ name: String, type: String = "event") {
        send(["type": "event", "eventType": type, "name": name])
    }

    func trackError(_ error: String) {
        send(["type": "event", "eventType": "error", "name": error])
    }

    // ── Swizzle ViewControllers ───────────────────────────────────────────────
    private func swizzleViewControllers() {
        swizzle(UIViewController.self,
                original: #selector(UIViewController.viewDidLoad),
                swizzled: #selector(UIViewController.dashboard_viewDidLoad))
        swizzle(UIViewController.self,
                original: #selector(UIViewController.viewDidAppear(_:)),
                swizzled: #selector(UIViewController.dashboard_viewDidAppear(_:)))
    }

    private func swizzle(_ cls: AnyClass, original: Selector, swizzled: Selector) {
        guard let o = class_getInstanceMethod(cls, original),
              let s = class_getInstanceMethod(cls, swizzled) else { return }
        method_exchangeImplementations(o, s)
    }

    // ── Memory ────────────────────────────────────────────────────────────────
    struct MemoryInfo {
        let appUsed, total, used, free: Double
    }

    func memoryInfo() -> MemoryInfo {
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let appUsed: Double = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        } == KERN_SUCCESS ? Double(taskInfo.resident_size) / 1_048_576 : 0

        let totalRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_048_576

        var vmStats = vm_statistics64()
        var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let freeRAM: Double = withUnsafeMutablePointer(to: &vmStats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
            }
        } == KERN_SUCCESS ? Double(vmStats.free_count) * Double(vm_page_size) / 1_048_576 : 0

        return MemoryInfo(appUsed: appUsed, total: totalRAM, used: totalRAM - freeRAM, free: freeRAM)
    }

    // ── CPU ───────────────────────────────────────────────────────────────────
    func cpuUsage() -> Double {
        var threadList: thread_act_array_t?
        var threadCount: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threadList, &threadCount) == KERN_SUCCESS,
              let threads = threadList else { return 0 }
        var total = 0.0
        let infoCount = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        for i in 0..<Int(threadCount) {
            var info = thread_basic_info()
            var count = infoCount
            let result = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    thread_info(threads[i], thread_flavor_t(THREAD_BASIC_INFO), $0, &count)
                }
            }
            if result == KERN_SUCCESS && info.flags & TH_FLAGS_IDLE == 0 {
                total += Double(info.cpu_usage) / Double(TH_USAGE_SCALE) * 100
            }
        }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadList)),
                      vm_size_t(threadCount) * vm_size_t(MemoryLayout<thread_t>.size))
        return total
    }
}

// ── ViewController Swizzle ────────────────────────────────────────────────────
private let skipVCs: Set<String> = [
    "UINavigationController", "UITabBarController", "UIInputWindowController",
    "UICompatibilityInputViewController", "UIPredictionViewController",
    "UIKeyboardHiddenViewController", "_UIAlertControllerTextFieldViewController"
]

// Per-VC load start time stored via associated object
private var loadStartKey = "dashboardLoadStart"

extension UIViewController {
    private var dashboardLoadStart: Date? {
        get { objc_getAssociatedObject(self, &loadStartKey) as? Date }
        set { objc_setAssociatedObject(self, &loadStartKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @objc func dashboard_viewDidLoad() {
        dashboard_viewDidLoad()
        let name = String(describing: type(of: self))
        guard !skipVCs.contains(name) else { return }
        dashboardLoadStart = Date()
    }

    @objc func dashboard_viewDidAppear(_ animated: Bool) {
        dashboard_viewDidAppear(animated)
        let name = String(describing: type(of: self))
        guard !skipVCs.contains(name) else { return }

        let now = Date()
        let transitionMs = dashboardLoadStart.map { Int(now.timeIntervalSince($0) * 1000) }
        dashboardLoadStart = nil

        AppDashboard.shared.trackScreenAppearWithTransition(name, transitionMs: transitionMs)
    }
}

// ── URLProtocol — intercepts ALL URLSession network calls ─────────────────────
class DashboardURLProtocol: URLProtocol {
    private var startTime: Date?
    private var dataTask: URLSessionDataTask?

    // Intercept everything except our own WebSocket to avoid infinite loop
    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: "DashboardHandled", in: request) == nil else { return false }
        let url = request.url?.absoluteString ?? ""
        return !url.contains("localhost:4000")  // don't intercept dashboard WS
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: "DashboardHandled", in: mutableRequest)

        startTime = Date()

        let session = URLSession(configuration: .default)
        dataTask = session.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            let duration = Int((Date().timeIntervalSince(self.startTime ?? Date())) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let size = data?.count ?? 0
            let url = request.url?.absoluteString ?? ""
            let method = request.httpMethod ?? "GET"

            // Extract gRPC action or any custom action header
            let headers = request.allHTTPHeaderFields ?? [:]
            let action = headers["grpc-method"]
                ?? headers["x-action"]
                ?? headers["x-grpc-action"]
                ?? headers[":path"]  // gRPC uses :path pseudo-header
                ?? ""

            AppDashboard.shared.trackAPICall(
                url: url,
                method: method,
                statusCode: statusCode,
                duration: duration,
                size: size,
                action: action
            )

            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                if let response = response {
                    self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                }
                if let data = data {
                    self.client?.urlProtocol(self, didLoad: data)
                }
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        dataTask?.resume()
    }

    override func stopLoading() {
        dataTask?.cancel()
    }
}
