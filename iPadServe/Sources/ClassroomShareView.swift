import CoreImage
import SwiftUI

/// Always reachable from the QR toolbar buttons. When sharing is off it
/// offers to turn it on; when on, it shows a QR code people on the same
/// Wi-Fi can scan to open the project on their own devices.
struct ClassroomShareView: View {
    @EnvironmentObject private var store: ProjectStore
    @EnvironmentObject private var server: LocalHTTPServer
    let project: ProjectItem
    @Environment(\.dismiss) private var dismiss

    private var shareURL: URL? {
        guard let entry = store.entryPage(for: project) else { return nil }
        return server.lanURL(for: project, file: entry)
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
                        Text(url.absoluteString)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                        Text("People on the same Wi-Fi can scan this code to see the same project.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Text("If others can't connect, allow Local Network access for HTML Serve in Settings > Privacy & Security > Local Network.")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Sharing Unavailable",
                        systemImage: "wifi.slash",
                        description: Text("Make sure the iPad is connected to Wi-Fi.")
                    )
                }
            }
            .navigationTitle(project.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
