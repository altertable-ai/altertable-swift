import Foundation
#if canImport(Darwin)
    import Darwin
#else
    import Glibc
#endif

/// A deliberately small real HTTP peer for public-API transport tests.
/// It records raw request headers, so tests do not depend on URLProtocol internals.
final class LoopbackHTTPServer {
    struct Request {
        let path: String
        let headers: [String: String]
        let body: Data
    }

    struct Response {
        let status: Int
        let headers: [String: String]
    }

    private let listener: Int32
    private let expectedRequestCount: Int
    private let responseForRequest: (Int, Request) -> Response
    private let condition = NSCondition()
    private var receivedRequests: [Request] = []

    let baseURL: URL

    init(
        expectedRequestCount: Int,
        responseForRequest: @escaping (Int, Request) -> Response
    ) throws {
        self.expectedRequestCount = expectedRequestCount
        self.responseForRequest = responseForRequest

        #if canImport(Darwin)
            let stream = SOCK_STREAM
        #else
            let stream = Int32(SOCK_STREAM.rawValue)
        #endif
        let descriptor = socket(AF_INET, stream, 0)
        guard descriptor >= 0 else { throw POSIXError(.ENFILE) }
        listener = descriptor

        var reuseAddress: Int32 = 1
        guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuseAddress, socklen_t(MemoryLayout.size(ofValue: reuseAddress))) == 0 else {
            close(descriptor)
            throw POSIXError(.ENFILE)
        }

        var address = sockaddr_in()
        #if canImport(Darwin)
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        address.sin_port = 0
        let didBind = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard didBind == 0, listen(descriptor, 8) == 0 else {
            close(descriptor)
            throw POSIXError(.ENFILE)
        }

        var boundAddress = sockaddr_in()
        var addressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard withUnsafeMutablePointer(to: &boundAddress, {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &addressLength)
            }
        }) == 0 else {
            close(descriptor)
            throw POSIXError(.ENFILE)
        }
        baseURL = URL(string: "http://127.0.0.1:\(UInt16(bigEndian: boundAddress.sin_port))")!

        DispatchQueue(label: "ai.altertable.tests.loopback-http").async { [weak self] in
            self?.serve()
        }
    }

    deinit {
        close(listener)
    }

    func requests(timeout: TimeInterval = 3) -> [Request] {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(timeout)
        while receivedRequests.count < expectedRequestCount, condition.wait(until: deadline) {}
        return receivedRequests
    }

    private func serve() {
        for index in 0 ..< expectedRequestCount {
            let connection = accept(listener, nil, nil)
            guard connection >= 0 else { return }
            defer { close(connection) }

            guard let request = readRequest(from: connection) else { return }
            condition.lock()
            receivedRequests.append(request)
            condition.broadcast()
            condition.unlock()

            send(responseForRequest(index, request), to: connection)
        }
    }

    private func readRequest(from connection: Int32) -> Request? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = recv(connection, &buffer, buffer.count, 0)
            guard count > 0 else { return nil }
            data.append(buffer, count: count)
            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { continue }
            let headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            let lines = headerText.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else { return nil }
            let path = requestLine.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 {
                    headers[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
            let contentLength = Int(headers["content-length"] ?? "0") ?? 0
            if data.count >= headerEnd.upperBound + contentLength {
                return Request(
                    path: path,
                    headers: headers,
                    body: Data(data[headerEnd.upperBound ..< headerEnd.upperBound + contentLength])
                )
            }
        }
    }

    private func send(_ response: Response, to connection: Int32) {
        let reason = response.status == 200 ? "OK" : "Temporary Redirect"
        var lines = ["HTTP/1.1 \(response.status) \(reason)"]
        lines.append(contentsOf: response.headers.map { "\($0.key): \($0.value)" })
        lines.append("Content-Length: 0")
        lines.append("Connection: close")
        let bytes = Array((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
        _ = bytes.withUnsafeBytes {
            #if canImport(Darwin)
                Darwin.send(connection, $0.baseAddress, bytes.count, 0)
            #else
                Glibc.send(connection, $0.baseAddress, bytes.count, 0)
            #endif
        }
    }
}
