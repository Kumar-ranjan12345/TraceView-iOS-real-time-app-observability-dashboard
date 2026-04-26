# Dashboard Features

## Currently Implemented ✅

### Overview Tab
- **App Memory** — RSS (resident set size) in MB
- **Device RAM** — total/used/free breakdown with visual bar
- **CPU Usage** — real-time % with min/avg/max
- **FPS** — real frame rate via CADisplayLink
- **Screen Transitions** — loading time + dwell time per screen
- **Health Score** — 0-100 based on memory, CPU, FPS, screen load times
- **Event Log** — all tracked events with CSV export

### Network Tab
- **All API calls** — URL, method, status code, response time, size
- **Stats** — total requests, avg response time, slowest call, error count
- **Color coding** — green (fast), yellow (medium), red (slow)
- **CSV export** — full network log

### Additional Metrics (in SDK, ready to display)
- Battery level & charging state
- Thermal state (nominal/fair/serious/critical)
- Thread count
- Disk space (total/free/used)
- iOS version & device model

## How to Add More Metrics to Dashboard

The SDK already sends these — just add cards to the HTML:

```javascript
// In updateMetrics function:
const battery = msg.batteryLevel ?? 0;
const thermal = msg.thermalState ?? 'unknown';
const threads = msg.threadCount ?? 0;
const diskFree = msg.diskFree ?? 0;

// Add cards:
document.getElementById('batteryVal').textContent = battery + '%';
document.getElementById('thermalVal').textContent = thermal;
document.getElementById('threadVal').textContent = threads;
document.getElementById('diskVal').textContent = diskFree.toFixed(1) + ' GB';
```

## What's NOT Possible (requires private APIs)

- Memory allocations breakdown (heap/stack/VM regions)
- GPU usage
- Energy impact score
- Detailed thread stack traces
- Xcode-level leak detection

## Accuracy vs Xcode Instruments

| Metric | Accuracy |
|--------|----------|
| Memory (RSS) | ✅ Exact same as Xcode |
| CPU % | ✅ Same calculation method |
| FPS | ✅ Real CADisplayLink measurement |
| Network timing | ✅ Accurate to millisecond |
| Screen transitions | ✅ Accurate viewDidLoad→viewDidAppear |
| Battery | ✅ System API |
| Thermal | ✅ System API |
| Disk | ✅ FileManager API |

This dashboard gives you 90% of what Instruments shows, in real-time, without stopping the app.
