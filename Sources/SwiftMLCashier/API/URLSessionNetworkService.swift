import Foundation
import os.log

public protocol NetworkService {
    func request<T: Codable>(_ endpoint: Endpoint) async throws -> T
}

public enum APIError: Error {
    case urlSessionError(Error)
    case dataDecodingError(Error)
    case invalidResponse
    case unauthorized
    case rateLimitExceeded
    case missingAPIKey
    case invalidRequest
    case unexpectedStatusCode(Int)
    case serverError
    case networkFailure
    case unknownError
}

public class URLSessionNetworkService: NetworkService {
    private let logger = Logger(subsystem: "com.marcusziade.swiftmlcashier", category: "NetworkService")
    
    public func request<T>(_ endpoint: Endpoint) async throws -> T where T: Codable {
        guard let urlRequest = endpoint.urlRequest else {
            logger.error("Invalid Request: Endpoint URL is nil.")
            throw APIError.invalidRequest
        }
        
        guard urlRequest.allHTTPHeaderFields?["Authorization"] != nil else {
            logger.error("Missing API Key: Authorization header is missing.")
            throw APIError.missingAPIKey
        }
        
        guard urlRequest.allHTTPHeaderFields?["Content-Type"] != nil else {
            logger.error("Invalid Request: Content-Type header is missing.")
            throw APIError.invalidRequest
        }
        
        logger.debug("Requesting URL: \(urlRequest.url?.absoluteString ?? "Unknown URL")")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                logger.error("Invalid Response: Response is not an HTTPURLResponse.")
                throw APIError.invalidResponse
            }
            
            logger.debug("Received HTTP Status Code: \(httpResponse.statusCode)")
            
            switch httpResponse.statusCode {
            case 200...299:
                do {
                    let decodedResponse = try JSONDecoder().decode(T.self, from: data)
                    return decodedResponse
                } catch {
                    logger.error("Data Decoding Error: \(error.localizedDescription)")
                    throw APIError.dataDecodingError(error)
                }
            case 401:
                logger.error("Error: Unauthorized (401).")
                throw APIError.unauthorized
            case 429:
                logger.error("Error: Rate Limit Exceeded (429).")
                throw APIError.rateLimitExceeded
            case 404:
                logger.error("Error: Not Found (404). URL: \(urlRequest.url?.absoluteString ?? "Unknown URL")")
                throw APIError.unexpectedStatusCode(httpResponse.statusCode)
            case 500...599:
                logger.error("Error: Server Error (\(httpResponse.statusCode)).")
                throw APIError.serverError
            default:
                logger.error("Error: Unexpected Status Code (\(httpResponse.statusCode)).")
                throw APIError.unexpectedStatusCode(httpResponse.statusCode)
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    logger.error("Network Failure: \(urlError.localizedDescription)")
                    throw APIError.networkFailure
                default:
                    logger.error("URL Session Error: \(urlError.localizedDescription)")
                    throw APIError.urlSessionError(error)
                }
            } else {
                logger.error("Unknown Error: \(error.localizedDescription)")
                throw APIError.unknownError
            }
        }
    }
}
