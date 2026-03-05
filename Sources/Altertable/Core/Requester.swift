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
                completion(.failure(APIError.networkError(error)))
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
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
