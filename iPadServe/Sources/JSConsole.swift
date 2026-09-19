import SwiftUI
import WebKit

struct JSConsoleMessage: Identifiable {
    enum Level: String {
        case log
        case info
        case warn
        case error

        var color: Color {
            switch self {
            case .log: return .primary
            case .info: return .blue
            case .warn: return .orange
            case .error: return .red
            }
        }
    }

    let id = UUID()
    let level: Level
    let message: String
    let source: String
    let line: Int
    let date: Date
}

final class JSConsoleStore: ObservableObject {
    static let messageHandlerName = "iPadServeConsole"
    static let maximumMessageCount = 500

    @Published private(set) var messages: [JSConsoleMessage] = []
    @Published var isPanelOpen = false {
        didSet {
            if isPanelOpen {
                hasUnseenErrors = false
            }
        }
    }
    @Published private(set) var hasUnseenErrors = false

    func append(level: JSConsoleMessage.Level, message: String, source: String, line: Int) {
        messages.append(JSConsoleMessage(level: level, message: message, source: source, line: line, date: Date()))
        if messages.count > Self.maximumMessageCount {
            messages.removeFirst(messages.count - Self.maximumMessageCount)
        }
        if level == .error, !isPanelOpen {
            hasUnseenErrors = true
        }
    }

    func clear() {
        messages.removeAll()
        hasUnseenErrors = false
    }

    static let captureScript = """
    (function() {
        if (window.__iPadServeConsoleInstalled) { return; }
        window.__iPadServeConsoleInstalled = true;
        function send(level, message, source, line) {
            try {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                    level: level,
                    message: String(message),
                    source: String(source || ""),
                    line: Number(line) || 0
                });
            } catch (e) {}
        }
        function format(args) {
            return Array.prototype.map.call(args, function(value) {
                if (value instanceof Error) {
                    return value.stack || (value.name + ": " + value.message);
                }
                if (typeof value === "object" && value !== null) {
                    try { return JSON.stringify(value); } catch (e) { return String(value); }
                }
                return String(value);
            }).join(" ");
        }
        ["log", "info", "warn", "error"].forEach(function(level) {
            var original = console[level];
            console[level] = function() {
                send(level, format(arguments), "", 0);
                if (typeof original === "function") {
                    original.apply(console, arguments);
                }
            };
        });
        window.addEventListener("error", function(event) {
            send("error", event.message || "Script error", event.filename || "", event.lineno || 0);
        });
        window.addEventListener("unhandledrejection", function(event) {
            send("error", "Unhandled promise rejection: " + format([event.reason]), "", 0);
        });
    })();
    """
}

struct JSConsolePanel: View {
    @ObservedObject var console: JSConsoleStore
    let close: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            messageList
        }
        .frame(height: 220)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(.separator.opacity(0.35))
                .frame(height: 0.5)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.terminal")
                .font(.system(size: 12, weight: .semibold))
            Text("Console")
                .font(.system(size: 13, weight: .semibold))

            Spacer(minLength: 0)

            Button(String(localized: "Clear")) {
                console.clear()
            }
            .font(.system(size: 12))
            .disabled(console.messages.isEmpty)

            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Close Console"))
        }
        .padding(.horizontal, 10)
        .frame(height: 32)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if console.messages.isEmpty {
                        Text("No console messages yet.")
                            .font(.system(size: 12).monospaced())
                            .foregroundStyle(.secondary)
                            .padding(10)
                    }
                    ForEach(console.messages) { message in
                        JSConsoleRow(message: message, timestamp: Self.timeFormatter.string(from: message.date))
                            .id(message.id)
                        Divider()
                    }
                }
            }
            .onChange(of: console.messages.last?.id) { _, lastID in
                if let lastID {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }
}

private struct JSConsoleRow: View {
    let message: JSConsoleMessage
    let timestamp: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(timestamp)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(message.message)
                    .foregroundStyle(message.level.color)
                    .textSelection(.enabled)
                if !message.source.isEmpty {
                    Text(location)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 12).monospaced())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .contextMenu {
            Button(String(localized: "Copy"), systemImage: "doc.on.doc") {
                UIPasteboard.general.string = message.message
            }
        }
    }

    private var location: String {
        let fileName = URL(string: message.source)?.lastPathComponent ?? message.source
        return message.line > 0 ? "\(fileName):\(message.line)" : fileName
    }
}
