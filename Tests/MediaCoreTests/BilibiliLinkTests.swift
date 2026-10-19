import Foundation

@main
struct BilibiliLinkTests {
    static func main() throws {
        let id = "BV1B7411m7LV"
        func expect(_ value: Bool) { precondition(value) }
        func video(_ text: String) throws -> BilibiliVideoLink {
            guard case .video(let link) = try BilibiliLinkInput.parse(text) else { fatalError("Expected a direct video") }
            return link
        }
        func rejected(_ text: String) {
            do { _ = try BilibiliLinkInput.parse(text); fatalError("Expected rejection for \(text)") }
            catch {}
        }
        let bare = try video(id)
        precondition(bare.bvid == id && bare.page == 1 && bare.startTime == 0)
        let full = try video("https://www.bilibili.com/video/\(id)/?p=3&t=12.5&share_source=copy_web&vd_source=discard")
        precondition(full.identifier == id && full.page == 3 && full.startTime == 12.5)
        precondition(full.embedURL.host == "player.bilibili.com")
        let query = URLComponents(url: full.embedURL, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.contains(URLQueryItem(name: "p", value: "3")))
        precondition(query.contains(URLQueryItem(name: "autoplay", value: "0")))
        precondition(!full.embedURL.absoluteString.contains("vd_source"))
        precondition(URLComponents(url: full.pageURL, resolvingAgainstBaseURL: false)!.queryItems!.contains(URLQueryItem(name: "t", value: "12.5")))
        precondition(BilibiliPlaybackMode.website.url(for: full) == full.pageURL)
        precondition(BilibiliPlaybackMode.embedded.url(for: full) == full.embedURL)
        for url in ["https://www.bilibili.com/", "https://passport.bilibili.com/", "https://account.bilibili.com/account/homesite"] {
            precondition(BilibiliWebPolicy.isOfficialPage(URL(string: url)!))
        }
        for url in ["https://bilibili.com.evil.test/", "https://evilbilibili.com/", "http://www.bilibili.com/",
                    "https://user@www.bilibili.com/", "https://www.bilibili.com:8443/", "file:///bilibili.com"] {
            precondition(!BilibiliWebPolicy.isOfficialPage(URL(string: url)!))
        }
        precondition(BilibiliWebPolicy.isVideoPage(full.pageURL))
        precondition(!BilibiliWebPolicy.isVideoPage(BilibiliWebPolicy.accountURL))
        try expect(video("m.bilibili.com/video/\(id)").identifier == id)
        try expect(video("https://bilibili.com/video/av386733968?p=2").aid == "386733968")
        try expect(video("av386733968").identifier == "av386733968")
        try expect(video("https://player.bilibili.com/player.html?aid=386733968&cid=794775520").cid == "794775520")
        try expect(video("推荐这个视频！ https://www.bilibili.com/video/\(id)/。 看看").identifier == id)
        try expect(video("http://www.bilibili.com/video/\(id)").embedURL.scheme == "https")
        if case .shortURL(let url) = try BilibiliLinkInput.parse("分享视频 https://b23.tv/AbC123！") {
            precondition(url.absoluteString == "https://b23.tv/AbC123")
        } else { fatalError("Expected a short link") }
        for text in ["", "BV123", "av0", "https://example.com/video/\(id)",
                     "https://www.bilibili.com.evil.example/video/\(id)",
                     "https://user:pass@www.bilibili.com/video/\(id)",
                     "https://www.bilibili.com:8443/video/\(id)",
                     "https://www.bilibili.com/bangumi/play/ep123", "https://live.bilibili.com/1",
                     "https://www.bilibili.com/video/\(id)?p=0", "https://www.bilibili.com/video/\(id)?p=2&p=3",
                     "https://www.bilibili.com/video/\(id)?t=nan", "https://www.bilibili.com/video/\(id)?t=-5",
                     "https://b23.tv/", "file:///video/\(id)", "javascript:alert(1)"] {
            rejected(text)
        }
        print("PASS: Bilibili link checks (9 valid inputs, 16 rejected inputs, clean official embed parameters).")
    }
}
