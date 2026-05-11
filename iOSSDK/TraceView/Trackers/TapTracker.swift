import UIKit

// ─── TapTracker ───────────────────────────────────────────────────────────────
// Records tap coordinates per screen for heatmap visualization.

class TapTracker: NSObject {
    static let shared = TapTracker()
    private override init() { super.init() }

    func start() {
        DispatchQueue.main.async {
            guard let o = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.sendEvent(_:))),
                  let s = class_getInstanceMethod(UIApplication.self, #selector(UIApplication.tv_sendEvent(_:)))
            else { return }
            method_exchangeImplementations(o, s)
        }
    }

    func recordTap(x: CGFloat, y: CGFloat) {
        let bounds = UIScreen.main.bounds
        TraceView.shared.send([
            "type": "tap",
            "x": Double(x / bounds.width),
            "y": Double(y / bounds.height),
            "screen": TraceView.shared.currentScreen,
            "rawX": Double(x),
            "rawY": Double(y)
        ])
    }
}

extension UIApplication {
    @objc func tv_sendEvent(_ event: UIEvent) {
        tv_sendEvent(event)
        guard event.type == .touches,
              let touch = event.allTouches?.first,
              touch.phase == .began else { return }
        let loc = touch.location(in: nil)
        TapTracker.shared.recordTap(x: loc.x, y: loc.y)
    }
}
