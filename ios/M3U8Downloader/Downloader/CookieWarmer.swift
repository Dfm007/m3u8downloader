import Foundation
import WebKit

@MainActor
final class CookieWarmer: NSObject, WKHTTPCookieStoreObserver {
    static let shared = CookieWarmer()

    private var webView: WKWebView?
    private var completion: (() -> Void)?
    private var warmedHosts: Set<String> = []

    private override init() {
        super.init()
    }

    /// 预热指定 URL 的 Cookie，完成后回调
    func warmUp(url: URL, completion: @escaping () -> Void) {
        guard let host = url.host else {
            completion()
            return
        }

        // 已预热过的主机直接跳过
        if warmedHosts.contains(host) {
            completion()
            return
        }

        self.completion = completion

        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let wv = WKWebView(frame: .zero, configuration: config)
        wv.navigationDelegate = self
        webView = wv

        // 加载站点根地址，触发 Cloudflare 挑战
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.path = "/"
        components?.query = nil
        components?.fragment = nil
        let rootURL = components?.url ?? url

        var request = URLRequest(url: rootURL)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        wv.load(request)

        // 超时兜底：10 秒后无论如何都继续
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            guard let self = self, self.completion != nil else { return }
            self.finishWarmUp(host: host)
        }
    }

    private func finishWarmUp(host: String) {
        warmedHosts.insert(host)
        syncCookiesToURLSession()
        let cb = completion
        completion = nil
        cb?()
    }

    /// 把 WKWebView 的 Cookie 同步到 URLSession 共享存储
    private func syncCookiesToURLSession() {
        guard let webView = webView else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
            for cookie in cookies {
                HTTPCookieStorage.shared.setCookie(cookie)
            }
        }
    }
}

extension CookieWarmer: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard let host = webView.url?.host else { return }
        finishWarmUp(host: host)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard let host = webView.url?.host ?? URL(string: "https://placeholder").flatMap({ $0.host }) else { return }
        finishWarmUp(host: host)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        // 即使加载失败也继续（可能 Cloudflare 挑战完成后 URL 变了）
        if let url = webView.url, let host = url.host {
            finishWarmUp(host: host)
        }
    }
}