//
//  NetworkService.swift
//  Briefeed
//
//  Created by Briefeed Team on 6/21/25.
//

import Foundation

enum NetworkError: LocalizedError {
    case invalidURL
    case noData
    case decodingError
    case serverError(Int)
    case unauthorized
    case rateLimited
    case networkUnavailable
    case unknown(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .noData:
            return "No data received"
        case .decodingError:
            return "Failed to decode response"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unauthorized:
            return "Unauthorized access"
        case .rateLimited:
            return "Rate limit exceeded. Please try again later"
        case .networkUnavailable:
            return "Network connection unavailable"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

protocol NetworkServiceProtocol {
    func request<T: Decodable>(_ endpoint: String, method: HTTPMethod, parameters: [String: Any]?, headers: [String: String]?) async throws -> T
    func requestData(_ endpoint: String, method: HTTPMethod, parameters: [String: Any]?, headers: [String: String]?) async throws -> Data
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

class NetworkService: NetworkServiceProtocol {
    static let shared = NetworkService()
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder.dateDecodingStrategy = .secondsSince1970
    }
    
    func request<T: Decodable>(_ endpoint: String, method: HTTPMethod = .get, parameters: [String: Any]? = nil, headers: [String: String]? = nil) async throws -> T {
        let data = try await requestData(endpoint, method: method, parameters: parameters, headers: headers)
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("Decoding error: \(error)")
            throw NetworkError.decodingError
        }
    }
    
    func requestData(_ endpoint: String, method: HTTPMethod = .get, parameters: [String: Any]? = nil, headers: [String: String]? = nil) async throws -> Data {
        guard let url = URL(string: endpoint) else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = Constants.API.defaultTimeout
        
        // Add headers
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        
        // Add parameters for POST/PUT requests
        if let parameters = parameters, method == .post || method == .put {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        }
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unknown(NSError(domain: "NetworkService", code: 0, userInfo: nil))
            }
            
            print("🌐 HTTP Response: \(httpResponse.statusCode) for \(url)")
            
            switch httpResponse.statusCode {
            case 200...299:
                return data
            case 401:
                throw NetworkError.unauthorized
            case 404:
                print("❌ 404 Not Found: \(url)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("   Response body: \(responseString.prefix(200))...")
                }
                throw NetworkError.serverError(httpResponse.statusCode)
            case 429:
                throw NetworkError.rateLimited
            case 400...499:
                throw NetworkError.serverError(httpResponse.statusCode)
            case 500...599:
                throw NetworkError.serverError(httpResponse.statusCode)
            default:
                throw NetworkError.serverError(httpResponse.statusCode)
            }
        } catch let error as NetworkError {
            throw error
        } catch {
            if (error as NSError).code == NSURLErrorNotConnectedToInternet {
                throw NetworkError.networkUnavailable
            }
            throw NetworkError.unknown(error)
        }
    }
}