import UIKit

// ─── ScreenTracker ────────────────────────────────────────────────────────────
// Tracks screen transitions via UIViewController swizzling.

class ScreenTracker: NSObject {
    static let shared = ScreenTracker()

    private var screenAppearTime: Date?
    private override init() { super.init() }

    func start() {
        swizzle(UIViewController.self,
                original: #selector(UIViewController.viewDidLoad),
                swizzled: #selector(UIViewController.tv_viewDidLoad))
        swizzle(UIViewController.self,
                original: #selector(UIViewController.viewDidAppear(_:)),
                swizzled: #selector(UIViewController.tv_viewDidAppear(_:)))
        swizzle(UIViewController.self,
                original: #selector(UIViewController.viewDidDisappear(_:)),
                swizzled: #selector(UIViewController.tv_viewDidDisappear(_:)))
    }

    func trackAppear(name: String, loadStart: Date?) {
        let now = Date()
        let transitionMs = loadStart.map { Int(now.timeIntervalSince($0) * 1000) }
        let dwellMs = screenAppearTime.map { Int(now.timeIntervalSince($0) * 1000) }
        screenAppearTime = now
        TraceView.shared.currentScreen = name

        TraceView.shared.send([
            "type": "screen",
            "name": name,
            "transitionMs": transitionMs as Any,
            "dwellMs": dwellMs as Any
        ])

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            DebugInspector.shared.sendAll()
        }
    }

    func trackDismiss(name: String) {
        LeakDetector.shared.trackDismissed(name: name)
    }

    private func swizzle(_ cls: AnyClass, original: Selector, swizzled: Selector) {
        guard let o = class_getInstanceMethod(cls, original),
              let s = class_getInstanceMethod(cls, swizzled) else { return }
        method_exchangeImplementations(o, s)
    }
}

// ── Skipped system VCs ────────────────────────────────────────────────────────
let tvSkipVCs: Set<String> = [
    "UINavigationController", "UITabBarController", "UIInputWindowController",
    "UICompatibilityInputViewController", "UIPredictionViewController",
    "UIKeyboardHiddenViewController", "_UIAlertControllerTextFieldViewController"
]

// ── Per-VC load start time ────────────────────────────────────────────────────
private var tvLoadStartKey = "tvLoadStart"

extension UIViewController {
    var tvLoadStart: Date? {
        get { objc_getAssociatedObject(self, &tvLoadStartKey) as? Date }
        set { objc_setAssociatedObject(self, &tvLoadStartKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    @objc func tv_viewDidLoad() {
        tv_viewDidLoad()
        let name = String(describing: type(of: self))
        guard !tvSkipVCs.contains(name) else { return }
        tvLoadStart = Date()
    }

    @objc func tv_viewDidAppear(_ animated: Bool) {
        tv_viewDidAppear(animated)
        let name = String(describing: type(of: self))
        guard !tvSkipVCs.contains(name) else { return }
        let loadStart = tvLoadStart
        tvLoadStart = nil
        ScreenTracker.shared.trackAppear(name: name, loadStart: loadStart)
    }

    @objc func tv_viewDidDisappear(_ animated: Bool) {
        tv_viewDidDisappear(animated)
        let name = String(describing: type(of: self))
        guard !tvSkipVCs.contains(name) else { return }
        if isBeingDismissed || isMovingFromParent {
            ScreenTracker.shared.trackDismiss(name: name)
        }
    }
}
