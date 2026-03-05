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
    private let config: AltertableConfig
    private let session: URLSession
    
    init(config: AltertableConfig, session: URLSession? = nil) {
        self.config = config
        
        if let session = session {
            self.session = session
        } else {
            let sessionConfig = URLSessionConfiguration.default
            sessionConfig.timeoutIntervalForRequest = config.requestTimeout
            sessionConfig.timeoutIntervalForResource = config.requestTimeout
            self.session = URLSession(configuration: sessionConfig)
        }
    }
    
    func send(_ payload: TrackPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/track", payload: payload, completion: completion)
    }
    
    func send(_ payload: IdentifyPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/identify", payload: payload, completion: completion)
    }
    
    func send(_ payload: AliasPayload, completion: @escaping (Result<Void, Error>) -> Void) {
        sendRequest(endpoint: "/alias", payload: payload, completion: completion)
    }
    
    private func sendRequest<T: Encodable>(endpoint: String, payload: T, completion: @escaping (Result<Void, Error>) -> Void) {
        let url = URL(string: "\(config.baseURL)\(endpoint)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
        components.queryItems = [URLQueryItem(name: "apiKey", value: config.apiKey)]
        request.url = components.url
        
        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(payload)
        } catch {
            completion(.failure(error))
            return
        }
        
        let task = session.dataTask(with: request) { _, response, error in
            if let error = error {
                // Retry? For now we just fail, but the Queue in Altertable (Phase 11) says "TODO: Re-queue on recoverable error"
                // Implementing retry at Requester level is better for transient network errors.
                self.retry(request: request, attempt: 1, maxAttempts: 3, completion: completion, originalError: error)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if (500...599).contains(httpResponse.statusCode) || httpResponse.statusCode == 429 {
                     self.retry(request: request, attempt: 1, maxAttempts: 3, completion: completion, originalError: APIError.httpError(httpResponse.statusCode))
                     return
                }
                
                guard (200...299).contains(httpResponse.statusCode) else {
                    completion(.failure(APIError.httpError(httpResponse.statusCode)))
                    return
                }
            }
            
            completion(.success(()))
        }
        
        task.resume()
    }
    
    private func retry(request: URLRequest, attempt: Int, maxAttempts: Int, completion: @escaping (Result<Void, Error>) -> Void, originalError: Error) {
        guard attempt < maxAttempts else {
            completion(.failure(originalError))
            return
        }
        
        let delay = pow(2.0, Double(attempt)) // Exponential backoff: 2s, 4s, 8s...
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            let task = self.session.dataTask(with: request) { _, response, error in
                if let error = error {
                    self.retry(request: request, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion, originalError: error)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse {
                    if (500...599).contains(httpResponse.statusCode) || httpResponse.statusCode == 429 {
                        self.retry(request: request, attempt: attempt + 1, maxAttempts: maxAttempts, completion: completion, originalError: APIError.httpError(httpResponse.statusCode))
                        return
                    }
                    
                    guard (200...299).contains(httpResponse.statusCode) else {
                        completion(.failure(APIError.httpError(httpResponse.statusCode)))
                        return
                    }
                }
                
                completion(.success(()))
            }
            task.resume()
        }
    }
}
