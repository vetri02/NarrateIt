import Foundation
import os

public class ElevenLabsService {
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "ElevenLabsService")

    public init(apiKey: String) {
        self.apiKey = apiKey
        logger.info("ElevenLabsService initialized with API key: \(apiKey.prefix(5))...") // Log first 5 characters of the API key
    }
    
    public func synthesizeSpeech(text: String, voiceID: String, completion: @escaping (Result<Data, Error>) -> Void) {
        let endpoint = "\(baseURL)/text-to-speech/\(voiceID)"
        guard let url = URL(string: endpoint) else {
            logger.error("Invalid URL: \(endpoint)")
            completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "xi-api-key")
        
        let body: [String: Any] = [
            "text": text,
            "model_id": "eleven_monolingual_v1",
            "voice_settings": [
                "stability": 0.5,
                "similarity_boost": 0.5
            ]
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            logger.error("Failed to serialize request body: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        logger.info("Sending request to Eleven Labs: \(endpoint)")
        
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                self.logger.error("Network error: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else {
                self.logger.error("Invalid response: not an HTTP response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                return
            }
            
            self.logger.info("Received response from Eleven Labs. Status code: \(httpResponse.statusCode)")
            
            guard (200...299).contains(httpResponse.statusCode) else {
                self.logger.error("HTTP error: status code \(httpResponse.statusCode)")
                if let data = data, let responseBody = String(data: data, encoding: .utf8) {
                    self.logger.error("Response body: \(responseBody)")
                }
                completion(.failure(NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received in response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            self.logger.info("Successfully received audio data. Size: \(data.count) bytes")
            completion(.success(data))
        }
        
        task.resume()
        logger.info("Request sent to Eleven Labs")
    }
}
