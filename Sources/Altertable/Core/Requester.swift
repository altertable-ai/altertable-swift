//
//  Requester.swift
//  Altertable
//

import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

enum APIError: Error {
    case invalidURL
    case httpError(Int)
    case networkError(Error)
    case decodingError(Error)
}

class Requester {
    private let apiKey: String
    private let session: URLSession

    // `retryBaseDelay` is a test-only override; guard all access through `delayQueue`.
    private let delayQueue = DispatchQueue(label: "ai.altertable.requester.delay")
    private var _retryBaseDelay: Double = 2.0
    var retryBaseDelay: Double {
        get { delayQueue.sync { _retryBaseDelay } }
        set { delayQueue.sync { _retryBaseDelay = newValue } }
    }

    /// ConfigRef exists so that Altertable can hold a reference to it for the
    /// URLSession timeout snapshot taken at init time. Requester does NOT read it
    /// after init — all config values needed per-request are passed explicitly to
    /// avoid cross-thread access on arbitrary URLSession callback threads.
    final class ConfigRef {
        var config: AltertableConfig
        init(_ config: AltertableConfig) {
            self.config = config
        }
    }

    init(apiKey: String, configRef: ConfigRef, session: URLSession? = nil) {
        self.apiKey = apiKey

        if let session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            // Snapshot timeout at init time — safe because init runs on the
            // Altertable serial queue before any concurrent access begins.
            sessionConfig.timeoutIntervalForRequest = configRef.config.requestTimeout
            sessionConfig.timeoutIntervalForResource = configRef.config.requestTimeout
            self.session = URLSession(configuration: sessionConfig)
        }
    }

    // MARK: - Public send methods

    // `baseURL` is passed by the caller (Altertable's serial queue) so this class
    // never reads shared config from an arbitrary thread.

    func send(_ payload: TrackPayload, baseURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/track", baseURL: baseURL, payload: payload, completion: completion)
    }

    func send(_ payload: IdentifyPayload, baseURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/identify", baseURL: baseURL, payload: payload, completion: completion)
    }

    func send(_ payload: AliasPayload, baseURL: String, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/alias", baseURL: baseURL, payload: payload, completion: completion)
    }

    private func sendRequest(
        endpoint: String,
        baseURL: String,
        payload: some Encodable,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard let url = URL(string: "\(baseURL)\(endpoint)") else {
            completion(.failure(APIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(payload)
        } catch {
            completion(.failure(error))
            return
        }

        execute(request: request, attempt: 1, maxAttempts: 3, completion: completion)
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

        let delay = pow(retryBaseDelay, Double(attempt))
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.execute(request: request, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion)
        }
    }
}
