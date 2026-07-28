import Foundation
import Network

@MainActor
final class LocalHTTPServer: ObservableObject {
    @Published private(set) var port: UInt16?
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var allowsLAN = false

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "com.engagendy.HTMLServe.http")

    func start() async throws {
        if isRunning, port != nil, listener != nil { return }

        if isStarting {
            _ = await waitUntilReady()
            if isRunning, port != nil, listener != nil { return }
        }

        if listener != nil {
            stop()
        }

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        // Bind to loopback unless the user explicitly enabled classroom
        // sharing; classrooms share Wi-Fi networks.
        if !allowsLAN {
            parameters.requiredLocalEndpoint = NWEndpoint.hostPort(host: .ipv4(.loopback), port: .any)
        }
        isStarting = true

        let listener: NWListener
        do {
            listener = try NWListener(using: parameters, on: .any)
        } catch {
            isStarting = false
            throw error
        }

        listener.service = nil
        listener.stateUpdateHandler = { [weak self, weak listener] state in
            guard let listener else { return }
            Task { @MainActor in
                guard let self, self.listener === listener else { return }

                switch state {
                case .ready:
                    self.port = listener.port?.rawValue
                    self.isRunning = listener.port != nil
                    self.isStarting = false
                case .waiting:
                    self.port = nil
                    self.isRunning = false
                    self.isStarting = false
                case .failed, .cancelled:
                    self.listener = nil
                    self.port = nil
                    self.isRunning = false
                    self.isStarting = false
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
        _ = await waitUntilReady()
    }

    func restart() async throws {
        stop()
        try await start()
        _ = await waitUntilReady()
    }

    /// Classroom sharing: rebinds the server to all interfaces so devices on
    /// the same Wi-Fi can open project pages. Note the port changes on restart.
    func setLANSharing(_ enabled: Bool) async {
        guard allowsLAN != enabled else { return }
        allowsLAN = enabled
        if enabled {
            triggerLocalNetworkPermissionPrompt()
        }
        try? await restart()
    }

    /// iOS only shows the Local Network permission dialog when the app engages
    /// with the network; a throwaway broadcast makes the prompt appear the
    /// moment the teacher enables sharing instead of when a student connects.
    private nonisolated func triggerLocalNetworkPermissionPrompt() {
        let connection = NWConnection(host: "255.255.255.255", port: 9, using: .udp)
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                connection.send(content: Data("HTMLServe".utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) {
            connection.cancel()
        }
    }

    func lanURL(for project: ProjectItem, file: ProjectFile) -> URL? {
        guard allowsLAN,
              let url = url(for: project, file: file),
              let address = Self.lanIPAddress(),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = address
        return components.url
    }

    /// The device's IPv4 address on Wi-Fi (en0), for sharing with the classroom.
    static func lanIPAddress() -> String? {
        var ifaddrPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPointer) == 0, let firstAddr = ifaddrPointer else { return nil }
        defer { freeifaddrs(ifaddrPointer) }

        var fallback: String?
        for pointer in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let interface = pointer.pointee
            guard let addressPointer = interface.ifa_addr,
                  addressPointer.pointee.sa_family == UInt8(AF_INET) else { continue }
            let flags = Int32(interface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0 else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(
                addressPointer,
                socklen_t(addressPointer.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            ) == 0 else { continue }

            let address = String(cString: host)
            let name = String(cString: interface.ifa_name)
            if name == "en0" { return address }
            if fallback == nil { fallback = address }
        }
        return fallback
    }

    func stop() {
        listener?.cancel()
        listener = nil
        port = nil
        isRunning = false
        isStarting = false
    }

    func url(for project: ProjectItem, file: ProjectFile) -> URL? {
        guard let port else { return nil }
        let encodedRoot = Self.urlSafeBase64(project.rootURL.path)
        let encodedFile = file.relativePath.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        return URL(string: "http://127.0.0.1:\(port)/file/\(encodedRoot)/\(encodedFile)")
    }

    private nonisolated func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func waitUntilReady() async -> Bool {
        for _ in 0..<20 {
            if isRunning, port != nil, listener != nil {
                return true
            }

            if !isStarting, listener == nil {
                return false
            }

            try? await Task.sleep(nanoseconds: 50_000_000)
        }

        return isRunning && port != nil && listener != nil
    }

    private nonisolated static let maxRequestHeaderBytes = 256 * 1024
    private nonisolated static let streamingThreshold: UInt64 = 8 * 1024 * 1024
    private nonisolated static let streamingChunkSize = 1024 * 1024

    private nonisolated func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                var nextBuffer = buffer
                nextBuffer.append(data)

                if let headerEnd = nextBuffer.range(of: Data("\r\n\r\n".utf8)) {
                    let headerData = nextBuffer.subdata(in: nextBuffer.startIndex..<headerEnd.upperBound)
                    let remainder = nextBuffer.subdata(in: headerEnd.upperBound..<nextBuffer.endIndex)
                    self.respond(to: headerData, remainder: remainder, on: connection)
                    return
                }

                guard nextBuffer.count <= Self.maxRequestHeaderBytes else {
                    self.send(status: 400, headers: [:], body: Data("Bad Request".utf8), on: connection, keepAlive: false, remainder: Data())
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

    private nonisolated func respond(to requestData: Data, remainder: Data, on connection: NWConnection) {
        guard let rawRequest = String(data: requestData, encoding: .utf8),
              let request = HTTPRequest(rawRequest: rawRequest) else {
            send(status: 400, headers: [:], body: Data("Bad Request".utf8), on: connection, keepAlive: false, remainder: Data())
            return
        }

        let keepAlive = request.headers["connection"]?.lowercased() != "close"

        guard request.method == "GET" || request.method == "HEAD" else {
            send(status: 405, headers: ["Allow": "GET, HEAD"], body: Data("Method Not Allowed".utf8), on: connection, keepAlive: keepAlive, remainder: remainder)
            return
        }

        guard let fileURL = resolveFileURL(from: request) else {
            send(status: 404, headers: [:], body: Data("Not Found".utf8), on: connection, includeBody: request.method != "HEAD", keepAlive: keepAlive, remainder: remainder)
            return
        }

        sendFile(fileURL, request: request, on: connection, keepAlive: keepAlive, remainder: remainder)
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

    private nonisolated func sendFile(_ url: URL, request: HTTPRequest, on connection: NWConnection, keepAlive: Bool, remainder: Data) {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let fileSize = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
            let modificationDate = attributes[.modificationDate] as? Date
            let mimeType = MimeTypes.type(for: url)
            let range = parseRange(request.headers["range"], fileSize: fileSize)
            let includeBody = request.method != "HEAD"

            var headers = [
                "Content-Type": mimeType,
                "Accept-Ranges": "bytes",
                "Cache-Control": "no-cache"
            ]
            if let modificationDate {
                headers["Last-Modified"] = Self.httpDate(from: modificationDate)
            }

            if range == nil,
               let modificationDate,
               let clientDate = Self.date(fromHTTPDate: request.headers["if-modified-since"]),
               UInt64(modificationDate.timeIntervalSince1970) <= UInt64(clientDate.timeIntervalSince1970) {
                headers["Content-Length"] = "0"
                send(status: 304, headers: headers, body: Data(), on: connection, includeBody: false, keepAlive: keepAlive, remainder: remainder)
                return
            }

            let status: Int
            let bodyStart: UInt64
            let bodyLength: UInt64
            if let range {
                status = 206
                bodyStart = range.start
                bodyLength = range.length
                headers["Content-Length"] = "\(range.length)"
                headers["Content-Range"] = "bytes \(range.start)-\(range.end)/\(fileSize)"
            } else {
                status = 200
                bodyStart = 0
                bodyLength = fileSize
                headers["Content-Length"] = "\(fileSize)"
            }

            guard includeBody, bodyLength > 0 else {
                send(status: status, headers: headers, body: Data(), on: connection, includeBody: false, keepAlive: keepAlive, remainder: remainder)
                return
            }

            if bodyLength > Self.streamingThreshold {
                let handle = try FileHandle(forReadingFrom: url)
                try handle.seek(toOffset: bodyStart)
                let header = headerData(status: status, headers: headers, keepAlive: keepAlive)
                connection.send(content: header, completion: .contentProcessed { [weak self] error in
                    guard let self else { return }
                    if error != nil {
                        try? handle.close()
                        connection.cancel()
                        return
                    }
                    self.streamBody(from: handle, remaining: bodyLength, on: connection, keepAlive: keepAlive, remainder: remainder)
                })
                return
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            try handle.seek(toOffset: bodyStart)
            let body = try handle.read(upToCount: Int(bodyLength)) ?? Data()
            send(status: status, headers: headers, body: body, on: connection, keepAlive: keepAlive, remainder: remainder)
        } catch {
            send(status: 500, headers: [:], body: Data("Server Error".utf8), on: connection, keepAlive: false, remainder: Data())
        }
    }

    private nonisolated func streamBody(
        from handle: FileHandle,
        remaining: UInt64,
        on connection: NWConnection,
        keepAlive: Bool,
        remainder: Data
    ) {
        guard remaining > 0 else {
            try? handle.close()
            finish(on: connection, keepAlive: keepAlive, remainder: remainder)
            return
        }

        let chunkSize = Int(min(remaining, UInt64(Self.streamingChunkSize)))
        guard let chunk = try? handle.read(upToCount: chunkSize), !chunk.isEmpty else {
            try? handle.close()
            connection.cancel()
            return
        }

        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil {
                try? handle.close()
                connection.cancel()
                return
            }
            self.streamBody(
                from: handle,
                remaining: remaining - UInt64(chunk.count),
                on: connection,
                keepAlive: keepAlive,
                remainder: remainder
            )
        })
    }

    private nonisolated func finish(on connection: NWConnection, keepAlive: Bool, remainder: Data) {
        if keepAlive {
            receive(on: connection, buffer: remainder)
        } else {
            connection.cancel()
        }
    }

    private nonisolated static let httpDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter
    }()

    private nonisolated static func httpDate(from date: Date) -> String {
        httpDateFormatter.string(from: date)
    }

    private nonisolated static func date(fromHTTPDate value: String?) -> Date? {
        guard let value else { return nil }
        return httpDateFormatter.date(from: value)
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

    private nonisolated func headerData(status: Int, headers: [String: String], keepAlive: Bool, bodyCount: Int? = nil) -> Data {
        var responseHeaders = headers
        responseHeaders["Connection"] = keepAlive ? "keep-alive" : "close"
        responseHeaders["Server"] = "HTMLServe"
        if responseHeaders["Content-Length"] == nil, let bodyCount {
            responseHeaders["Content-Length"] = "\(bodyCount)"
        }

        let reason = HTTPStatus.reason(for: status)
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        for (key, value) in responseHeaders {
            header += "\(key): \(value)\r\n"
        }
        header += "\r\n"
        return Data(header.utf8)
    }

    private nonisolated func send(
        status: Int,
        headers: [String: String],
        body: Data,
        on connection: NWConnection,
        includeBody: Bool = true,
        keepAlive: Bool,
        remainder: Data
    ) {
        var payload = headerData(status: status, headers: headers, keepAlive: keepAlive, bodyCount: body.count)
        if includeBody {
            payload.append(body)
        }

        connection.send(content: payload, completion: .contentProcessed { [weak self] error in
            guard let self, error == nil else {
                connection.cancel()
                return
            }
            self.finish(on: connection, keepAlive: keepAlive, remainder: remainder)
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
        case 304: return "Not Modified"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 500: return "Server Error"
        default: return "OK"
        }
    }
}
