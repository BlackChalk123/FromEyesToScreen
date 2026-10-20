import Foundation

/// Navigation policy shared by normal links, popups and SPA messages.
public enum BilibiliRoute {
    public static func video(at url: URL) -> BilibiliVideoLink? {
        guard case .video(let link) = try? BilibiliLinkInput.parse(url.absoluteString) else { return nil }
        return link
    }
    public static func key(_ link: BilibiliVideoLink) -> String { "\(link.identifier):\(link.page)" }
    public static func isUnsupportedPlayback(_ url: URL) -> Bool {
        guard BilibiliWebPolicy.isOfficialPage(url) else { return false }
        return url.path.hasPrefix("/bangumi/play/") || url.path.hasPrefix("/cheese/play/") ||
            (url.host == "live.bilibili.com" && url.path.dropFirst().first?.isNumber == true)
    }
    public static func allowsBrowsing(_ url: URL) -> Bool {
        BilibiliWebPolicy.isOfficialPage(url) ||
            (url.scheme == "https" && ["b23.tv", "www.b23.tv"].contains(url.host?.lowercased() ?? "") &&
             url.user == nil && url.password == nil && (url.port == nil || url.port == 443))
    }
}
