import Darwin
import Foundation

final class DOMCaptureBridgeServer: @unchecked Sendable {
    static let port: UInt16 = 17272

    private static let maxRequestBytes = 40 * 1024 * 1024
    private static let headerSeparator = Data("\r\n\r\n".utf8)

    private let queue = DispatchQueue(label: "com.ishu.ClipShot.DOMCaptureBridgeServer")
    private let clipboardHandler: @Sendable (Data) async -> Bool
    private let statusHandler: @Sendable (String) async -> Void

    private var socketFileDescriptor: Int32 = -1
    private var acceptSource: DispatchSourceRead?

    init(
        clipboardHandler: @escaping @Sendable (Data) async -> Bool,
        statusHandler: @escaping @Sendable (String) async -> Void
    ) {
        self.clipboardHandler = clipboardHandler
        self.statusHandler = statusHandler
    }

    func start() {
        queue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func stop() {
        queue.async { [weak self] in
            self?.stopOnQueue()
        }
    }

    private func startOnQueue() {
        guard acceptSource == nil else {
            return
        }

        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            reportStatus("DOM bridge failed to open socket")
            return
        }

        var reuse: Int32 = 1
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = Self.port.bigEndian
        address.sin_addr = in_addr(s_addr: INADDR_LOOPBACK.bigEndian)

        let didBind = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(
                    descriptor,
                    $0,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }

        guard didBind == 0 else {
            Darwin.close(descriptor)
            reportStatus("DOM bridge port \(Self.port) is unavailable")
            return
        }

        guard Darwin.listen(descriptor, SOMAXCONN) == 0 else {
            Darwin.close(descriptor)
            reportStatus("DOM bridge failed to listen")
            return
        }

        socketFileDescriptor = descriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [weak self] in
            self?.acceptAvailableConnections()
        }
        source.setCancelHandler {
            Darwin.close(descriptor)
        }
        acceptSource = source
        source.resume()
        reportStatus("DOM bridge ready on 127.0.0.1:\(Self.port)")
    }

    private func stopOnQueue() {
        acceptSource?.cancel()
        acceptSource = nil
        socketFileDescriptor = -1
    }

    private func acceptAvailableConnections() {
        while true {
            var storage = sockaddr_storage()
            var addressLength = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let clientDescriptor = withUnsafeMutablePointer(to: &storage) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(socketFileDescriptor, $0, &addressLength)
                }
            }

            if clientDescriptor < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR {
                    return
                }
                return
            }

            handleClient(clientDescriptor)
        }
    }

    private func handleClient(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL, 0)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)
        }

        let clipboardHandler = clipboardHandler

        DispatchQueue.global(qos: .userInitiated).async {
            let request = Self.readHTTPRequest(from: descriptor)

            Task {
                let response = await Self.makeResponse(
                    for: request,
                    clipboardHandler: clipboardHandler
                )
                Self.writeAll(response, to: descriptor)
                Darwin.close(descriptor)
            }
        }
    }

    private func reportStatus(_ status: String) {
        let statusHandler = statusHandler
        Task {
            await statusHandler(status)
        }
    }

    private static func readHTTPRequest(from descriptor: Int32) -> HTTPRequest? {
        var timeout = timeval(tv_sec: 2, tv_usec: 0)
        setsockopt(
            descriptor,
            SOL_SOCKET,
            SO_RCVTIMEO,
            &timeout,
            socklen_t(MemoryLayout<timeval>.size)
        )

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)

        while data.count < maxRequestBytes {
            let readCount = Darwin.recv(descriptor, &buffer, buffer.count, 0)
            if readCount > 0 {
                data.append(buffer, count: readCount)
                if let expectedLength = expectedRequestLength(for: data),
                   data.count >= expectedLength {
                    return parseHTTPRequest(data)
                }
            } else {
                break
            }
        }

        return parseHTTPRequest(data)
    }

    private static func expectedRequestLength(for data: Data) -> Int? {
        guard let headerRange = data.range(of: headerSeparator) else {
            return nil
        }

        let headerEnd = headerRange.upperBound
        guard let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .compactMap { line -> Int? in
                let parts = line.split(separator: ":", maxSplits: 1)
                guard parts.count == 2,
                      parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else {
                    return nil
                }
                return Int(parts[1].trimmingCharacters(in: .whitespaces))
            }
            .first ?? 0

        return headerEnd + contentLength
    }

    private static func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let headerRange = data.range(of: headerSeparator),
              let expectedLength = expectedRequestLength(for: data),
              data.count >= expectedLength,
              let headerText = String(data: data[..<headerRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let firstLine = headerText.components(separatedBy: "\r\n").first ?? ""
        let firstLineParts = firstLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard firstLineParts.count >= 2 else {
            return nil
        }

        let bodyStart = headerRange.upperBound
        let body = data[bodyStart..<expectedLength]
        return HTTPRequest(
            method: firstLineParts[0],
            path: firstLineParts[1],
            body: Data(body)
        )
    }

    private static func makeResponse(
        for request: HTTPRequest?,
        clipboardHandler: @Sendable (Data) async -> Bool
    ) async -> Data {
        guard let request else {
            return jsonResponse(statusCode: 400, ok: false, message: "Invalid request")
        }

        if request.method == "OPTIONS" {
            return jsonResponse(statusCode: 204, ok: true, message: "OK")
        }

        if request.method == "GET", request.path.hasPrefix("/health") {
            return jsonResponse(statusCode: 200, ok: true, message: "ClipShot DOM bridge is ready")
        }

        if request.method == "POST", request.path.hasPrefix("/clipboard") {
            return await handleClipboardRequest(request, clipboardHandler: clipboardHandler)
        }

        return jsonResponse(statusCode: 404, ok: false, message: "Unknown route")
    }

    private static func handleClipboardRequest(
        _ request: HTTPRequest,
        clipboardHandler: @Sendable (Data) async -> Bool
    ) async -> Data {
        do {
            let payload = try JSONDecoder().decode(DOMClipboardRequest.self, from: request.body)
            let base64 = payload.pngBase64
                .replacingOccurrences(of: "data:image/png;base64,", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard let pngData = Data(base64Encoded: base64, options: .ignoreUnknownCharacters),
                  !pngData.isEmpty else {
                return jsonResponse(statusCode: 400, ok: false, message: "Invalid PNG payload")
            }

            let didCopy = await clipboardHandler(pngData)
            return jsonResponse(
                statusCode: didCopy ? 200 : 500,
                ok: didCopy,
                message: didCopy ? "OK" : "Clipboard write failed"
            )
        } catch {
            return jsonResponse(statusCode: 400, ok: false, message: "Invalid clipboard JSON")
        }
    }

    private static func jsonResponse(statusCode: Int, ok: Bool, message: String) -> Data {
        let statusText = statusText(for: statusCode)
        let headers = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/plain\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: content-type\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Content-Length: 0\r
        Connection: close\r
        \r
        """

        _ = ok
        _ = message
        return Data(headers.utf8)
    }

    private static func statusText(for statusCode: Int) -> String {
        switch statusCode {
        case 200:
            return "OK"
        case 204:
            return "No Content"
        case 400:
            return "Bad Request"
        case 404:
            return "Not Found"
        case 500:
            return "Internal Server Error"
        default:
            return "OK"
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard var pointer = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            var remaining = data.count
            while remaining > 0 {
                let written = Darwin.send(descriptor, pointer, remaining, 0)

                if written < 0 {
                    if errno == EINTR {
                        continue
                    }
                    if errno == EAGAIN || errno == EWOULDBLOCK {
                        usleep(1_000)
                        continue
                    }
                    return
                }

                guard written > 0 else {
                    return
                }
                pointer = pointer.advanced(by: written)
                remaining -= written
            }
        }
    }
}

private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data
}

private struct DOMClipboardRequest: Decodable {
    let pngBase64: String
}
