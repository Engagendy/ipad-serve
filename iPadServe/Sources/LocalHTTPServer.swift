import Foundation
import Network

@MainActor
final class LocalHTTPServer: ObservableObject {
    @Published private(set) var port: UInt16?
    @Published private(set) var isRunning = false

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.engagendy.HTMLServe.http")

    func start() async throws {
        if isRunning, port != nil, listener != nil { return }

        if listener != nil {
            stop()
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        listener.service = nil
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let listener else { return }
            Task { @MainActor in
                guard let self, self.listener === listener else { return }

                switch state {
                case .ready:
                    self.port = listener.port?.rawValue
                    self.isRunning = listener.port != nil
                case .waiting:
                    self.port = nil
                    self.isRunning = false
                case .failed, .cancelled:
                    self.listener = nil
                    self.port = nil
                    self.isRunning = false
                default:
                    break
                }
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        self.listener = listener
        listener.start(queue: queue)
    }

    func ensureRunning() async throws {
        if isRunning, port != nil, listener != nil { return }
        try await start()
    }

    func restart() async throws {
        stop()
        try await start()
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        isRunning = false
    }

    func url(for project: ProjectItem, file: ProjectFile) -> URL? {
        guard let port else { return nil }
        let encodedRoot = Self.urlSafeBase64(project.rootURL.path)
        let encodedFile = file.relativePath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "http://localhost:\(port)/file/\(encodedRoot)/\(encodedFile)")
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                var nextBuffer = buffer
                nextBuffer.append(data)

                if nextBuffer.range(of: Data("\r\n\r\n".utf8)) != nil {
                    self.respond(to: nextBuffer, on: connection)
                    return
                }

                self.receive(on: connection, buffer: nextBuffer)
                return
            }

            if isComplete || error != nil {
                connection.cancel()
            }
        }
    }

    private nonisolated func respond(to requestData: Data, on connection: NWConnection) {
        guard let rawRequest = String(data: requestData, encoding: .utf8),
              let request = HTTPRequest(rawRequest: rawRequest) else {
            send(status: 400, headers: [:], body: Data("Bad Request".utf8), on: connection)
            return
        }

        guard request.method == "GET" || request.method == "HEAD" else {
            send(status: 405, headers: ["Allow": "GET, HEAD"], body: Data("Method Not Allowed".utf8), on: connection)
            return
        }

        guard let fileURL = resolveFileURL(from: request) else {
            send(status: 404, headers: [:], body: Data("Not Found".utf8), on: connection, includeBody: request.method != "HEAD")
            return
        }

        sendFile(fileURL, request: request, on: connection)
    }

    private nonisolated func resolveFileURL(from request: HTTPRequest) -> URL? {
        let components = request.path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2,
              components[0] == "file",
              let rootPath = Self.path(fromURLSafeBase64: String(components[1])) else {
            return nil
        }

        let relativePath = components.dropFirst(2).map(String.init).joined(separator: "/").removingPercentEncoding ?? ""
        let root = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL
        let candidate = relativePath.isEmpty
            ? root.appendingPathComponent("index.html").standardizedFileURL
            : root.appendingPathComponent(relativePath).standardizedFileURL
        guard candidate.path.hasPrefix(root.path + "/") || candidate.path == root.path else {
            return nil
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory) else {
            return nil
        }

        if isDirectory.boolValue {
            let index = candidate.appendingPathComponent("index.html")
            return FileManager.default.fileExists(atPath: index.path) ? index : nil
        }

        return candidate
    }

    private nonisolated static func urlSafeBase64(_ value: String) -> String {
        Data(value.utf8)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private nonisolated static func path(fromURLSafeBase64 value: String) -> String? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        while base64.count % 4 != 0 {
            base64 += "="
        }

        guard let data = Data(base64Encoded: base64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated func sendFile(_ url: URL, request: HTTPRequest, on connection: NWConnection) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let mimeType = MimeTypes.type(for: url)
            let range = parseRange(request.headers["range"], fileSize: fileSize)
            let includeBody = request.method != "HEAD"
            let body = includeBody ? try readFile(url, range: range, fileSize: fileSize) : Data()

            if let range {
                send(
                    status: 206,
                    headers: [
                        "Content-Type": mimeType,
                        "Accept-Ranges": "bytes",
                        "Content-Length": "\(range.length)",
                        "Content-Range": "bytes \(range.start)-\(range.end)/\(fileSize)"
                    ],
                    body: body,
                    on: connection,
                    includeBody: includeBody
                )
            } else {
                send(
                    status: 200,
                    headers: [
                        "Content-Type": mimeType,
                        "Accept-Ranges": "bytes",
                        "Content-Length": "\(fileSize)"
                    ],
                    body: body,
                    on: connection,
                    includeBody: includeBody
                )
            }
        } catch {
            send(status: 500, headers: [:], body: Data("Server Error".utf8), on: connection)
        }
    }

    private nonisolated func readFile(_ url: URL, range: ByteRange?, fileSize: UInt64) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        if let range {
            try handle.seek(toOffset: range.start)
            return try handle.read(upToCount: Int(range.length)) ?? Data()
        }

        if fileSize > 32 * 1024 * 1024 {
            return try handle.readToEnd() ?? Data()
        }

        return try Data(contentsOf: url)
    }

    private nonisolated func parseRange(_ header: String?, fileSize: UInt64) -> ByteRange? {
        guard let header, header.lowercased().hasPrefix("bytes="), fileSize > 0 else { return nil }
        let rawRange = header.dropFirst("bytes=".count)
        let parts = rawRange.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }

        if let start = UInt64(parts[0]), let end = UInt64(parts[1]) {
            guard start <= end, end < fileSize else { return nil }
            return ByteRange(start: start, end: end)
        }

        if let start = UInt64(parts[0]), parts[1].isEmpty {
            guard start < fileSize else { return nil }
            return ByteRange(start: start, end: fileSize - 1)
        }

        if parts[0].isEmpty, let suffixLength = UInt64(parts[1]), suffixLength > 0 {
            let length = min(suffixLength, fileSize)
            return ByteRange(start: fileSize - length, end: fileSize - 1)
        }

        return nil
    }

    private nonisolated func send(
        status: Int,
        headers: [String: String],
        body: Data,
        on connection: NWConnection,
        includeBody: Bool = true
    ) {
        var responseHeaders = headers
        responseHeaders["Connection"] = "close"
        responseHeaders["Server"] = "HTMLServe"
        if responseHeaders["Content-Length"] == nil {
            responseHeaders["Content-Length"] = "\(body.count)"
        }

        let reason = HTTPStatus.reason(for: status)
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        for (key, value) in responseHeaders {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"

        var payload = Data(header.utf8)
        if includeBody {
            payload.append(body)
        }

        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let query: [String: String]
    let headers: [String: String]

    init?(rawRequest: String) {
        let lines = rawRequest.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ", maxSplits: 2)
        guard requestParts.count >= 2 else { return nil }

        method = String(requestParts[0]).uppercased()
        let target = String(requestParts[1])
        let targetParts = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        path = String(targetParts[0])
        query = targetParts.count > 1 ? Self.parseQuery(String(targetParts[1])) : [:]

        var parsedHeaders: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            parsedHeaders[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        headers = parsedHeaders
    }

    private static func parseQuery(_ rawQuery: String) -> [String: String] {
        rawQuery.split(separator: "&").reduce(into: [:]) { result, pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard let key = parts.first else { return }
            result[String(key)] = parts.count > 1 ? String(parts[1]) : ""
        }
    }
}

private struct ByteRange {
    let start: UInt64
    let end: UInt64

    var length: UInt64 {
        end - start + 1
    }
}

private enum HTTPStatus {
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Server Error"
        default: return "OK"
        }
    }
}
