import WebKit

enum BilibiliWebConfiguration {
    static func make(dataStore: WKWebsiteDataStore = .default()) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = dataStore
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        // WKWebView omits Safari's Version token by default. The Bilibili home
        // page treats that tokenless user agent as an unsupported old browser.
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion
        let browserMajor = osMajor >= 26 ? osMajor : max(17, osMajor + 3)
        configuration.applicationNameForUserAgent = "Version/\(browserMajor).0 Safari/605.1.15"
        return configuration
    }
}
