import SwiftUI
import WebKit

struct BrowserView: View {
    private let contentTopInset: CGFloat = 48
    private let fullScreenTopInset: CGFloat = 10
    let page: BrowserPage
    let close: () -> Void
    @StateObject private var state = WebViewState()
    @State private var isFullScreen = false

    var body: some View {
        ZStack(alignment: .top) {
            WebView(url: page.url, state: state)
                .padding(.top, isFullScreen ? fullScreenTopInset : contentTopInset)
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
                    isFullScreen: $isFullScreen,
                    close: close
                )
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(isFullScreen)
    }
}

private struct BrowserToolbar: View {
    @ObservedObject var state: WebViewState
    @Binding var isFullScreen: Bool
    let close: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            BrowserIconButton("Files", systemImage: "folder", action: close)

            Divider()
                .frame(height: 18)

            BrowserIconButton("Back", systemImage: "chevron.left") {
                state.webView?.goBack()
            }
            .disabled(!state.canGoBack)

            BrowserIconButton("Forward", systemImage: "chevron.right") {
                state.webView?.goForward()
            }
            .disabled(!state.canGoForward)

            BrowserIconButton("Reload", systemImage: "arrow.clockwise") {
                state.webView?.reload()
            }

            BrowserIconButton("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right") {
                isFullScreen = true
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

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

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
        Coordinator(state: state)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let state: WebViewState

        init(state: WebViewState) {
            self.state = state
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            state.errorMessage = nil
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            state.errorMessage = error.localizedDescription
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            state.errorMessage = error.localizedDescription
            state.refresh(from: webView)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
            completionHandler()
        }
    }
}
