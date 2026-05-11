# TraceView
### iOS Real-time App Observability & Performance Dashboard

> Add via Swift Package Manager or drag the folder. Get a live performance dashboard in your browser — no Xcode Instruments needed.

---

## What is TraceView?

TraceView is a lightweight real-time observability tool for iOS apps. It consists of a modular Swift SDK that you add to any iOS project, and a Node.js server that powers a browser-based dashboard.

Once running, you get a live view of everything happening inside your app — memory, CPU, FPS, network calls, screen transitions, crashes, ANRs, console logs, UserDefaults, tap heatmaps, and more — all in one place, shareable with your team.

---

## Installation

### Option 1 — Swift Package Manager (Recommended)

In Xcode → **File → Add Package Dependencies** → paste:

```
https://github.com/Kumar-ranjan12345/TraceView-iOS-real-time-app-observability-dashboard
```

Select version `1.0.0` → Add Package.

### Option 2 — Drag & Drop

Drag the entire `ios-dashboard/iOSSDK/TraceView/` folder into your Xcode project (check "Copy items if needed").

---

## Dashboard Tabs

### ⚡ Overview
- **App Memory** — RSS usage in MB with peak tracking and mini progress bar
- **Device RAM** — total / used / free with visual breakdown bar
- **CPU Usage** — real-time % with min / avg / max over time
- **FPS** — real frame rate via CADisplayLink (not estimated)
- **Current Screen** — active ViewController with live timer
- **Charts** — memory history + CPU usage with crosshair tooltips on hover
- **Device RAM Breakdown** — color-coded bar (This App / Other / Free)
- **Device & App Info** — app name, version/build, bundle ID, environment (Simulator/Device), device model, iOS version, network type
- **Screen Transitions** — loading time (viewDidLoad→viewDidAppear) + dwell time per screen with ACTIVE/CLOSED/LATENCY badges
- **Event Log** — chronological log with colored left border per event type

### 🌐 Network
- All API calls intercepted automatically via URLProtocol
- Click any row to expand — shows request headers, response headers, response body (JSON formatted)
- Method badges (GET/POST/PUT/DELETE) with color coding
- Status code, response time (green/yellow/red), response size
- gRPC support — reads action name from request headers
- Stats: total requests, avg response time, slowest call, error count
- Search/filter requests
- Export to CSV

### 💥 Crashes
- Uncaught exception reporting with stack trace (first 15 frames)
- Signal crash detection (SIGSEGV, SIGABRT, SIGILL, SIGFPE, SIGBUS)
- ANR detection — alerts when main thread blocks > 2 seconds with stack trace
- **Crash persistence** — crashes saved to disk, sent on next launch even if app was killed
- Memory Leak Detector — ViewControllers retained after dismiss with How to Fix guidance
- Click to expand — shows memory/CPU snapshot at crash time, last 5 events before crash, full stack trace
- Copy Report + Export JSON per crash

### 📊 Analytics (Mixpanel-style)
- **Tap Heatmap** — visual heat dots showing where users tap per screen
- **User Flow** — numbered sequence of every screen visited with timestamps and dwell time
- **Screen Engagement** — horizontal bar chart of time spent per screen
- **Session stats** — total taps, unique screens, session duration, avg screen time

### 🐛 Debug
- **Console Log Viewer** — captures `print()` output, filter by All/Error/Warn
- **View Controller Stack** — live navigation hierarchy with depth colors
- **UserDefaults Inspector** — all app key-value pairs with search/filter
- **Keychain Inspector** — stored keychain items (keys only, not values)
- **WebSocket Inspector** — WS messages sent/received this session
- **Notification Center Log** — every `NotificationCenter.post` event
- **APNS Token** — push notification device token (click to copy)
- **Thread Violations** — UIKit called on background thread with stack trace
- **Custom Debug Actions** — register your own buttons via `TraceView.shared.customActions`

---

## Additional Tracking

- **Launch time** — cold start time shown as toast banner on connect
- **Memory warnings** — logged with memory snapshot, flashes memory card red
- **Network type** — WiFi / cellular / offline, updates every second
- **Battery level + state** — charging/full/unplugged
- **Thermal state** — nominal/fair/serious/critical
- **Thread count** — active threads
- **Disk usage** — free / total in GB
- **App lifecycle** — foreground/background/terminate events

---

## Project Structure

```
TraceView-iOS-real-time-app-observability-dashboard/
├── Package.swift                        # SPM package definition
├── ios-dashboard/
│   ├── iOSSDK/
│   │   └── TraceView/                   # SDK source (used by Package.swift)
│   │       ├── TraceView.swift          # Entry point — public API
│   │       ├── Core/
│   │       │   ├── WebSocketManager.swift
│   │       │   ├── MetricsCollector.swift
│   │       │   └── SystemInfo.swift
│   │       └── Trackers/
│   │           ├── ScreenTracker.swift
│   │           ├── NetworkTracker.swift
│   │           ├── CrashTracker.swift
│   │           ├── TapTracker.swift
│   │           ├── LeakDetector.swift
│   │           ├── DebugInspector.swift
│   │           └── AppLifecycleTracker.swift
│   ├── server/
│   │   ├── index.js                     # Node.js WebSocket server
│   │   └── package.json
│   └── dashboard/
│       └── index.html                   # Browser dashboard
└── README.md
```

---

## Setup

### 1. Start the server

```bash
cd ios-dashboard/server
npm install
node index.js
# Server runs at http://localhost:4000
```

### 2. Add to your iOS app

```swift
// AppDelegate.swift
import TraceView  // if using SPM

func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: ...) -> Bool {

    TraceView.shared.candidateURLs = [
        "ws://localhost:4000?type=ios",        // USB cable (Xcode debug)
        "ws://YOUR_MAC_IP:4000?type=ios",      // Same WiFi
        "wss://YOUR_NGROK_URL?type=ios"        // Any network via ngrok
    ]
    TraceView.shared.start()
    return true
}
```

Add to `Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

### 3. Intercept network calls

If your app uses a custom URLSession, inject the protocol:

```swift
let config = URLSessionConfiguration.default
config.protocolClasses = [TVURLProtocol.self] + (config.protocolClasses ?? [])
let session = URLSession(configuration: config, delegate: yourDelegate, delegateQueue: nil)
```

### 4. Open dashboard

```
http://localhost:4000
```

---

## Connection Modes

| Mode | Requirement | URL |
|------|------------|-----|
| USB | iPhone connected via cable, Xcode open | `ws://localhost:4000` |
| WiFi | Same network | `ws://MAC_IP:4000` |
| ngrok | Any network | `wss://xxx.ngrok-free.app` |

The SDK tries each URL in order — put fastest first.

---

## Manual Tracking

```swift
TraceView.shared.trackEvent("Button tapped", type: "tap")
TraceView.shared.trackError("Login failed: invalid token")

// APNS token
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    TraceView.shared.setAPNSToken(token)
}

// WebSocket tracking
TraceView.shared.trackWebSocketConnected(url: "wss://api.example.com/ws")
TraceView.shared.trackWebSocketSent(url: "wss://api.example.com/ws", message: payload)
TraceView.shared.trackWebSocketReceived(url: "wss://api.example.com/ws", message: response)

// Custom debug actions (appear in Debug tab)
TraceView.shared.customActions = [
    .init(title: "Clear Cache") { URLCache.shared.removeAllCachedResponses() },
    .init(title: "Reset Defaults") {
        UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
    }
]
```

---

## Accuracy vs Xcode Instruments

| Metric | TraceView | Instruments |
|--------|-----------|-------------|
| Memory (RSS) | ✅ Exact | ✅ Exact |
| CPU % | ✅ Same method | ✅ Hardware counters |
| FPS | ✅ CADisplayLink | ✅ CADisplayLink |
| Network calls + body | ✅ URLProtocol | ✅ Full stack |
| Screen timing | ✅ viewDidLoad→Appear | ✅ Same |
| Crash + ANR | ✅ Yes | ✅ Yes |
| Crash persistence | ✅ Yes | ✅ Yes |
| Console logs | ✅ Yes | ✅ Yes |
| UserDefaults | ✅ Yes | ❌ No |
| Keychain inspector | ✅ Yes | ❌ No |
| Tap heatmap | ✅ Yes | ❌ No |
| User flow | ✅ Yes | ❌ No |
| Memory leak detector | ✅ Yes | ✅ Yes |
| Thread violations | ✅ Yes | ✅ Yes |
| Memory leaks (heap) | ❌ | ✅ |
| Flame graphs | ❌ | ✅ |
| GPU profiling | ❌ | ✅ |
| Works without Xcode | ✅ | ❌ |
| Shareable with team | ✅ | ❌ |

TraceView covers ~85% of day-to-day profiling and debugging needs without opening Instruments.

---

## Tech Stack

- **SDK** — Swift, CoreFoundation, URLProtocol, CADisplayLink, SystemConfiguration
- **Server** — Node.js, Express, ws (WebSocket)
- **Dashboard** — Vanilla JS, Chart.js, Inter font, glassmorphism UI
