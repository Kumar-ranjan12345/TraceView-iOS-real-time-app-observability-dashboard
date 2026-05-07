import Foundation

// ─── NetworkTracker ───────────────────────────────────────────────────────────
// Intercepts all URLSession calls via URLProtocol.
// Add to your custom URLSession: config.protocolClasses = [TVURLProtocol.self] + ...

class NetworkTracker {
    static func register() {
        URLProtocol.registerClass(TVURLProtocol.self)
    }
}

// ── TVURLProtocol ─────────────────────────────────────────────────────────────
class TVURLProtocol: URLProtocol {
    private var dataTask: URLSessionDataTask?
    private var startTime: Date?

    override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: "TVHandled", in: request) == nil else { return false }
        let url = request.url?.absoluteString ?? ""
        return !url.contains(":4000")  // don't intercept TraceView's own WS
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: "TVHandled", in: mutableRequest)
        startTime = Date()

        let session = URLSession(configuration: .default)
        dataTask = session.dataTask(with: mutableRequest as URLRequest) { [weak self] data, response, error in
            guard let self = self else { return }

            let duration = Int((Date().timeIntervalSince(self.startTime ?? Date())) * 1000)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let size = data?.count ?? 0
            let url = self.request.url?.absoluteString ?? ""
            let method = self.request.httpMethod ?? "GET"
            let headers = self.request.allHTTPHeaderFields ?? [:]
            let action = headers["grpc-method"] ?? headers["x-action"] ?? headers["x-grpc-action"] ?? ""

            TraceView.shared.send([
                "type": "network",
                "url": url,
                "method": method,
                "status": statusCode,
                "duration": duration,
                "size": size,
                "action": action
            ])

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

    override func stopLoading() { dataTask?.cancel() }
}
