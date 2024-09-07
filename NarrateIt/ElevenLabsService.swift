import Foundation
import os


public class ElevenLabsService {
    private let apiKey: String
    private let baseURL = "https://api.elevenlabs.io/v1"
    private let logger = Logger(subsystem: "com.yourcompany.NarrateIt", category: "ElevenLabsService")
    
    public init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    public func synthesizeSpeech(text: String, voiceID: String, completion: @escaping (Result<(Data, [WordTiming]), Error>) -> Void) {
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
            ],
            "return_word_timings": true  // Add this line
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            logger.error("Failed to serialize request body: \(error.localizedDescription)")
            completion(.failure(error))
            return
        }
        
        logger.info("Sending request to Eleven Labs: \(endpoint)")
        
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30 // Adjust as needed
        let session = URLSession(configuration: config)

        let task = session.dataTask(with: request) { data, response, error in
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
                completion(.failure(NSError(domain: "ElevenLabsService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP status code: \(httpResponse.statusCode)"])))
                return
            }
            
            guard let data = data else {
                self.logger.error("No data received in response")
                completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                return
            }
            
            // Log the raw response data
            self.logger.info("Raw response data size: \(data.count) bytes")

            // Check if the response is audio data directly
            if let audioContentType = httpResponse.allHeaderFields["Content-Type"] as? String,
               audioContentType.contains("audio/") {
                self.logger.info("Response appears to be audio data. Size: \(data.count) bytes")
                // Since we don't have word timings, we'll return an empty array
                completion(.success((data, [])))
                return
            }

            // If it's not audio data, try to parse it as JSON
            do {
                if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                    self.logger.info("Parsed JSON response: \(json)")

                    if let error = json["detail"] as? String {
                        self.logger.error("API error: \(error)")
                        completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: error])))
                        return
                    }

                    if let audioBase64 = json["audio"] as? String,
                       let audioData = Data(base64Encoded: audioBase64) {
                        let wordTimings = json["word_timings"] as? [[String: Any]] ?? []
                        let parsedTimings = wordTimings.compactMap { timing -> WordTiming? in
                            guard let word = timing["word"] as? String,
                                  let start = timing["start"] as? Double,
                                  let end = timing["end"] as? Double,
                                  let startIndex = timing["start_index"] as? Int,
                                  let endIndex = timing["end_index"] as? Int else {
                                return nil
                            }
                            return WordTiming(word: word, start: start, end: end, startIndex: startIndex, endIndex: endIndex)
                        }
                        
                        self.logger.info("Successfully received data from Eleven Labs. Audio size: \(audioData.count) bytes, Word timings: \(parsedTimings.count)")
                        completion(.success((audioData, parsedTimings)))
                    } else {
                        self.logger.error("Audio data not found in JSON response")
                        completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Audio data not found in JSON response"])))
                    }
                } else {
                    self.logger.error("Failed to parse JSON")
                    completion(.failure(NSError(domain: "ElevenLabsService", code: 0, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON"])))
                }
            } catch {
                self.logger.error("Failed to parse response: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        
        task.resume()
        logger.info("Request sent to Eleven Labs")
    }
}

// Remove this if it exists
// public struct WordTiming { ... }
