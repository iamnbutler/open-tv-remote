import Foundation

/// URLSession setup for talking to TVs on the LAN. TVs serve self-signed certificates,
/// so trust is relaxed — but only for private-network addresses.
class LocalTrustDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        handle(challenge, completionHandler)
    }

    private func handle(_ challenge: URLAuthenticationChallenge,
                        _ completion: (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        if space.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = space.serverTrust, LocalNetwork.isPrivateAddress(space.host) {
            completion(.useCredential, URLCredential(trust: trust))
        } else {
            completion(.performDefaultHandling, nil)
        }
    }
}

enum LocalHTTP {
    static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 4
        config.timeoutIntervalForResource = 8
        config.waitsForConnectivity = false
        return URLSession(configuration: config, delegate: LocalTrustDelegate(), delegateQueue: nil)
    }()

    static func get(_ url: URL, timeout: TimeInterval = 3) async -> Data? {
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        guard let (data, resp) = try? await session.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode ?? 0 < 300 else { return nil }
        return data
    }

    /// Returns the HTTP status code, or nil if the request didn't complete.
    @discardableResult
    static func post(_ url: URL, body: Data? = nil, timeout: TimeInterval = 3) async -> Int? {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body ?? Data()
        req.timeoutInterval = timeout
        guard let (_, resp) = try? await session.data(for: req) else { return nil }
        return (resp as? HTTPURLResponse)?.statusCode
    }
}

/// Tiny helper for pulling a single element's text out of small XML documents.
enum XMLText {
    static func first(_ tag: String, in data: Data) -> String? {
        let s = String(decoding: data, as: UTF8.self)
        guard let open = s.range(of: "<\(tag)>"),
              let close = s.range(of: "</\(tag)>", range: open.upperBound..<s.endIndex) else { return nil }
        let value = s[open.upperBound..<close.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : unescape(value)
    }

    static func unescape(_ s: String) -> String {
        s.replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}
