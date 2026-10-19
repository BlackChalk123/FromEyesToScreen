import Foundation

public struct BilibiliVideoLink: Equatable {
    public let bvid: String?
    public let aid: String?
    public let cid: String?
    public let page: Int
    public let startTime: Double

    public var identifier: String { bvid ?? "av\(aid ?? "")" }
    public var title: String { "哔哩哔哩 · \(identifier)" + (page > 1 ? " · P\(page)" : "") }
    public var embedURL: URL {
        var components = URLComponents(string: "https://player.bilibili.com/player.html")!
        var query = [URLQueryItem(name: bvid != nil ? "bvid" : "aid", value: bvid ?? aid),
                     URLQueryItem(name: "p", value: String(page)),
                     URLQueryItem(name: "autoplay", value: "0"),
                     URLQueryItem(name: "muted", value: "0"),
                     URLQueryItem(name: "danmaku", value: "1")]
        if let cid { query.append(URLQueryItem(name: "cid", value: cid)) }
        if startTime > 0 { query.append(URLQueryItem(name: "t", value: String(startTime))) }
        components.queryItems = query
        return components.url!
    }
    public var pageURL: URL {
        var components = URLComponents(string: "https://www.bilibili.com/video/\(identifier)/")!
        components.queryItems = [URLQueryItem(name: "p", value: String(page))]
        if startTime > 0 { components.queryItems?.append(URLQueryItem(name: "t", value: String(startTime))) }
        return components.url!
    }

    fileprivate init(id: String, query: [String: String] = [:]) throws {
        if Self.matches(id, pattern: "^BV[A-Za-z0-9]{10}$") {
            bvid = id; aid = nil
        } else if id.lowercased().hasPrefix("av"), let value = Self.positiveID(String(id.dropFirst(2))) {
            aid = value; bvid = nil
        } else { throw BilibiliLinkError.invalidVideo }
        if let value = query["p"] {
            guard let number = Int(value), (1...10000).contains(number) else { throw BilibiliLinkError.invalidPage }
            page = number
        } else { page = 1 }
        if let value = query["t"] {
            guard let seconds = Double(value), seconds.isFinite, (0...31_536_000).contains(seconds) else {
                throw BilibiliLinkError.invalidTime
            }
            startTime = seconds
        } else { startTime = 0 }
        if let value = query["cid"] {
            guard let number = Self.positiveID(value) else { throw BilibiliLinkError.invalidVideo }
            cid = number
        } else { cid = nil }
    }

    fileprivate static func positiveID(_ value: String) -> String? {
        guard matches(value, pattern: "^[0-9]+$"), let number = UInt64(value), number > 0 else { return nil }
        return String(number)
    }
    fileprivate static func matches(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}

public enum BilibiliLinkInput: Equatable {
    case video(BilibiliVideoLink)
    case shortURL(URL)

    public static func parse(_ input: String) throws -> Self {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text.count < 8192 else { throw BilibiliLinkError.invalidVideo }
        if BilibiliVideoLink.matches(text, pattern: "^BV[A-Za-z0-9]{10}$") ||
            BilibiliVideoLink.matches(text, pattern: "^[aA][vV][0-9]+$") {
            return .video(try BilibiliVideoLink(id: text))
        }
        var candidate = text
        if let range = text.range(of: "https?://[^\\s<>]+", options: [.regularExpression, .caseInsensitive]) {
            candidate = String(text[range]).trimmingCharacters(in: CharacterSet(charactersIn: "，。；！、）】》」』,;!)]>\""))
        } else if !candidate.contains("://") { candidate = "https://" + candidate }
        guard let components = URLComponents(string: candidate),
              let host = components.host?.lowercased(),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              components.port == nil || components.port == 443 else { throw BilibiliLinkError.invalidVideo }
        let shortHosts = ["b23.tv", "www.b23.tv"]
        let fullHosts = ["www.bilibili.com", "bilibili.com", "m.bilibili.com", "player.bilibili.com"]
        guard shortHosts.contains(host) || fullHosts.contains(host) else { throw BilibiliLinkError.unsupportedHost }
        var secure = components
        secure.scheme = "https"
        guard let url = secure.url else { throw BilibiliLinkError.invalidVideo }
        if shortHosts.contains(host) {
            guard components.path.count > 1 else { throw BilibiliLinkError.invalidVideo }
            return .shortURL(url)
        }
        let relevantKeys = Set(["bvid", "aid", "cid", "p", "t"])
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where relevantKeys.contains(item.name) {
            guard query[item.name] == nil, let value = item.value else { throw BilibiliLinkError.invalidVideo }
            query[item.name] = value
        }
        if host == "player.bilibili.com", components.path == "/player.html" {
            if let bvid = query["bvid"] { return .video(try BilibiliVideoLink(id: bvid, query: query)) }
            if let aid = query["aid"] { return .video(try BilibiliVideoLink(id: "av" + aid, query: query)) }
            throw BilibiliLinkError.unsupportedContent
        }
        let path = components.path.split(separator: "/")
        guard path.count == 2, path[0] == "video" else { throw BilibiliLinkError.unsupportedContent }
        return .video(try BilibiliVideoLink(id: String(path[1]), query: query))
    }
}

public enum BilibiliLinkError: LocalizedError {
    case invalidVideo, unsupportedHost, unsupportedContent, invalidPage, invalidTime, shortLinkFailed
    public var errorDescription: String? {
        switch self {
        case .invalidVideo: return "没有识别到有效视频。请粘贴 B 站视频链接或完整 BV / av 号。"
        case .unsupportedHost: return "请使用 bilibili.com 或 b23.tv 的视频链接。"
        case .unsupportedContent: return "这一版支持普通投稿视频；番剧、直播、收藏夹等链接暂不支持。"
        case .invalidPage: return "分 P 参数无效，请使用从 1 开始的分集序号。"
        case .invalidTime: return "起播时间无效，请使用以秒为单位的 t 参数。"
        case .shortLinkFailed: return "未能解析 B 站短链接，请尝试复制浏览器中的完整视频链接。"
        }
    }
}
