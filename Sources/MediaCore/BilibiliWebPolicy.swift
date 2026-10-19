import Foundation

public enum BilibiliPlaybackMode: String, CaseIterable, Identifiable {
    case website, embedded
    public var id: String { rawValue }
    public var title: String { self == .website ? "主站播放" : "外链播放" }
    public func url(for link: BilibiliVideoLink) -> URL { self == .website ? link.pageURL : link.embedURL }
}

public enum BilibiliWebPolicy {
    public static let accountURL = URL(string: "https://www.bilibili.com/")!

    public static func isOfficialPage(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.port == nil || url.port == 443 else { return false }
        return host == "bilibili.com" || host.hasSuffix(".bilibili.com")
    }

    public static func isVideoPage(_ url: URL) -> Bool {
        isOfficialPage(url) && ["www.bilibili.com", "bilibili.com"].contains(url.host?.lowercased() ?? "") &&
            url.path.hasPrefix("/video/")
    }
}
