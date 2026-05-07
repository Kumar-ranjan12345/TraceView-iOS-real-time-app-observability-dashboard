import Foundation

// ─── WebSocketManager ─────────────────────────────────────────────────────────
// Handles connection, reconnection, and message sending.

class WebSocketManager: NSObject {
    static let shared = WebSocketManager()

    private var ws: URLSessionWebSocketTask?
    private var candidateURLs: [String] = []

    private override init() { super.init() }

    func connect(urls: [String]) {
        candidateURLs = urls
        tryConnect(index: 0)
    }

    private func tryConnect(index: Int) {
        guard index < candidateURLs.count else {
            print("⚡ All URLs failed — retrying in 5s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { self.tryConnect(index: 0) }
            return
        }

        let urlString = candidateURLs[index]
        guard let url = URL(string: urlString) else {
            tryConnect(index: index + 1)
            return
        }

        print("⚡ Trying \(urlString)...")
        let task = URLSession(configuration: .default).webSocketTask(with: url)
        task.resume()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            task.sendPing { [weak self] error in
                guard let self = self else { return }
                if let error = error {
                    print("⚡ ❌ \(urlString) failed: \(error.localizedDescription)")
                    task.cancel()
                    self.tryConnect(index: index + 1)
                } else {
                    print("⚡ ✅ Connected via: \(urlString)")
                    self.ws = task
                    self.receive()
                }
            }
        }
    }

    private func receive() {
        ws?.receive { [weak self] result in
            switch result {
            case .success(let msg):
                if case .string(let str) = msg,
                   let data = str.data(using: .utf8),
                   let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self?.handleIncoming(dict)
                }
                self?.receive()
            case .failure:
                print("⚡ Connection lost — reconnecting...")
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { self?.connect(urls: self?.candidateURLs ?? []) }
            }
        }
    }

    private func handleIncoming(_ dict: [String: Any]) {
        guard let type = dict["type"] as? String else { return }
        if type == "runAction", let title = dict["title"] as? String {
            DispatchQueue.main.async {
                TraceView.shared.runCustomAction(title: title)
            }
        }
    }

    func send(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let str = String(data: data, encoding: .utf8) else { return }
        ws?.send(.string(str)) { _ in }
    }
}
