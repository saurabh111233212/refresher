import SwiftUI
import WebKit

enum RichContent: Equatable {
    case markdown(String, fontSize: CGFloat, centered: Bool)
    /// Question and answer live in one page so revealing is a class toggle, not a new page load.
    case card(question: String, answer: String, deckHex: UInt32, revealed: Bool)
}

/// Markdown + KaTeX, rendered offline from the bundled `web/card.html`, sized to its content.
struct RichText: View {
    let content: RichContent
    @State private var height: CGFloat = 24

    init(markdown: String, fontSize: CGFloat = 17, centered: Bool = false) {
        content = .markdown(markdown, fontSize: fontSize, centered: centered)
    }

    init(card question: String, answer: String, deckHex: UInt32, revealed: Bool) {
        content = .card(question: question, answer: answer, deckHex: deckHex, revealed: revealed)
    }

    var body: some View {
        RichTextWebView(content: content, height: $height)
            .frame(height: height)
    }
}

private struct RichTextWebView: UIViewRepresentable {
    let content: RichContent
    @Binding var height: CGFloat

    /// One shared process pool keeps WebKit warm, so later views skip the cold start the first one pays.
    private static let processPool = WKProcessPool()

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = Self.processPool
        configuration.userContentController.add(context.coordinator, name: "height")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.navigationDelegate = context.coordinator
        let web = Bundle.main.url(forResource: "web", withExtension: nil)!
        webView.loadFileURL(web.appendingPathComponent("card.html"), allowingReadAccessTo: web)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.height = $height
        context.coordinator.show(content, in: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        // The content controller retains its handler; drop it so the coordinator and web view can be freed.
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "height")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var height: Binding<CGFloat>
        private var loaded = false
        private var pending: RichContent?
        private var shown: RichContent?

        init(height: Binding<CGFloat>) { self.height = height }

        func show(_ content: RichContent, in webView: WKWebView) {
            pending = content
            if loaded { flush(webView) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            flush(webView)
        }

        private func flush(_ webView: WKWebView) {
            guard let pending, pending != shown else { return }
            defer { shown = pending }
            switch pending {
            case let .markdown(markdown, fontSize, centered):
                webView.evaluateJavaScript("render(\(literal(markdown)), \(fontSize), \(centered))")
            case let .card(question, answer, deckHex, revealed):
                if case let .card(shownQuestion, shownAnswer, _, _) = shown, shownQuestion == question, shownAnswer == answer {
                    webView.evaluateJavaScript("setRevealed(\(revealed))")
                } else {
                    let color = literal(String(format: "#%06X", deckHex))
                    webView.evaluateJavaScript("renderCard(\(literal(question)), \(literal(answer)), 17, \(color), \(revealed))")
                }
            }
        }

        /// JSON-encoding makes any string a valid JS string literal.
        private func literal(_ text: String) -> String {
            String(decoding: try! JSONEncoder().encode(text), as: UTF8.self)
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let value = message.body as? Double else { return }
            let newHeight = max(CGFloat(value).rounded(.up), 1)
            if abs(newHeight - height.wrappedValue) > 0.5 { height.wrappedValue = newHeight }
        }
    }
}
