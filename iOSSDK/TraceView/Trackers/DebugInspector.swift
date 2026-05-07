import UIKit

// ─── DebugInspector ───────────────────────────────────────────────────────────
// UserDefaults, Keychain, VC Stack, Notification log.

class DebugInspector: NSObject {
    static let shared = DebugInspector()
    private override init() { super.init() }

    func start() {
        setupNotificationLog()
    }

    func sendAll() {
        sendUserDefaults()
        sendVCStack()
        sendKeychainItems()
    }

    // ── UserDefaults ──────────────────────────────────────────────────────────
    func sendUserDefaults() {
        let all = UserDefaults.standard.dictionaryRepresentation()
        let filtered = all.filter { k, _ in
            !k.hasPrefix("NS") && !k.hasPrefix("Apple") &&
            !k.hasPrefix("com.apple") && !k.hasPrefix("AK")
        }
        let simplified = filtered.mapValues { v -> String in
            if let s = v as? String { return s }
            if let n = v as? NSNumber { return n.stringValue }
            return "\(v)"
        }
        TraceView.shared.send(["type": "userDefaults", "data": simplified])
    }

    // ── VC Stack ──────────────────────────────────────────────────────────────
    func sendVCStack() {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first?.rootViewController else { return }

        var stack: [String] = []
        func traverse(_ vc: UIViewController, depth: Int) {
            stack.append(String(repeating: "  ", count: depth) + String(describing: type(of: vc)))
            if let nav = vc as? UINavigationController {
                nav.viewControllers.forEach { traverse($0, depth: depth + 1) }
            } else if let tab = vc as? UITabBarController {
                tab.viewControllers?.forEach { traverse($0, depth: depth + 1) }
            } else if let p = vc.presentedViewController {
                traverse(p, depth: depth + 1)
            }
        }
        traverse(root, depth: 0)
        TraceView.shared.send(["type": "vcStack", "stack": stack])
    }

    // ── Keychain ──────────────────────────────────────────────────────────────
    func sendKeychainItems() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let array = result as? [[String: Any]] else {
            TraceView.shared.send(["type": "keychain", "items": []])
            return
        }
        let items = array.map { item -> [String: String] in
            var entry: [String: String] = [:]
            if let a = item[kSecAttrAccount as String] as? String { entry["account"] = a }
            if let s = item[kSecAttrService as String] as? String { entry["service"] = s }
            if let l = item[kSecAttrLabel as String] as? String { entry["label"] = l }
            return entry
        }
        TraceView.shared.send(["type": "keychain", "items": items])
    }

    // ── Notification Log ──────────────────────────────────────────────────────
    private func setupNotificationLog() {
        guard let o = class_getInstanceMethod(NotificationCenter.self,
                  #selector(NotificationCenter.post(name:object:userInfo:))),
              let s = class_getInstanceMethod(NotificationCenter.self,
                  #selector(NotificationCenter.tv_post(name:object:userInfo:)))
        else { return }
        method_exchangeImplementations(o, s)
    }

    func trackNotification(name: String) {
        let skip = ["UITextInputCurrentInputModeDidChange", "UIKeyboardWill", "UIKeyboardDid",
                    "_UIApplicationDidReceiveMemoryWarning", "NSBundle", "UIWindowDidBecomeKey"]
        guard !skip.contains(where: { name.contains($0) }) else { return }
        TraceView.shared.send(["type": "notification", "name": name])
    }
}

extension NotificationCenter {
    @objc func tv_post(name: NSNotification.Name, object: Any?, userInfo: [AnyHashable: Any]?) {
        tv_post(name: name, object: object, userInfo: userInfo)
        DebugInspector.shared.trackNotification(name: name.rawValue)
    }
}
