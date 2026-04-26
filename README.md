# TraceView
### iOS Real-time App Observability & Performance Dashboard

> Drop one Swift file into your iOS app. Get a live performance dashboard in your browser — no Xcode Instruments needed.

---

## What is TraceView?

TraceView is a lightweight real-time observability tool for iOS apps. It consists of a single Swift SDK file (`AppDashboard.swift`) that you drop into any iOS project, and a Node.js server that powers a browser-based dashboard.

Once running, you get a live view of everything happening inside your app — memory, CPU, FPS, network calls, screen transitions, crashes, and ANRs — all in one place, shareable with your team.

---

## Features

### Overview Tab
- **App Memory** — RSS usage in MB with peak tracking
- **Device RAM** — total / used / free with visual breakdown bar
- **CPU Usage** — real-time % with min / avg / max over time
- **FPS** — real frame rate via CADisplayLink (not estimated)
- **Battery** — level + charging state
- **Thermal State** — nominal / fair / serious / critical
- **Thread Count** — active threads
- **Disk Usage** — free / total in GB
- **Health Score** — 0–100 score based on memory, CPU, FPS, and screen load times
- **Screen Transitions** — loading time (viewDidLoad → viewDidAppear) + dwell time per screen

### Network Tab
- All API calls intercepted automatically via URLProtocol
- Shows: method, endpoint path, host, status code, response time, response size
- gRPC support — reads action name from request headers
- Stats: total requests, avg response time, slowest call, error count
- Export to CSV

### Crashes Tab
- Uncaught exception reporting with stack trace (first 10 frames)
- Signal crash detection (SIGSEGV, SIGABRT, SIGILL, SIGFPE, SIGBUS)
- ANR detection — alerts when main thread blocks > 2 seconds
- Export to CSV

---

## Project Structure

```
ios-dashboard/
├── iOSSDK/
│   └── AppDashboard.swift     # Drop this into your iOS app
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

Drop `AppDashboard.swift` into your Xcode project, then:

```swift
// AppDelegate.swift
func application(_ application: UIApplication,
                 didFinishLaunchingWithOptions launchOptions: ...) -> Bool {
    AppDashboard.shared.start()
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

### 4. Intercept network calls (optional but recommended)

If your app uses a custom URLSession, inject the protocol:

```swift
let config = URLSessionConfiguration.default
config.protocolClasses = [DashboardURLProtocol.self] + (config.protocolClasses ?? [])
let session = URLSession(configuration: config, delegate: yourDelegate, delegateQueue: nil)
```

### 5. Open dashboard

```
http://localhost:4000
```

---

## Manual Tracking

```swift
AppDashboard.shared.trackEvent("Button tapped", type: "tap")
AppDashboard.shared.trackError("Login failed: invalid token")
```

---

## Connection Modes

| Mode | Requirement | How |
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
| Memory leaks | ❌ | ✅ |
| Flame graphs | ❌ | ✅ |
| GPU profiling | ❌ | ✅ |
| Works without Xcode | ✅ | ❌ |
| Shareable with team | ✅ | ❌ |

TraceView covers ~80% of day-to-day profiling needs without opening Instruments.

---

## Tech Stack

- **SDK** — Swift, CoreFoundation, URLProtocol, CADisplayLink
- **Server** — Node.js, Express, ws (WebSocket)
- **Dashboard** — Vanilla JS, Chart.js, Inter font
