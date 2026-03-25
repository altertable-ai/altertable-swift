//
//  Requester.swift
//  Altertable
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum APIError: LocalizedError, Sendable {
    case invalidURL
    case httpError(Int)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case let .httpError(code):
            return "HTTP error \(code)"
        case let .networkError(error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

final class Requester {
    private let apiKey: String
    private let session: URLSession

    // `retryBaseDelay` is a test-only override; guard all access through `delayQueue`.
    private let delayQueue = DispatchQueue(label: "ai.altertable.requester.delay")
    private var _retryBaseDelay: Double = SDKConstants.httpRetryBaseDelaySeconds
    var retryBaseDelay: Double {
        get { delayQueue.sync { _retryBaseDelay } }
        set { delayQueue.sync { _retryBaseDelay = newValue } }
    }

    init(apiKey: String, requestTimeout: TimeInterval, session: URLSession? = nil) {
        self.apiKey = apiKey

        if let session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            // Snapshot timeout at init time — safe because init runs on the
            // Altertable serial queue before any concurrent access begins.
            sessionConfig.timeoutIntervalForRequest = requestTimeout
            sessionConfig.timeoutIntervalForResource = requestTimeout
            self.session = URLSession(configuration: sessionConfig)
        }
    }

    // MARK: - Public send methods

    // `baseURL` is passed by the caller (Altertable's serial queue) so this class
    // never reads shared config from an arbitrary thread.

    func send<P: APIPayload>(_ payload: P, baseURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: P.endpoint, baseURL: baseURL, payload: payload, completion: completion)
    }

    /// Sends a batch as a JSON array body to the same endpoint as a single payload.
    func sendBatch<P: APIPayload>(_ payloads: [P], baseURL: URL, completion: @escaping (Result<Void, Error>) -> Void) {
        guard !payloads.isEmpty else {
            completion(.success(()))
            return
        }
        sendBatchRequest(endpoint: P.endpoint, baseURL: baseURL, payloads: payloads, completion: completion)
    }

    private func sendRequest(
        endpoint: String,
        baseURL: URL,
        payload: some Encodable,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Use X-API-Key as the primary authentication method
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        execute(request: request, attempt: 1, maxAttempts: SDKConstants.httpRetryMaxAttempts, completion: completion)
    }

    private func sendBatchRequest<P: APIPayload>(
        endpoint: String,
        baseURL: URL,
        payloads: [P],
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent(endpoint)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(payloads)
        } catch {
            completion(.failure(error))
            return
        }

        execute(request: request, attempt: 1, maxAttempts: SDKConstants.httpRetryMaxAttempts, completion: completion)
    }

    private func execute(
        request: URLRequest,
        attempt: Int,
        maxAttempts: Int,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            guard let self else { return }

            if let error {
                self.retryOrFail(
                    request: request,
                    attempt: attempt,
                    maxAttempts: maxAttempts,
                    error: error,
                    completion: completion
                )
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                let status = httpResponse.statusCode
                if (500 ... 599).contains(status) || status == 429 {
                    self.retryOrFail(
                        request: request,
                        attempt: attempt,
                        maxAttempts: maxAttempts,
                        error: APIError.httpError(status),
                        completion: completion
                    )
                    return
                }

                guard (200 ... 299).contains(status) else {
                    completion(.failure(APIError.httpError(status)))
                    return
                }
            }

            completion(.success(()))
        }
        task.resume()
    }

    private func retryOrFail(
        request: URLRequest,
        attempt: Int,
        maxAttempts: Int,
        error: Error,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard attempt < maxAttempts else {
            completion(.failure(error))
            return
        }

        let attemptIndex = attempt - 1
        let exponentialDelay = retryBaseDelay * pow(2.0, Double(attemptIndex))
        let jitterFactor = 0.5 + Double.random(in: 0 ..< 1)
        let delay = exponentialDelay * jitterFactor
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.execute(request: request, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
        }
    }
}

extension Requester {
    /// Whether a failed delivery should be retried later by the batcher (after HTTP-level retries are exhausted).
    static func isRetryableDeliveryError(_ error: Error) -> Bool {
        if error is URLError {
            return true
        }
        guard let apiError = error as? APIError else {
            return false
        }
        switch apiError {
        case .networkError:
            return true
        case let .httpError(code):
            return code == 429 || code >= 500
        case .invalidURL:
            return false
        }
    }
}
