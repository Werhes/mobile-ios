//
//  YandexMusicAuthView.swift
//  OpenVK for iOS
//
//  WKWebView для входа в аккаунт Яндекс Музыки. Приложение автоматически
//  «чувствует» успешный вход: перехватывает OAuth-токен из редиректа
//  (access_token в URL) либо извлекает его из localStorage страницы.
//

import SwiftUI
import WebKit

struct YandexMusicAuthView: UIViewRepresentable {

    /// Вызывается при успешном получении токена.
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true

        if let url = URL(string: YandexConstants.oauthAuthorizeURL) {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let onToken: (String) -> Void
        private var didDeliverToken = false

        init(onToken: @escaping (String) -> Void) {
            self.onToken = onToken
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if let urlString = navigationAction.request.url?.absoluteString,
               let token = Self.extractToken(from: urlString) {
                deliver(token)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // После загрузки страницы пробуем вытащить токен из localStorage
            // (веб-версия Яндекс Музыки хранит его там после входа).
            webView.evaluateJavaScript(Self.localStorageScript) { [weak self] value, _ in
                guard let self = self, let payload = value as? String else { return }
                if let token = Self.tokenFromPayload(payload) {
                    self.deliver(token)
                }
            }
        }

        // MARK: - Token extraction

        private func deliver(_ token: String) {
            guard !didDeliverToken else { return }
            didDeliverToken = true
            onToken(token)
        }

        /// Ищем access_token в любой части URL (query или fragment).
        static func extractToken(from urlString: String) -> String? {
            if let token = matchToken(in: urlString) {
                return token
            }
            // Токен может лежать во fragment (#access_token=...), недоступном
            // через URL(string:) queryItems — проверяем по строке напрямую.
            if let range = urlString.range(of: "access_token=") {
                let rest = urlString[range.upperBound...]
                let token = rest.split(whereSeparator: { $0 == "&" || $0 == "#" }).first.map(String.init)
                if let token = YandexMusicService.cleanToken(token) {
                    return token
                }
            }
            return nil
        }

        private static func tokenFromPayload(_ payload: String) -> String? {
            // Сначала ищем явный access_token=
            if let range = payload.range(of: "access_token=") {
                let rest = payload[range.upperBound...]
                let token = rest.split(whereSeparator: { $0 == "&" || $0 == "\n" || $0 == "," })
                    .first.map(String.init)
                if let token = YandexMusicService.cleanToken(token) {
                    return token
                }
            }
            // Иначе ищем любую длинную base64-подобную строку-токен
            let pattern = #"[A-Za-z0-9_\-\.]{25,}"#
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: payload, range: NSRange(payload.startIndex..., in: payload)) {
                let candidate = (payload as NSString).substring(with: match.range)
                return YandexMusicService.cleanToken(candidate)
            }
            return nil
        }

        private static func matchToken(in text: String) -> String? {
            // Полный шаблон access_token=XXX
            let pattern = #"access_token=([A-Za-z0-9_\-\.]+)"#
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
                return nil
            }
            let nsText = text as NSString
            let token = nsText.substring(with: match.range(at: 1))
            return YandexMusicService.cleanToken(token)
        }

        private static let localStorageScript = """
        (function() {
          var out = [];
          try {
            for (var i = 0; i < localStorage.length; i++) {
              var k = localStorage.key(i);
              var v = localStorage.getItem(k);
              if (v) { out.push(k + '=' + v); }
            }
          } catch (e) {}
          return out.join('\\n');
        })();
        """
    }
}