# TraceView
### iOS Real-time App Observability & Performance Dashboard

> Drop one Swift file into your iOS app. Get a live performance dashboard in your browser — no Xcode Instruments needed.

---

## What is TraceView?

TraceView is a lightweight real-time observability tool for iOS apps. It consists of a single Swift SDK file (`AppDashboard.swift`) that you drop into any iOS project, and a Node.js server that powers a browser-based dashboard.

Once running, you get a live view of everything happening inside your app — memory, CPU, FPS, network calls, screen transitions, crashes, ANRs, console logs, UserDefaults, and more — all in one place, shareable with your team.

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
- Click to expand — shows memory/CPU snapshot at crash time, last 5 events before crash, full stack trace
- Copy Report + Export JSON per crash
- Export all crashes to CSV

### 📊 Analytics (Mixpanel-style)
- **Tap Heatmap** — visual heat dots showing where users tap per screen
- **User Flow** — numbered sequence of every screen visited with timestamps and dwell time
- **Screen Engagement** — horizontal bar chart of time spent per screen
- **Session stats** — total taps, unique screens, session duration, avg screen time

### 🐛 Debug
- **Console Log Viewer** — captures `print()` output from the app, streamed live. Filter by All/Error/Warn. Clear button
- **View Controller Stack** — live navigation hierarchy showing current VC tree
- **UserDefaults Inspector** — all app key-value pairs with search/filter
- **Notification Center Log** — every `NotificationCenter.post` event

---

## Additional Tracking

- **Launch time** — cold start time shown as toast banner on connect
- **Memory warnings** — logged with memory snapshot, flashes memory card red
- **Network type** — WiFi / cellular / offline, updates every second
- **Battery level + state** — charging/full/unplugged
- **Thermal state** — nominal/fair/serious/critical
- **Thread count** — active threads
- **Disk usage** — free / total in GB

---

## Project Structure

```
ios-dashboard/
├── iOSSDK/
│   └── TraceView/                    # Drop this entire folder into your Xcode project
│       ├── TraceView.swift           # Entry point — public API, start(), customActions
│       ├── Core/
│       │   ├── WebSocketManager.swift  # Connection, reconnection, message sending
│       │   ├── MetricsCollector.swift  # Memory, CPU, FPS, battery, thermal, disk
│       │   └── SystemInfo.swift        # Static system helpers (networkType, memoryInfo etc)
│       └── Trackers/
│           ├── ScreenTracker.swift     # Screen transitions, load time, dwell time
│           ├── NetworkTracker.swift    # URLProtocol interceptor (TVURLProtocol)
│           ├── CrashTracker.swift      # Uncaught exceptions, signals, ANR detection
│           ├── TapTracker.swift        # Tap heatmap coordinates
│           ├── LeakDetector.swift      # ViewController leak detection
│           └── DebugInspector.swift    # UserDefaults, Keychain, VC Stack, Notifications
├── server/
│   ├── index.js               # Node.js WebSocket server
│   └── package.json
├── dashboard/
│   └── index.html             # Browser dashboard (served by server)
└── README.md
```

---

## Setup

### 1. Start the server

```bash
cd server
npm install
npm start
# Server runs at http://localhost:4000
```

### 2. Configure connection in AppDashboard.swift

The SDK tries each URL in order until one connects:

```swift
private let candidateURLs: [String] = [
    "ws://localhost:4000?type=ios",        // USB cable (Xcode debug)
    "ws://YOUR_MAC_IP:4000?type=ios",      // Same WiFi network
    "wss://YOUR_NGROK_URL?type=ios"        // Any network via ngrok
]
```

**USB (recommended):** Connect iPhone via USB, run via Xcode — no shared network needed.

**WiFi:** Find Mac IP with `ipconfig getifaddr en0`, replace above.

**ngrok (any network):**
```bash
brew install ngrok
ngrok http 4000
# Copy the wss:// URL into candidateURLs
```

### 3. Add to your iOS app

Drag the entire `iOSSDK/TraceView/` folder into your Xcode project (check "Copy items if needed"), then:

```swift
// AppDelegate.swift
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

### 4. Intercept network calls

If your app uses a custom URLSession, inject the protocol:

```swift
let config = URLSessionConfiguration.default
config.protocolClasses = [TVURLProtocol.self] + (config.protocolClasses ?? [])
let session = URLSession(configuration: config, delegate: yourDelegate, delegateQueue: nil)
```

### 5. Open dashboard

```
http://localhost:4000
```

---

## Manual Tracking

```swift
TraceView.shared.trackEvent("Button tapped", type: "tap")
TraceView.shared.trackError("Login failed: invalid token")

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

## Connection Modes

| Mode | Requirement | URL |
|------|------------|-----|
| USB | iPhone connected via cable, Xcode open | `ws://localhost:4000` |
| WiFi | Same network | `ws://MAC_IP:4000` |
| ngrok | Any network | `wss://xxx.ngrok-free.app` |

---

## Accuracy vs Xcode Instruments

| Metric | TraceView | Instruments |
|--------|-----------|-------------|
| Memory (RSS) | ✅ Exact | ✅ Exact |
| CPU % | ✅ Same method | ✅ Hardware counters |
| FPS | ✅ CADisplayLink | ✅ CADisplayLink |
| Network calls | ✅ URLProtocol | ✅ Full stack |
| Screen timing | ✅ viewDidLoad→Appear | ✅ Same |
| Crash + ANR | ✅ Yes | ✅ Yes |
| Console logs | ✅ Yes | ✅ Yes |
| UserDefaults | ✅ Yes | ❌ No |
| Tap heatmap | ✅ Yes | ❌ No |
| User flow | ✅ Yes | ❌ No |
| Memory leaks | ❌ | ✅ |
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
