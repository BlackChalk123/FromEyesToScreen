import Foundation

/// Short links use a temporary session and never read the user's browser cookies.
public final class BilibiliLinkResolver: NSObject, URLSessionTaskDelegate {
    public func resolve(_ text: String) async throws -> BilibiliVideoLink {
        switch try BilibiliLinkInput.parse(text) {
        case .video(let link): return link
        case .shortURL(let url):
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 15
            configuration.timeoutIntervalForResource = 20
            configuration.httpCookieAcceptPolicy = .never
            let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<400).contains(http.statusCode),
                  let resolved = response.url,
                  case .video(let link) = try BilibiliLinkInput.parse(resolved.absoluteString) else {
                throw BilibiliLinkError.shortLinkFailed
            }
            return link
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask,
                           willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                           completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil,
              url.port == nil || url.port == 443,
              ["b23.tv", "www.b23.tv", "bilibili.com", "www.bilibili.com", "m.bilibili.com"].contains(url.host?.lowercased() ?? "") else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
