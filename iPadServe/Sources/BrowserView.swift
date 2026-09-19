import SwiftUI
import WebKit

struct BrowserView: View {
    private let contentTopInset: CGFloat = 48
    private let fullScreenTopInset: CGFloat = 10
    let page: BrowserPage
    let close: () -> Void
    var goHome: () -> Void = {}
    /// Receives the URL of the currently open page, or nil when it is unknown
    /// so the caller can fall back to the entry page.
    var share: (URL?) -> Void = { _ in }
    /// Incremented by the owner when project files change on disk; the web
    /// view reloads if Auto Reload is on.
    var reloadToken = 0
    @Binding var autoReload: Bool
    @StateObject private var state = WebViewState()
    @StateObject private var console = JSConsoleStore()
    @State private var isFullScreen = false

    var body: some View {
        ZStack(alignment: .top) {
            WebView(url: page.url, state: state, console: console)
                .padding(.top, isFullScreen ? fullScreenTopInset : contentTopInset)
                .padding(.bottom, console.isPanelOpen && !isFullScreen ? 220 : 0)
                .ignoresSafeArea(isFullScreen ? .all : .container, edges: .top)

            if let errorMessage = state.errorMessage {
                ContentUnavailableView(
                    "Page Could Not Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
                .background(.background)
            }

            if isFullScreen {
                FullScreenExitButton {
                    isFullScreen = false
                }
            } else {
                BrowserToolbar(
                    state: state,
                    console: console,
                    isFullScreen: $isFullScreen,
                    autoReload: $autoReload,
                    close: close,
                    goHome: goHome,
                    share: { share(state.webView?.url) }
                )
            }

            if console.isPanelOpen && !isFullScreen {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    JSConsolePanel(console: console) {
                        console.isPanelOpen = false
                    }
                }
            }
        }
        // The navigation bar is hidden by ProjectDetailView, which owns this
        // column's navigation configuration for the whole of its lifetime.
        .statusBarHidden(isFullScreen)
        .onChange(of: reloadToken) { _, _ in
            guard autoReload else { return }
            state.webView?.reload()
        }
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var state: WebViewState
    @ObservedObject var console: JSConsoleStore
    @Binding var isFullScreen: Bool
    @Binding var autoReload: Bool
    let close: () -> Void
    let goHome: () -> Void
    let share: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            BrowserIconButton("Home", systemImage: "house", action: goHome)
                .keyboardShortcut("h", modifiers: [.command, .shift])
            BrowserIconButton("Share QR Code", systemImage: "qrcode", action: share)
            BrowserIconButton("Files", systemImage: "folder", action: close)
                .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()
                .frame(height: 18)

            BrowserIconButton("Back", systemImage: "chevron.left") {
                state.webView?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!state.canGoBack)

            BrowserIconButton("Forward", systemImage: "chevron.right") {
                state.webView?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!state.canGoForward)

            BrowserIconButton("Reload", systemImage: "arrow.clockwise") {
                state.webView?.reload()
            }
            .keyboardShortcut("r", modifiers: .command)

            BrowserIconButton(
                autoReload ? "Auto Reload On" : "Auto Reload Off",
                systemImage: autoReload ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.triangle.2.circlepath.circle"
            ) {
                autoReload.toggle()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .foregroundStyle(autoReload ? Color.accentColor : Color.primary)

            BrowserIconButton("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                isFullScreen = true
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            BrowserIconButton("Console", systemImage: "apple.terminal") {
                console.isPanelOpen.toggle()
            }
            .keyboardShortcut("j", modifiers: [.command, .option])
            .overlay(alignment: .topTrailing) {
                if console.hasUnseenErrors {
                    Circle()
                        .fill(.red)
                        .frame(width: 7, height: 7)
                        .padding(3)
                        .allowsHitTesting(false)
                }
            }

            Spacer(minLength: 0)

            if state.isLoading {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.separator.opacity(0.35))
                .frame(height: 0.5)
        }
    }
}

private struct BrowserIconButton: View {
    let label: String
    let systemImage: String
    let action: () -> Void

    init(_ label: String, systemImage: String, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct FullScreenExitButton: View {
    let action: () -> Void

    var body: some View {
        HStack {
            Spacer()
            Button(action: action) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(.regularMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .accessibilityLabel("Exit Full Screen")
            .padding(8)
        }
    }
}

final class WebViewState: ObservableObject {
    weak var webView: WKWebView?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    func refresh(from webView: WKWebView) {
        canGoBack = webView.canGoBack
        canGoForward = webView.canGoForward
        isLoading = webView.isLoading
    }
}

struct WebView: UIViewRepresentable {
    let url: URL
    @ObservedObject var state: WebViewState
    @ObservedObject var console: JSConsoleStore

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.userContentController.addUserScript(
            WKUserScript(source: JSConsoleStore.captureScript, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        configuration.userContentController.add(context.coordinator, name: JSConsoleStore.messageHandlerName)

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        state.webView = webView
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        state.webView = webView
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state, console: console)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let state: WebViewState
        private let console: JSConsoleStore

        init(state: WebViewState, console: JSConsoleStore) {
            self.state = state
            self.console = console
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == JSConsoleStore.messageHandlerName,
                  let body = message.body as? [String: Any],
                  let levelName = body["level"] as? String,
                  let level = JSConsoleMessage.Level(rawValue: levelName),
                  let text = body["message"] as? String else { return }
            console.append(
                level: level,
                message: text,
                source: body["source"] as? String ?? "",
                line: body["line"] as? Int ?? 0
            )
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.errorMessage = nil
            state.refresh(from: webView)
            console.clear()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if let message = Self.describe(error) {
                state.errorMessage = message
            }
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if let message = Self.describe(error) {
                state.errorMessage = message
            }
            state.refresh(from: webView)
        }

        /// Builds a message that includes the underlying failure reason and the
        /// failing URL, not just WebKit's generic top-level description.
        /// Returns nil for cancelled loads (e.g. tapping a link mid-load).
        private static func describe(_ error: Error) -> String? {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                return nil
            }
            if nsError.domain == "WebKitErrorDomain", nsError.code == 102 { // frame load interrupted
                return nil
            }

            var lines = [nsError.localizedDescription]
            var underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError
            while let current = underlying {
                if !current.localizedDescription.isEmpty, !lines.contains(current.localizedDescription) {
                    lines.append(current.localizedDescription)
                }
                underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError
            }
            if let failingURL = (nsError.userInfo[NSURLErrorFailingURLStringErrorKey] as? String)
                ?? (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.absoluteString {
                lines.append(failingURL)
            }
            lines.append("\(nsError.domain) \(nsError.code)")
            return lines.joined(separator: "\n")
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                completionHandler()
            })
            present(alert, from: webView, fallback: completionHandler)
        }

        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                completionHandler(false)
            })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { _ in
                completionHandler(true)
            })
            present(alert, from: webView, fallback: { completionHandler(false) })
        }

        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { textField in
                textField.text = defaultText
            }
            alert.addAction(UIAlertAction(title: String(localized: "Cancel"), style: .cancel) { _ in
                completionHandler(nil)
            })
            alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default) { [weak alert] _ in
                completionHandler(alert?.textFields?.first?.text ?? "")
            })
            present(alert, from: webView, fallback: { completionHandler(nil) })
        }

        private func present(_ alert: UIAlertController, from webView: WKWebView, fallback: () -> Void) {
            guard var presenter = webView.window?.rootViewController else {
                fallback()
                return
            }
            while let presented = presenter.presentedViewController {
                presenter = presented
            }
            presenter.present(alert, animated: true)
        }
    }
}
