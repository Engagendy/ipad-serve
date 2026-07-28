import CoreImage
import SwiftUI

/// Shown when classroom sharing is on: a QR code students on the same Wi-Fi
/// can scan to open the project's entry page on their own devices.
struct ClassroomShareView: View {
    let projectName: String
    let url: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let url {
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
                        Text("Students on the same Wi-Fi can scan this code to open the book.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    ContentUnavailableView(
                        "Sharing Unavailable",
                        systemImage: "wifi.slash",
                        description: Text("Turn on classroom sharing and make sure the iPad is connected to Wi-Fi.")
                    )
                }
            }
            .navigationTitle(projectName)
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
