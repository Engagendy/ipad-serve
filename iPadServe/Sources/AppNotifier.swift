import SwiftUI

/// A transient, non-blocking notice shown as a banner at the top of the app.
struct AppNotice: Identifiable, Equatable {
    enum Kind {
        case error
        case info
    }

    let id = UUID()
    let kind: Kind
    let message: String
}

/// App-wide surface for non-fatal errors (import failures, file copy errors,
/// rename failures, server start failures). Showing a new notice replaces the
/// current one; notices auto-dismiss after a few seconds.
@MainActor
final class AppNotifier: ObservableObject {
    static let shared = AppNotifier()

    @Published private(set) var notice: AppNotice?
    private var dismissTask: Task<Void, Never>?

    func error(_ message: String) {
        show(AppNotice(kind: .error, message: message))
    }

    func info(_ message: String) {
        show(AppNotice(kind: .info, message: message))
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        withAnimation {
            notice = nil
        }
    }

    private func show(_ notice: AppNotice) {
        dismissTask?.cancel()
        withAnimation {
            self.notice = notice
        }
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation {
                self?.notice = nil
            }
        }
    }
}

/// Banner shown by the top-level view; place with `.overlay(alignment: .top)`.
struct AppNoticeBanner: View {
    @ObservedObject private var notifier = AppNotifier.shared

    var body: some View {
        if let notice = notifier.notice {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Image(systemName: notice.kind == .error ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(notice.kind == .error ? Color.orange : Color.blue)
                Text(notice.message)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Button {
                    notifier.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(String(localized: "Dismiss"))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .frame(maxWidth: 560)
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .id(notice.id)
        }
    }
}
