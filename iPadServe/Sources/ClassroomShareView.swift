import CoreImage
import SwiftUI

/// Always reachable from the QR toolbar buttons. When sharing is off it
/// offers to turn it on; when on, it shows a QR code people on the same
/// Wi-Fi can scan to open the project on their own devices.
struct ClassroomShareView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    let project: ProjectItem
    var file: ProjectFile? = nil
    @Environment(\.dismiss) private var dismiss

    private var sharedFile: ProjectFile? {
        file ?? store.entryPage(for: project)
    }

    private var shareURL: URL? {
        guard let sharedFile else { return nil }
        return server.lanURL(for: project, file: sharedFile)
    }

    private var localURL: URL? {
        guard let sharedFile else { return nil }
        return server.url(for: project, file: sharedFile)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !server.allowsLAN {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi")
                            .font(.system(size: 44))
                            .foregroundStyle(.tint)
                        Text("Sharing Is Off")
                            .font(.title2.bold())
                        Text("Turn on sharing so people on the same Wi-Fi can open this project on their own devices.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            Task { await server.setLANSharing(true) }
                        } label: {
                            Text("Turn On Sharing")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        if let localURL {
                            Divider()
                                .frame(maxWidth: 240)
                            Text(localURL.absoluteString)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                            CopyLinkButton(url: localURL)
                            Text("This link only works on this iPad. Turn on sharing to let other devices open it.")
                                .font(.footnote)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(32)
                } else if server.lanPermissionDenied {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.orange)
                        Text("Local Network Access Needed")
                            .font(.title2.bold())
                        Text("HTML Serve isn't allowed to use the local network, so other devices can't open this project. Allow Local Network access for HTML Serve in Settings, then come back and share again.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            openSettings()
                        } label: {
                            Text("Open Settings")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(32)
                } else if let url = shareURL {
                    VStack(spacing: 24) {
                        if let qr = Self.qrImage(for: url.absoluteString) {
                            Image(uiImage: qr)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 320)
                                .padding(12)
                                .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        }
                        if let sharedFile, file != nil {
                            Text(sharedFile.relativePath)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        CopyLinkButton(url: url)
                        Text("People on the same Wi-Fi can scan this code to see the same project.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Link("Test This Link in Safari", destination: url)
                            .font(.callout)
                        Text("If others can't connect, allow Local Network access for HTML Serve in Settings > Privacy & Security > Local Network, then quit and reopen the app and scan a fresh code.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Sharing Unavailable",
                            systemImage: "wifi.slash",
                            description: Text("Make sure the iPad is connected to Wi-Fi and that HTML Serve is allowed to use the local network.")
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        Button {
                            openSettings()
                        } label: {
                            Text("Open Settings")
                                .padding(.horizontal, 24)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(32)
                }
            }
            .navigationTitle(file?.name ?? project.name)
            .navigationBarTitleDisplayMode(.inline)
            .task {
                try? await server.ensureRunning()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    static func qrImage(for string: String) -> UIImage? {
        let filter = CIFilter(name: "CIQRCodeGenerator")
        filter?.setValue(Data(string.utf8), forKey: "inputMessage")
        filter?.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter?.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// Copies the share link to the pasteboard and briefly confirms with a checkmark.
private struct CopyLinkButton: View {
    let url: URL
    @State private var isCopied = false

    var body: some View {
        Button {
            UIPasteboard.general.url = url
            withAnimation {
                isCopied = true
            }
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation {
                    isCopied = false
                }
            }
        } label: {
            Label(
                isCopied ? String(localized: "Copied") : String(localized: "Copy Link"),
                systemImage: isCopied ? "checkmark" : "doc.on.doc"
            )
            .frame(minWidth: 120)
        }
        .buttonStyle(.bordered)
        .disabled(isCopied)
    }
}
